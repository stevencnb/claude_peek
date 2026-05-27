# Lightweight local `peek` (`/peek`)

A single-file, dependency-free version of the [`peek`](../plugins/peek/README.md) plugin —
for when you just want a bare **`/peek`** on one machine and don't need the full plugin.

## Install

```
mkdir -p ~/.claude/commands && cp standalone/peek.md ~/.claude/commands/peek.md
```

(Or copy it into a project's `.claude/commands/peek.md` to scope it to that repo.) Then run
`/peek what changed` — no `/plugin install`, no marketplace, no `jq`.

## How it differs from the plugin

| | Plugin (`/peek:peek`) | Standalone (`/peek`) |
|---|---|---|
| Invocation | `/peek:peek …` (plugin skills are always namespaced) | bare `/peek …` |
| Where it runs | isolated `peek-inspector` subagent | **inline, in your main session** |
| Main-thread context | inspection output stays out of it | output lands in your main context |
| Read-only enforcement | **guard hook** classifies every Bash command (allow / ask / deny) | by instruction + `disallowed-tools: Write Edit` + **your own permission settings** |
| Install | `/plugin install peek@peek-marketplace` | copy one file |

Use the **plugin** when you want the hard, enforced read-only guarantee and context
isolation. Use the **standalone** when you want the simplest possible bare `/peek` and are
fine relying on your own Claude Code permission configuration for the read-only boundary.
