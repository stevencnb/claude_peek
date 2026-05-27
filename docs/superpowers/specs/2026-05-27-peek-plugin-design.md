# `peek` — read-only repo inspector plugin (design)

**Date:** 2026-05-27
**Author:** Steven Chang
**Status:** Design — awaiting review before implementation plan

## 1. Purpose

`peek` is an installable Claude Code plugin that provides a **read-only repository
inspector** callable from inside a session via `/peek <free-form English>`. It lets
the user inspect git state, folder structure, and file contents **without modifying
anything** and **without polluting the main session's context** (the work happens in
a subagent whose results are summarized back).

The user works on a remote laptop with **no SSH / no GUI / no browser preview** —
Claude Code is the only channel, so all output must return as text in the session.

## 2. Hard constraints (fixed — not up for redesign)

1. Mechanism must be a **read-only subagent** so the main writing/coding thread's
   context stays clean. (`/btw` is not an option — it has no tool access.)
2. The subagent must **never** mutate the repo or filesystem. Read-only is a **hard
   safety requirement**, enforced by a gate — not by trusting the model.
3. Everything comes back as **text** in the session (no SSH, GUI, browser).
4. Must inspect, read-only:
   - **git:** status, log, diff (staged + unstaged), show, branch
   - **folder structure:** tree-style view, respecting `.gitignore` where sensible
   - **arbitrary file contents**, including markdown rendered verbatim
5. Installable as a plugin (`/plugin install`) and usable across repos.

## 3. Decisions locked during brainstorming

