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

If you're on a remote session where `! <cmd>` shell mode is disabled, this is the
in-session replacement — see [docs/remote-sessions.md](../../docs/remote-sessions.md).

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

A `PreToolUse` Bash hook (`scripts/peek-guard.sh`) acts **only inside the
`peek-inspector` subagent** (it keys on `agent_type`) and **no-ops in your main
session**. Inside the inspector it classifies every command **deny / allow / ask**
(deny beats ask beats allow) and hard-blocks the deny floor with `exit 2`. The
subagent also has `Write`/`Edit` disabled as a coarse tool-level boundary.

→ **Full threat model: [docs/security.md](../../docs/security.md). How it works:
[docs/architecture.md](../../docs/architecture.md).**

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
