# `peek` on remote sessions (where `!` shell mode isn't available)

## The gap

In a **local** Claude Code terminal you can type `! <cmd>` to drop into shell mode for
a quick look. In **remote** Claude Code sessions — claude.ai/code, or any session
reached over the network rather than from a local terminal — that's disabled.
Attempting it returns, verbatim:

> Shell commands are only available in local sessions.

## Why it stings

That removes the fastest "just let me look at the repo" affordance. On a remote
session the only way to inspect the repo *from inside the session* is to ask the
model, through its tools, to do it for you.

## Why asking the model directly isn't great

Two failure modes:

1. **It can mutate.** A stray `git checkout`, an over-eager "let me just fix that"
   — the model has write access, so "show me X" can turn into "changed X."
2. **It pollutes context.** Whatever the model reads is pulled into your main thread's
   context, nudging the task you were actually on.

## How `peek` closes the gap

`peek` runs inspection in a subagent that is:

- **physically read-only** — the guard hook plus `disallowedTools: Write, Edit` (see
  [security.md](security.md)); and
- **context-isolated** — it runs in its own subagent thread, so the inspection
  commands and reasoning never land in your main session; only the result comes back
  (see [architecture.md](architecture.md)).

Same UX whether you're local or remote: `/peek:peek what changed`.

## Three ways to "look," compared

| Approach | Works on remote? | Can mutate? | Isolated from main context? |
|---|---|---|---|
| `! <cmd>` shell mode | ❌ no (`!` disabled) | n/a | n/a |
| Ask Claude directly | ✅ yes | ⚠️ yes | ❌ no |
| `/peek:peek …` | ✅ yes | ✅ no (enforced) | ✅ yes |

## Caveat: the standalone `/peek`

The lite [standalone `/peek`](../standalone/README.md) runs **inline** (no subagent,
no guard hook). On a remote session it restores read-only *inspection*, but **not**
the context isolation or the enforced guard — read-only there rests on instructions +
`disallowed-tools: Write Edit` + your own permission settings. For the enforced,
isolated guarantee use the plugin (`/peek:peek`). See
[architecture.md](architecture.md#plugin-vs-standalone).

## See also

- [use-cases.md](use-cases.md) — more situations `peek` is good for.
- [architecture.md](architecture.md) · [security.md](security.md)
- [Design spec](superpowers/specs/2026-05-27-peek-plugin-design.md)
