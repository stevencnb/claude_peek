# `peek` documentation

`peek` is a **read-only repository inspector** for Claude Code: run
`/peek:peek <plain English>` and an isolated subagent inspects git state, folder
structure, and file contents — **without modifying anything** and **without polluting
your main session's context**.

> On a remote Claude Code session where `! <cmd>` shell mode is disabled, `peek` is
> the in-session, read-only equivalent. See [remote-sessions.md](remote-sessions.md).

## Pick a door

- **Want to use it?** → [use-cases.md](use-cases.md)
- **Want to understand it?** → [architecture.md](architecture.md)
- **Evaluating whether to install?** → [security.md](security.md)
- **On a remote/web session without `!`?** → [remote-sessions.md](remote-sessions.md)

## Install & quick start

See the [repo README](../README.md). For the lightweight bare `/peek`, see
[`standalone/README.md`](../standalone/README.md).

## Decision record

The canonical design spec —
[superpowers/specs/2026-05-27-peek-plugin-design.md](superpowers/specs/2026-05-27-peek-plugin-design.md)
— records the verified platform facts and the rationale (why three-way, why
[exit 2](security.md#why-exit-2)).
