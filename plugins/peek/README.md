# peek

A **read-only repository inspector** for Claude Code. Run `/peek:peek <plain English>` and a
dedicated subagent (`peek-inspector`, model: `haiku`) inspects git state, folder
structure, and file contents — **without modifying anything** and **without polluting
your main session's context**.

> Plugin skills are always namespaced as `plugin:command`, so this command is `/peek:peek`.
> Want a bare `/peek` for quick local use? See the lightweight
> [`standalone/peek.md`](../../standalone/README.md) in the repo root.

## Why

Deep in a coding session you often want to glance at repo state — what changed, the last
few commits, a diff, the folder layout, a file's contents — without derailing the main
thread or risking an accidental write. `peek` runs that inspection in an isolated
subagent and returns the raw output.

## Usage

```
/peek:peek what changed
/peek:peek last 5 commits
/peek:peek diff for src/app.ts
/peek:peek staged diff
/peek:peek folder structure
/peek:peek read src/config.ts
/peek:peek show HEAD~2
```

The inspector returns command output verbatim. It never edits, advises, or mutates.

## Safety model (read-only is enforced, not trusted)

`peek` ships a `PreToolUse` hook (`scripts/peek-guard.sh`) that runs on every Bash call
but **acts only inside the `peek-inspector` subagent** — it keys on the hook's
`agent_type` field. In your main session (and any other agent) it no-ops, so your normal
ability to edit, commit, and run commands is **never affected**.

Inside the inspector, each Bash command is classified three ways:

- **deny** — destructive / mutating / escape commands: `rm`, `mv`, `git commit`/`push`/
  `checkout`/`reset`/…, output redirection (`>`/`>>`, `git --output`), command substitution (`` ` `` /
  `$(...)`), interpreters (`python -c`, `bash -c`, `awk`, …), `sudo`, etc. Blocked.
- **allow** — recognized read-only inspection commands: `git status`/`log`/`diff`/`show`,
  read-only `git branch`/`remote -v`/`config --get`, `ls`/`tree`/`cat`/`head`/`tail`/
  `wc`/`stat`, `find` (without `-delete`/`-exec`), `grep`, etc. Run with no prompt.
- **ask** — anything else (unrecognized program, or an ambiguous form). The command is
  surfaced for a permission decision, so **your** Claude Code config (allow/ask/deny
  rules) or an interactive prompt decides. Deny rules always win.

The subagent additionally has `Write`/`Edit` disabled at the tool level as a coarse hard
boundary. The guard fails **closed** inside the inspector: anything it can't confidently
classify as read-only is denied or escalated, never silently allowed.

## Requirements

- **`jq`** — used by the guard to read the proposed command. macOS: `brew install jq`.
  If `jq` is missing, the inspector denies commands with an install hint; your main
  session is unaffected (the scope check is `jq`-free).
- macOS / Linux (bash 3.2+). `tree` is optional — the inspector falls back to
  `git ls-files` / `find` when it isn't installed.

## What's inside

| Path | Role |
|---|---|
| `agents/peek-inspector.md` | The read-only inspector subagent. |
| `commands/peek.md` | The `/peek:peek` slash command. |
| `hooks/hooks.json` | Registers the `PreToolUse` Bash guard. |
| `scripts/peek-guard.sh` | The three-way read-only guard. |

For a bare `/peek` without the plugin (inline, no guard), see
[`standalone/peek.md`](../../standalone/README.md).
