# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-plugin Claude Code **marketplace** repo. It ships **`peek`**, a read-only repository inspector: `/peek:peek <plain English>` inspects git state, folder structure, and file contents through an isolated subagent that is prevented — by a guard hook, not by trust — from mutating the repo or filesystem. There is nothing to "build"; the substance is one shell guard plus Markdown agent/command/hook definitions.

## Commands

```bash
# Guard unit tests — the main test suite. Requires bash + jq; exits non-zero on failure.
bash plugins/peek/tests/test-peek-guard.sh

# Run a single guard check (no per-case flag exists — pipe a simulated PreToolUse payload):
echo '{"tool_input":{"command":"git status"},"agent_type":"peek-inspector"}' | bash plugins/peek/scripts/peek-guard.sh
#   omit "agent_type" to confirm the main-session no-op → prints nothing, exits 0

# Validate plugin schema (manifest, agent/command frontmatter, hooks.json):
claude plugin validate plugins/peek
```

Dev / manual end-to-end:

```bash
claude --plugin-dir ./plugins/peek      # fastest loop: load the plugin without installing
```
```
/plugin marketplace add /Users/steven/projects/claude_peek   # or install via the marketplace
/plugin install peek@peek-marketplace
/reload-plugins
```

**Reload gotcha (observed):** after a fresh `/plugin install`, `/reload-plugins` makes the command/skill available, but the **agent does not register as a subagent type until a full Claude Code restart** (after which it appears namespaced as `peek:peek-inspector`).

## Architecture

Everything serves one goal: inspection that **cannot** mutate, while leaving the user's main session entirely unaffected.

**The linchpin — `agent_type` scoping.** `hooks/hooks.json` registers `scripts/peek-guard.sh` as a *session-wide* PreToolUse hook on `Bash`. But the guard's **first action** is a jq-free check: if the hook payload's `agent_type` is not `"peek-inspector"` (the subagent's frontmatter `name`), it `exit 0`s with no output. `agent_type` is absent on the main thread and other agents, so the guard **no-ops everywhere except inside the inspector** — normal editing/committing/running is never touched. This single fact connects `hooks.json` ↔ `peek-guard.sh` ↔ `agents/peek-inspector.md`; understand it before touching any of them.

**Three-way guard, fails closed (only inside the inspector).** Each Bash command is classified:
- **deny** — output redirection / command & process substitution (checked on the whole string, even inside quotes); known mutators/interpreters/privilege programs (the `MUT_PROGS`/`PRIV_PROGS` tables); git *write* subcommands and git `--output`/`--output-directory` (a file write available even on read subcommands like `diff`/`show`/`log`); `find` with `-delete`/`-exec`.
- **allow** — recognized read-only programs (`RO_PROGS`) and git *read* subcommands.
- **ask** — anything unrecognized or ambiguous → defers to the user's own permission config / an interactive prompt.

Compound commands are split on `; | &` and newlines and **every** segment is classified; **deny beats ask beats allow**. git subcommands that have both read and write forms (`branch`, `config`, `remote`, `stash`, `worktree`, `reflog`, `tag`, `notes`, `symbolic-ref`) get context-sensitive logic in `classify_git_dual`.

**Defense in depth.** The subagent additionally sets `disallowedTools: Write, Edit` — a tool-level hard boundary for file writes, complementing the guard which covers Bash. Per the design, plugin subagents *cannot* set their own `permissionMode`/`hooks`/`mcpServers` (ignored for security), so the hook keyed on `agent_type` is the *only* viable per-subagent enforcement point — don't try to lock the agent down via its own mode.

**Data flow.** `/peek:peek <english>` (`commands/peek.md`) → main agent invokes the `peek-inspector` subagent with `$ARGUMENTS` → subagent runs the minimal read-only commands → each Bash call passes the guard → raw output returns and is relayed verbatim.

**Two delivery forms of the same idea:**
- **Plugin** (`plugins/peek/`, invoked `/peek:peek`): the full version — isolated subagent + enforced guard. It's namespaced because plugin skills are *always* `plugin:command`; bare `/peek` is not possible for a plugin.
- **Standalone** (`standalone/peek.md`, copied to `~/.claude/commands/peek.md`, invoked `/peek`): a lite version that runs **inline** (no subagent, no guard hook). Read-only rests on its instructions + `disallowed-tools: Write Edit` + the user's permission settings. Keep its read-only command guidance in sync with the subagent's.

## Invariants when editing the guard (`scripts/peek-guard.sh`)

- **Target bash 3.2** (macOS default): no associative arrays, no `${var,,}`; use `case` / `grep -E`.
- **Fail closed inside, open outside.** The `agent_type` scope gate must stay first and jq-free, so a guard error or a missing `jq` can never affect the main session. Inside the inspector, uncertainty resolves to `ask`/`deny`, never a silent allow.
- **The deny floor uses `exit 2`.** Exit 2 is the documented hard block — it blocks the tool call in *every* permission mode, including `bypassPermissions` (this resolves spec §11). `ask`/`allow` stay as exit-0 JSON decisions, so the user's own config still governs the grey zone. Never use any *other* non-zero exit as a deny path — only `2` blocks; the rest fail *open*.
- **Never write to `${CLAUDE_PLUGIN_ROOT}`** — it is ephemeral (cleaned ~7 days). No logs or state there.
- **Keep `tests/test-peek-guard.sh` in sync** — every classification change needs a case; run the suite after editing.

## Deeper context

`docs/superpowers/specs/2026-05-27-peek-plugin-design.md` is the canonical design doc: the verified Claude Code platform facts (hook `agent_type`, the decision JSON, deny→ask→allow precedence) and the rationale for the three-way model. Read it before changing the safety model.
