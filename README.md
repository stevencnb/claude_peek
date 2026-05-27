# peek — Claude Code plugin marketplace

This repo hosts the **`peek`** Claude Code plugin: a read-only repository inspector you
call from inside a session with `/peek:peek <plain English>`. It inspects git state, folder
structure, and file contents through a subagent that **can never modify the repo or
filesystem**, and keeps the work out of your main session's context.

See [`plugins/peek/README.md`](plugins/peek/README.md) for full usage and the safety model.

## Install

Add this repo as a plugin marketplace, then install `peek`:

```
/plugin marketplace add <this-repo-url-or-local-path>
/plugin install peek@peek-marketplace
```

From a local clone, for example:

```
/plugin marketplace add /path/to/claude_peek
/plugin install peek@peek-marketplace
```

Then try it. Plugin skills are always namespaced as `plugin:command`, so the command is
`peek:peek`:

```
/peek:peek what changed
/peek:peek last 5 commits
/peek:peek folder structure
/peek:peek read README.md
```

## Lightweight local alternative (`/peek`)

Plugin skills are always namespaced, so the plugin is `/peek:peek`. If you'd rather type a
bare **`/peek`** on a single machine and don't need the enforced guard, copy the standalone
command into your user commands directory:

```
mkdir -p ~/.claude/commands && cp standalone/peek.md ~/.claude/commands/peek.md
```

Then `/peek what changed` works directly. This lite version runs **inline in your main
session** (no isolated subagent) and has **no enforcing guard hook** — read-only is by
instruction plus your own Claude Code permission settings. For the enforced, isolated
read-only guarantee, use the plugin. See [`standalone/README.md`](standalone/README.md).

## Requirements

`jq` must be installed (`brew install jq` on macOS) — the guard uses it to read the
proposed command. macOS / Linux (bash). See the [plugin README](plugins/peek/README.md)
for details. (The lightweight `standalone/peek.md` has no `jq` dependency.)

## Layout

```
.claude-plugin/marketplace.json   # marketplace entry
plugins/peek/                     # the plugin (enforced, isolated /peek:peek)
  .claude-plugin/plugin.json
  agents/peek-inspector.md
  commands/peek.md
  hooks/hooks.json
  scripts/peek-guard.sh
standalone/peek.md                # lightweight local /peek (copy to ~/.claude/commands/)
docs/superpowers/specs/           # design spec
```

## License

MIT — see [LICENSE](LICENSE).
