# Security & threat model

## Threat model

**Actor:** a *model* that has been instructed — or coerced via prompt injection —
to attempt mutation while running inside the `peek-inspector` subagent.

**Not in scope:** a malicious *user* (they don't need the inspector to run `rm`); and
platform/OS-level threats (kernel bugs, shell injection into bash itself, a
compromised Claude Code binary).

**Contrast with `!` shell mode:** `! <cmd>` runs your raw shell *as you*, with no
classifier and no isolation — and that's fine, because *you* typed it. `peek` accepts
the command from a model, so it adds the enforcement layer below. (Why this matters
most on remote sessions: [remote-sessions.md](remote-sessions.md).)

## What `peek` defends against

Inside the inspector, the guard denies (hard, via [exit 2](#why-exit-2)):

- **Mutating commands** — e.g. `rm`, `mv`, `cp`, `mkdir`, `touch`, `chmod`, `dd`,
  `tee`, `git commit`.
- **Output redirection** — `>`, `>>`, `2>`, `&>` (checked on the whole string, so
  caught even inside quotes).
- **Command/process substitution** — `` `…` ``, `$(…)`, `<(…)`, `>(…)`.
- **Interpreter escapes** — `bash -c …`, `sh -c …`, `python -c …`, `awk`, `perl`,
  `node`, `eval`, `source`.
- **Git write subcommands** — `add`, `commit`, `push`, `checkout`, `reset`,
  `restore`, `merge`, `rebase`, `stash push`, … — **including** `--output` /
  `--output-directory`, which are file writes available even on read subcommands like
  `diff`/`show`/`log`.
- **`find` that acts** — `-delete`, `-exec`, `-execdir`, `-fprintf`, `-fls`, `-ok`.
- **Dangerous environment overrides** — `env -…`, and `GIT_DIR=`/`GIT_WORK_TREE=`
  style prefixes that would retarget git.

## What `peek` does *not* defend against

- **Main-session Bash calls** — out of scope by design. The guard no-ops when
  `agent_type != peek-inspector` ([agent_type scoping](architecture.md#the-linchpin-agent_type-scoping)).
- **`ask`-classified commands your own config then allows** — the grey zone is
  intentionally yours to govern.
- **Reading sensitive files** — `peek` can read anything *you* can read. That's the
  point; it's an inspector. Don't point it at secrets you don't want surfaced into
  the session.
- **TOCTOU between classification and execution** — acceptable for read-only
  commands; the worst case is reading a slightly different file than intended.

## Why `exit 2`

`peek`'s deny path uses **`exit 2`**, the only exit status documented to block a tool
call in **every** permission mode, including `bypassPermissions`. Every *other*
non-zero exit is non-blocking — it **fails open** (the call proceeds) — so the guard
never uses any other non-zero status as a deny. `ask` and `allow` are emitted as
exit-0 JSON decisions instead, so your own permission rules still compose on top
(`deny` rules always win). This is the single most important security invariant.
History: the canonical [design spec](superpowers/specs/2026-05-27-peek-plugin-design.md)
§11 records why this replaced an earlier `permissionDecision: deny`.

## Failure modes

- **`jq` missing** → the guard *fails closed inside the inspector*: it denies with an
  "install jq" hint. The main session is unaffected, because the `agent_type` scope
  gate runs first and is `jq`-free.
- **Guard script error/crash** → *outside* the inspector it has already `exit 0`'d
  (the scope gate is the first action), so the main session is untouched. *Inside*,
  the inspector can't run the command because Bash hands control to the guard before
  execution. This is what "**fail closed inside, open outside**" means.

## What an attacker would have to do

To actually mutate the repo through `peek`, an attacker would need one of:

1. **Bypass `agent_type` scoping** — requires a Claude Code platform bug. Report to
   Anthropic.
2. **Find a classification gap** — a mutating command the three-way guard misreads as
   read-only. Please report it via the repo's issues.
3. **Trick the user** into approving an `ask`-classified command in their own session.

## See also

- [architecture.md](architecture.md) — how the guard is built.
- [design-principles.md](design-principles.md) — the design philosophy in four questions.
- [Design spec](superpowers/specs/2026-05-27-peek-plugin-design.md) — decision record.
