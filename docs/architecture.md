# How `peek` works

## Why this exists

`peek` is the structural answer to "I want to look at the repo without mutating it
or flooding the main thread's context." It's also the *only* in-session way to do
that on remote Claude Code sessions, which lack `! <cmd>` shell mode. Two properties
make it work: it is **read-only by construction** (a guard hook plus
`disallowedTools: Write, Edit`) and **context-isolated** (it runs in a separate
subagent thread, so the back-and-forth of inspection never lands in your main
session — only the result comes back). Full story:
[remote-sessions.md](remote-sessions.md).

## The linchpin: `agent_type` scoping

`hooks/hooks.json` registers `scripts/peek-guard.sh` as a **session-wide** PreToolUse
hook on `Bash`. But the guard's first action is a `jq`-free check: if the hook
payload's `agent_type` is not `"peek-inspector"`, it `exit 0`s with no output.
`agent_type` is absent on the main thread and other agents, so the guard **no-ops
everywhere except inside the inspector** — your normal editing, committing, and
running are never touched. This single fact connects `hooks.json`, `peek-guard.sh`,
and `agents/peek-inspector.md`.

## The three-way guard

Inside the inspector, each Bash command is classified **deny / allow / ask**, with
precedence **deny beats ask beats allow**:

- **deny** — mutators/escapes, output redirection, command/process substitution, git
  *write* subcommands (and git `--output`/`--output-directory` even on read
  subcommands), `find -delete`/`-exec`. (Full list: [security.md](security.md).)
- **allow** — recognized read-only programs and git *read* subcommands.
- **ask** — anything unrecognized or ambiguous → defers to your own permission
  config / an interactive prompt.

This mirrors Claude Code's native permission model (a PreToolUse hook may deny, force
ask, or allow; a user `deny` rule still wins). The guard **fails closed inside, open
outside**: uncertainty inside the inspector resolves to ask/deny, never a silent
allow.

## The deny floor is `exit 2`

The deny path uses **`exit 2`**, the documented blocking error that blocks the tool
call in *every* permission mode, including `bypassPermissions`. Other non-zero exits
are **non-blocking — they fail open** — so they are never used as a deny path.
`ask`/`allow` stay as exit-0 JSON decisions, so your own config still governs the
grey zone. See [security.md](security.md) and the design spec's §11.

## Compound commands

Commands are split on `;`, `|`, `&`, `&&`, `||`, and newlines; **every** segment is
classified and the results reduce by deny-beats-ask-beats-allow. Substitution and
redirection are checked against the whole string first (so they're caught even inside
quotes). Git subcommands that have both read and write forms — `branch`, `config`,
`remote`, `stash`, `worktree`, `reflog`, `tag`, `notes`, `symbolic-ref` — get
context-sensitive handling in `classify_git_dual`.

## Defense in depth

The inspector subagent also sets `disallowedTools: Write, Edit` — a tool-level hard
boundary for file writes that complements the Bash guard. Plugin subagents cannot set
their own `permissionMode`/`hooks`/`mcpServers` (ignored for security), so a
session-wide hook keyed on `agent_type` is the only viable per-subagent enforcement
point.

## Plugin vs standalone

Two delivery forms of the same idea:

- **Plugin** (`/peek:peek`) — isolated subagent **and** the enforced guard hook. The
  full read-only guarantee plus context isolation.
- **Standalone** (`/peek`) — runs **inline** in your main session; read-only rests on
  instructions + `disallowed-tools: Write Edit` + your own permission settings. No
  subagent, no guard hook.

The feature-by-feature comparison table lives in
[`standalone/README.md`](../standalone/README.md) — the canonical home for it.

## Data flow

```
/peek:peek <english>
      │
      ▼
main agent ──(Agent tool, subagent_type: peek-inspector)──▶ peek-inspector subagent
                                                                  │
                                              chooses minimal read-only commands
                                                                  │
                                                  Bash call ──▶ peek-guard.sh
                                                                  │ (acts only because
                                                                  │  agent_type == peek-inspector)
                                                        deny(exit 2) / ask(JSON) / allow(JSON)
                                                                  │
                                                          allowed output
                                                                  │
                                                                  ▼
                                              subagent returns raw output verbatim
                                                                  │
                                                                  ▼
                                                  main agent relays it to you
```

## See also

- [design-principles.md](design-principles.md) — the four design questions behind these mechanisms.
- [security.md](security.md) — the threat model and the full deny list.
- [remote-sessions.md](remote-sessions.md) — why `peek` exists for remote sessions.
- [Design spec](superpowers/specs/2026-05-27-peek-plugin-design.md) — decision record.
