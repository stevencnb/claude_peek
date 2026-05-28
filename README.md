# peek — Claude Code plugin marketplace

This repo hosts the **`peek`** Claude Code plugin: a read-only repository inspector you
call from inside a session with `/peek:peek <plain English>`. It inspects git state, folder
structure, and file contents through a subagent that **can never modify the repo or
filesystem**, and keeps the work out of your main session's context.

See [`plugins/peek/README.md`](plugins/peek/README.md) for full usage and the safety model.

> **Especially useful on remote Claude Code sessions** (e.g. claude.ai/code) where
> `! <cmd>` shell mode is disabled — `peek` is the read-only inspection escape hatch
> that *does* work there. See [docs/remote-sessions.md](docs/remote-sessions.md).

📖 **Docs:** [use-cases](docs/use-cases.md) · [architecture](docs/architecture.md) · [security](docs/security.md) · [remote sessions](docs/remote-sessions.md)

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

For a bare `/peek` without the plugin, see [`standalone/README.md`](standalone/README.md).

## Requirements

`jq` must be installed (`brew install jq` on macOS) — the guard uses it to read the
proposed command. macOS / Linux (bash). See the [plugin README](plugins/peek/README.md)
for details. (The lightweight `standalone/peek.md` has no `jq` dependency.)

## License

MIT — see [LICENSE](LICENSE).