- **Name:** `peek` — command `/peek`, agent `peek-inspector`, plugin `peek`.
  (The repo dir `claude_peek` and the `/peek` example were typos; the "take a quick
  look" pun fits a read-only inspector.)
- **Safety model:** a **three-way guard** that leverages Claude Code's _native_
  permission system + the user's own config, with an unconditional hard-deny floor.
  See §6.
- **Process:** design → committed spec (this doc) → formal implementation plan
  (`writing-plans`) → build.

## 4. Verified platform facts (basis for the design)

All confirmed against canonical docs at `code.claude.com/docs` (2026-05):

- **Subagent identity is visible to hooks.** PreToolUse hook stdin JSON includes
  `agent_id` and `agent_type`. For custom subagents, `agent_type` = the agent's
  frontmatter `name`. Both are **absent on main-thread calls**. Docs: _"Use this to
  distinguish subagent hook calls from main-thread calls."_ (hooks reference)
  → **This is the linchpin:** a session-wide hook can scope enforcement to
  `agent_type == "peek-inspector"` and no-op everywhere else, so the **main coding
  session is never affected.**
- **Plugin subagents cannot set `permissionMode`/`hooks`/`mcpServers`** (ignored for
  plugin-shipped agents, for security). `settings.json` permission rules apply
  **session-wide, not per-subagent.** → The only per-subagent enforcement point is the
  **hook keyed on `agent_type`**; we cannot lock the agent down via its own mode.
- **Agent frontmatter supports** `name, description, model, effort, maxTurns, tools,
disallowedTools, skills, memory, background, isolation` (comma-separated form, e.g.
  `tools: Read, Glob, Grep, Bash`).
- **PreToolUse decision mechanism:** exit 0 + stdout JSON
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny|ask|allow","permissionDecisionReason":"..."}}`.
  Exit 2 = blocking error (stderr → model). Other non-zero = non-blocking (call
  proceeds) → **must not be used as a deny path** (fails open).
- **Hooks compose with permission rules:** PreToolUse hooks run **before** the
  permission prompt. A hook can `deny`, force `ask`, or `allow`. **Deny rules always
  win** (deny → ask → allow precedence); a user `deny` rule still blocks even if the
  hook returned `allow`, and a user `ask` rule still prompts. → The user's own config
  composes on top of the guard exactly as they wanted.
- **Claude Code already auto-runs a built-in read-only Bash set with no prompt in
  every mode:** `ls, cat, echo, pwd, head, tail, grep, find, wc, which, diff, stat,
du, cd`, and **read-only forms of git**. → Routine inspection is already friction-free;
  the guard adds a safety floor + grey-zone escalation rather than re-implementing this.
- **Arg-constraining Bash allow patterns are explicitly "fragile"** per the docs,
  which **recommend PreToolUse hooks** for this. → Validates moving the decision into
  the guard hook instead of a brittle baked-in allow pattern.
- **`${CLAUDE_PLUGIN_ROOT}`** expands inside `hooks.json` command strings; in shell
  form, **double-quote it**: `"${CLAUDE_PLUGIN_ROOT}"/scripts/peek-guard.sh`. The dir
  is **ephemeral** (changes on update, old copy cleaned ~7 days) → **the guard must not
  write state/logs there.**
- **Layout:** components live at plugin root (`agents/`, `commands/`, `hooks/`,
  `scripts/`); only `plugin.json` lives in `.claude-plugin/`. `hooks/hooks.json` is the
  hook location. `plugin.json` requires only `name`.

## 5. Architecture & components

Built onto the existing empty scaffolding under `plugins/peek/`.

| File                                      | Role                                                               |
| ----------------------------------------- | ------------------------------------------------------------------ |
| `plugins/peek/.claude-plugin/plugin.json` | Manifest: `name: peek`, `version: 0.1.0`, `description`, `author`. |
| `plugins/peek/agents/peek-inspector.md`   | The inspector subagent (§7).                                       |
| `plugins/peek/commands/peek.md`           | `/peek <free-form>` → dispatch to `peek-inspector` (§8).           |
| `plugins/peek/hooks/hooks.json`           | PreToolUse matcher `Bash` → guard script.                          |
| `plugins/peek/scripts/peek-guard.sh`      | The three-way read-only guard (§6).                                |
| `plugins/peek/README.md`                  | Usage, the `jq` dependency, the safety model.                      |
| `.claude-plugin/marketplace.json`         | Marketplace entry so `/plugin install peek` works.                 |
| `README.md` (repo root)                   | Install instructions (add this repo as a marketplace).             |

Data flow: user types `/peek what changed` → the `peek` command instructs the main
agent to invoke the `peek-inspector` subagent with `$ARGUMENTS` → the subagent chooses
read-only commands/tools → each Bash call passes through `peek-guard.sh` (which acts
only because `agent_type == peek-inspector`) → allowed output returns to the subagent →
subagent returns raw output → main agent relays it. The main session's own Bash calls
are untouched (guard no-ops when `agent_type != peek-inspector`).

## 6. The safety model — `peek-guard.sh` (the crux)

A single PreToolUse hook on `Bash`, session-wide, but **gated on subagent identity**.

### 6.1 Decision algorithm

1. **Scope gate (jq-free, robust).** Read stdin. If it does **not** match
   `"agent_type"\s*:\s*"peek-inspector"` → **`exit 0` with no output.** This is the
   first thing the script does, so the **main session and all other agents are wholly
   unaffected**, even if `jq` is missing or the script later errors.
2. **In-inspector parsing.** Extract `tool_input.command` (prefer `jq`; if `jq` is
   absent, **fail closed → deny** with a reason telling the user to install `jq`).
   This fail-closed only triggers _inside_ the inspector, so it can never break the
   main session.
3. **Classify the command (fail-closed):**
   - **DENY** (the hard floor; mechanism = `permissionDecision: deny`). Intended to
     hold regardless of session permission mode because PreToolUse hooks run before
     permission evaluation. **Caveat:** docs only _explicitly_ guarantee mode-independent
     blocking for **exit code 2**; whether `permissionDecision: deny` also holds under
     `bypassPermissions` must be verified in testing (§11) — if it doesn't, the deny
     path falls back to `exit 2`.
     - Output redirection in any form: `>`, `>>`, `2>`, `&>` (denied even if quoted —
       acceptable, since read-only inspection rarely needs a literal `>`).
     - Command/process substitution: `$( … )`, backticks, `<( … )`, `>( … )`.
     - Any segment whose program is a known mutator/escape:
       `rm, rmdir, mv, cp, mkdir, touch, ln, dd, tee, truncate, shred, chmod, chown,
install, rsync, sed -i, sudo, eval, exec, source, ., env -…, awk, perl, python,
python3, node, ruby, bash, sh, zsh, npm, yarn, pnpm, pip, make, curl, wget,
scp, ssh, nc`.
     - `git` **write** subcommands: `add, commit, push, pull, fetch, merge, rebase,
reset, restore, checkout, switch, clean, rm, mv, init, clone, am, apply,
cherry-pick, revert, gc, prune, repack, stash push|pop|apply|drop|clear|save,
worktree add|remove, submodule, config <set>, branch -d|-D|-m|-f,
tag -a|-d|-f, remote add|remove|rename|set-url, update-index, notes add`.
     - `find` with `-delete`, `-exec`, `-execdir`, `-fprintf`, `-fls`, `-ok`.
   - **ALLOW** (explicit, so routine `/peek` never prompts) — read-only inspection set:
     `ls, tree, cat, head, tail, wc, stat, file, du, pwd, echo, which, basename,
dirname, realpath, readlink, nl, column, sort (no -o), uniq, cut, grep, egrep,
fgrep`, and `git` **read** subcommands: `status, log, diff, show, branch (list),
remote -v|show|get-url, tag (list), rev-parse, ls-files, ls-tree, cat-file,
blame, shortlog, describe, show-ref, reflog (read), for-each-ref, name-rev,
whatchanged, grep, config --get|--list|-l, stash list|show, worktree list`.
   - **ASK** — anything else (unknown program, or a recognized program in an
     unrecognized/ambiguous form): emit `permissionDecision: ask` → _raise the command
     and let the user's config / a prompt decide._ If the session is non-interactive,
     `ask` degrades safely to a deny.
4. **Compound commands.** Split on `&&`, `||`, `;`, `|`, `|&`, `&`, and newlines;
   strip leading wrappers (`timeout, time, nice, nohup, stdbuf, xargs, env, command,
\`). Evaluate **every** segment. Result = **deny if any segment denies**, else
   **ask if any segment asks**, else **allow**. (Substitution/redirection checks run on
   the whole string first.)
5. **Emit:** print the `hookSpecificOutput` JSON via `printf` (no `jq` needed to
   emit), `exit 0`.

### 6.2 Why three-way (vs. alternatives considered)

- **Strict baked-in allowlist (original framing):** docs call arg-constraining Bash
  patterns "fragile" and recommend hooks; also contradicts the user's "let my config
  decide" reframe. Rejected as the _primary_ mechanism (its safe core survives as the
  hard-deny floor + explicit allow set).
- **Pure native / ask only, no hard floor:** clean, but a plugin can't guarantee the
  session is in a prompting mode, so "never mutate" wouldn't be guaranteed in e.g.
  `bypassPermissions`. Rejected — violates hard constraint #2.
- **Three-way (chosen):** the user's config governs the grey zone via `ask`, _and_
  destructive ops are impossible in the inspector regardless of session mode. Honors
  both the reframe and the original hard constraint.

### 6.3 Portability / dependencies

- Shebang `#!/usr/bin/env bash`; `chmod +x`. Target **bash 3.2** (macOS default): no
  associative arrays, no `${var,,}`; use `case`/`grep -E`.
- **`jq`** is a soft dependency used only to extract the command _inside the inspector_;
  scope-gating is `jq`-free so the main session never depends on it. Documented in the
  plugin README; missing `jq` → inspector denies with an install hint.
- No writes to `${CLAUDE_PLUGIN_ROOT}` (ephemeral). No logging by default.

## 7. `peek-inspector.md` (subagent)

Frontmatter:

```yaml
name: peek-inspector
description: Read-only repository inspector — git state, folder structure, file
  contents. Returns raw output verbatim, never edits or advises.
model: haiku
tools: Read, Glob, Grep, Bash
disallowedTools: Write, Edit
```

System prompt (body) directs it to:

- Translate the user's English request into the **minimal set of read-only commands**.
- Prefer the **Read** tool for file contents (verbatim, incl. markdown), **Glob** for
  structure, **Grep** for search; use **Bash** for git and `tree`.
- For "folder structure": prefer `git ls-files`-derived view (respects `.gitignore`)
  for tracked files; use `tree`/`find` for a fuller view when asked. **`tree` is often
  absent on macOS → fall back to `find` or `git ls-files`.**
- **Return raw output verbatim** with minimal framing. **Never** edit, never advise,
  never attempt a mutating command. If a request would require mutation, state plainly
  that the inspector is read-only and does not perform it.

`disallowedTools: Write, Edit` is a coarse hard boundary; the guard handles Bash.

## 8. `peek.md` (slash command)

Frontmatter `description`; body instructs the main agent to invoke the
`peek-inspector` subagent (Agent tool, `subagent_type: peek-inspector`) with the
free-form `$ARGUMENTS`, and to relay the subagent's output verbatim. Example mappings
to include as guidance: "what changed" → `git status` + `git diff`; "last 5 commits"
→ `git log -5`; "diff for X" → `git diff -- X`; "folder structure" → tree/`git
ls-files`; "read X" → Read tool.

## 9. Testing & validation

- **Schema:** `claude plugin validate` on the plugin (manifest, agent/command
  frontmatter, `hooks/hooks.json`).
- **Guard unit tests (no subagent needed):** pipe simulated hook JSON into
  `peek-guard.sh` and assert the decision. Matrix:

  | `agent_type`     | command                       | expected                                   |
  | ---------------- | ----------------------------- | ------------------------------------------ | ---------------------- |
  | (absent / main)  | `rm -rf /`                    | exit 0, no output (main session untouched) |
  | `peek-inspector` | `git status`                  | allow                                      |
  | `peek-inspector` | `git log -5`                  | allow                                      |
  | `peek-inspector` | `git diff -- src/a.js`        | allow                                      |
  | `peek-inspector` | `git log                      | head`                                      | allow (both read-only) |
  | `peek-inspector` | `tree -L 2`                   | allow                                      |
  | `peek-inspector` | `cat README.md`               | allow                                      |
  | `peek-inspector` | `git commit -m x`             | deny                                       |
  | `peek-inspector` | `git push`                    | deny                                       |
  | `peek-inspector` | `rm file`                     | deny                                       |
  | `peek-inspector` | `cat f > out`                 | deny (redirection)                         |
  | `peek-inspector` | `ls && rm x`                  | deny (compound)                            |
  | `peek-inspector` | `echo $(rm x)`                | deny (substitution)                        |
  | `peek-inspector` | `find . -name '*.js' -delete` | deny                                       |
  | `peek-inspector` | `find . -name '*.js'`         | allow                                      |
  | `peek-inspector` | `npm test`                    | deny (known mutator family)                |
  | `peek-inspector` | `psql -c '\dt'`               | ask (unknown)                              |
  | `peek-inspector` | `git status` (jq absent)      | deny + "install jq"                        |

- **End-to-end (manual):** install via the local marketplace, run `/peek what
changed`, `/peek folder structure`, `/peek read <path>`; attempt a mutating phrasing
  and confirm refusal; confirm the **main session can still commit/write** (guard
  no-ops outside the inspector).

## 10. Scope / YAGNI

**In:** the seven files in §5 + guard unit tests.
**Out (for now):** `CHANGELOG.md`, configurable allow/deny lists, debug logging,
non-git VCS, Windows-specific handling (target bash/macOS/Linux; note PowerShell is
out of scope).

## 11. Open items to confirm at build time

- Exact top-level `marketplace.json` field set (`name`, `owner`, `plugins[]` with
  `name`/`source: ./plugins/peek`/`description`) — validate with `claude plugin validate`.
- **Verify the deny floor under `bypassPermissions`** (and `acceptEdits`): confirm a
  `permissionDecision: deny` from the guard actually blocks; if not, switch the deny
  path to `exit 2`. This is the one residual safety assumption.
- Confirm `ask` behavior inside the subagent (prompts the user in the main session in
  `default` mode; should degrade to deny when non-interactive).
- Whether to commit on `main` or a feature branch (raise with user before any commit).
