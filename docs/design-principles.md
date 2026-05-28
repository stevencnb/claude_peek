# Design principles

Four questions shaped every structural choice in `peek`. The other docs explain the
*mechanisms* — [architecture.md](architecture.md) (how it's built),
[security.md](security.md) (threat model), [remote-sessions.md](remote-sessions.md) (why
it exists). This page is the layer above them: the *why*, stated as the questions the
design answers. Each is already settled in the code — the pointers say where.

The short version is one stance applied four ways: **inspection should be transient and
isolated; its one safety-critical promise must be mechanically enforced against an
untrusted model; the plugin decides only the absolutes and defers the ambiguous middle to
you; and any missing piece should fail safe in a contained blast radius.**

## Where should temporary inspection work live?

**In a throwaway context that touches neither your main thread nor the disk.** Inspection
runs in the isolated `peek-inspector` subagent, so its commands and reasoning never land
in your main session — only the result comes back. And it never persists: output
redirection is denied (no scratch files), and the guard writes no logs or state to the
ephemeral `${CLAUDE_PLUGIN_ROOT}` (it's cleaned ~7 days after an update). The only durable
artifact is the text handed back to you; anything that would outlive the request is
disallowed by design.

→ [Context isolation](remote-sessions.md#how-peek-closes-the-gap) · no-writes & the
ephemeral plugin root: [design spec](superpowers/specs/2026-05-27-peek-plugin-design.md)
§6.3.

## Which promises need enforcement instead of instructions?

**Only the safety-critical one: "never mutate the repo or filesystem."** The untrusted
party is the *model itself* — possibly coerced via prompt injection — so a promise it
could simply ignore cannot rest on prose. That one promise is backed by mechanism: the
`exit 2` hard-deny floor plus `disallowedTools: Write, Edit`. Everything else — return
output verbatim, never editorialize, run the fewest commands — stays as prompt
instruction, because breaking it yields a worse answer, not a breached repo. The tell: the
standalone `/peek` keeps read-only as instruction only, and the single promise that gets
*promoted* to enforcement in the plugin is exactly the mutation boundary.

→ [Defense in depth](architecture.md#defense-in-depth) ·
[why `exit 2`](security.md#why-exit-2) ·
[plugin vs standalone](architecture.md#plugin-vs-standalone)

## Which decisions belong to the plugin, and which belong to the user's environment?

**The plugin owns the absolutes; your environment owns the grey zone.** What counts as a
mutation versus plainly read-only is near-universal, so the guard decides it
unconditionally — destructive commands always denied, recognized read-only ones always
allowed. Anything ambiguous is emitted as `ask` and deferred to your own permission config;
the grey zone is intentionally yours to govern. The guard *composes with* your rules rather
than overriding them (a user `deny` still wins), and via the `agent_type` gate it claims
authority over **nothing** outside the inspector.

→ [The three-way guard](architecture.md#the-three-way-guard) ·
[`agent_type` scoping](architecture.md#the-linchpin-agent_type-scoping) ·
[what `peek` does *not* defend against](security.md#what-peek-does-not-defend-against)

## How should a plugin fail when one piece is missing?

**Fail closed where the guarantee matters; stay open — untouched — everywhere it doesn't.**
The blast radius of a missing piece is contained to the component that needs it. The
dependency-free scope gate runs *first*, so a missing `jq` or a guard crash can never reach
your main session; inside the inspector those same conditions deny. When uncertain, the
guard resolves toward the safe side — `ask` or `deny`, never a silent allow — and even the
deny *mechanism* is `exit 2` precisely because every other non-zero exit fails open.

→ [Fail closed inside, open outside](security.md#failure-modes) ·
[why `exit 2`](security.md#why-exit-2)

## See also

- [architecture.md](architecture.md) — the mechanisms these principles produce.
- [security.md](security.md) — the threat model and the full deny list.
- [Design spec](superpowers/specs/2026-05-27-peek-plugin-design.md) — the dated decision
  record (this page is the distilled, living philosophy).
