# Additional project docs for `peek` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four focused docs under `docs/` (use-cases, architecture, security, remote-sessions) plus a `docs/README.md` index, and trim the three existing READMEs to summarize-and-link, so `peek` is introduced from multiple angles without duplicated prose.

**Architecture:** Pure documentation change. The new `docs/` pages become the canonical home for depth; the READMEs shrink to a pitch + pointers. No source file under `plugins/peek/` (agent, command, hook, guard, tests) or `standalone/peek.md` is touched, so behavior is unchanged and the guard test suite must still pass verbatim. One topic — the "no `!` shell mode on remote sessions" story — gets a dedicated canonical page (`docs/remote-sessions.md`); every other surface paraphrases and links to it, and the verbatim error string is quoted in exactly one place.

**Tech Stack:** Markdown only. Validation via `bash` (link audit, terminology lint) and the existing guard test (`bash plugins/peek/tests/test-peek-guard.sh`).

**Source spec:** `docs/superpowers/specs/2026-05-27-additional-project-docs-design.md` (read it before starting; section references like "§4.3" below point into it).

---

## Commit & branch policy (read first)

The user deferred the commit decision ("don't commit yet; decide later") and the
branch choice (main vs feature) is open per spec §10. **Before the first commit,
confirm with the user: (a) go-ahead to commit, and (b) commit on `main` or create a
branch (e.g. `docs/introduce-peek`).** The commit steps below are written assuming
approval; if the user prefers a branch, create it first with
`git switch -c docs/introduce-peek` and run all commits there. End every commit
message body with the `Co-Authored-By` trailer the repo uses.

## File structure

| File | Create / Modify | Responsibility |
|---|---|---|
| `docs/architecture.md` | Create | How `peek` works: `agent_type` linchpin, three-way guard, exit-2 floor, compound handling, defense in depth, plugin-vs-standalone rationale, data-flow diagram. Defines the `#plugin-vs-standalone` anchor others link to. |
| `docs/security.md` | Create | Threat model: actor, defends-against / does-not, why exit 2, failure modes, attacker walkthrough. |
| `docs/remote-sessions.md` | Create | **Canonical home** for the no-`!` story. Owns the verbatim error string. |
| `docs/use-cases.md` | Create | Cookbook of 7–9 named scenarios; scenario #1 summarizes the remote-session case and links out. |
| `docs/README.md` | Create | Index: one-paragraph pitch + "pick a door" links + spec pointer. |
| `README.md` (root) | Modify | Trim ~74→~30 lines: pitch + install + `jq` + license + links. |
| `plugins/peek/README.md` | Modify | Trim ~75→~30 lines: replace the long safety section with a 2-sentence summary + links. |
| `standalone/README.md` | Modify | Minor: add two links into `docs/`. |

**Task order rationale:** create `architecture.md` first because other pages link to its `#plugin-vs-standalone` anchor; then `security.md`; then `remote-sessions.md` (links to both); then `use-cases.md` (links to all); then the index (links to the four); then the README trims (link into `docs/`); finally a cross-cutting audit so every link is checked once all targets exist.

**Locked terminology (use verbatim across all docs, per spec §6):** *linchpin*, *three-way guard*, *deny floor*, *`agent_type` scoping*, *exit 2*, *fail closed inside, open outside*. Internal links use **relative paths**, never absolute URLs.

---

### Task 1: `docs/architecture.md`

**Files:**
- Create: `docs/architecture.md`

Implements spec §4.3. Sections in order: (0) Why this exists, (1) The linchpin — `agent_type` scoping, (2) Three-way classifier, (3) The deny floor is `exit 2`, (4) Compound-command handling, (5) Defense in depth, (6) Plugin vs standalone, (7) Data flow, (8) See also.

- [ ] **Step 1: Write the file**

Write `docs/architecture.md` with this exact skeleton, filling each section with prose that states the facts below. Keep total length ~250–350 lines.

````markdown
# How `peek` works

## Why this exists

`peek` is the structural answer to "I want to look at the repo without mutating it
or flooding the main thread's context." It's also the *only* in-session way to do
that on remote Claude Code sessions, which lack `! <cmd>` shell mode. Two properties
make it work: it is **read-only by construction** (a guard hook plus
`disallowedTools: Write, Edit`) and **context-isolated** (it runs in a subagent;
only a summary returns to your main thread). Full story:
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

- [security.md](security.md) — the threat model and the full deny list.
- [remote-sessions.md](remote-sessions.md) — why `peek` exists for remote sessions.
- [Design spec](superpowers/specs/2026-05-27-peek-plugin-design.md) — decision record.
````

- [ ] **Step 2: Verify the `#plugin-vs-standalone` anchor exists and links resolve**

Run:
```bash
grep -n '^## Plugin vs standalone' docs/architecture.md && \
for l in security.md remote-sessions.md superpowers/specs/2026-05-27-peek-plugin-design.md ../standalone/README.md; do
  [ -e "docs/$l" ] || [ -e "$(cd docs && readlink -f "$l" 2>/dev/null)" ] || { echo "BROKEN docs/architecture.md -> $l"; }
done; echo "audit done"
```
Expected: prints the matching `## Plugin vs standalone` line, then `audit done` with no `BROKEN` lines. (`../standalone/README.md` resolves to repo-root `standalone/README.md`.)

- [ ] **Step 3: Commit** (see Commit & branch policy)

```bash
git add docs/architecture.md
git commit -m "$(cat <<'EOF'
docs: add architecture deep-dive

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `docs/security.md`

**Files:**
- Create: `docs/security.md`

Implements spec §4.4. Sections: (1) Threat model preamble, (2) What peek defends against, (3) What peek does not defend against, (4) Why `exit 2`, (5) Failure modes, (6) What an attacker would have to do, (7) See also.

- [ ] **Step 1: Write the file**

Write `docs/security.md` (~200–300 lines) with this exact skeleton and facts:

````markdown
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
- [Design spec](superpowers/specs/2026-05-27-peek-plugin-design.md) — decision record.
````

- [ ] **Step 2: Verify links resolve**

Run:
```bash
for l in remote-sessions.md architecture.md superpowers/specs/2026-05-27-peek-plugin-design.md; do
  [ -e "docs/$l" ] || echo "BROKEN docs/security.md -> $l"; done; echo "audit done"
```
Expected: `audit done`, no `BROKEN` lines.

- [ ] **Step 3: Commit**

```bash
git add docs/security.md
git commit -m "$(cat <<'EOF'
docs: add security & threat model

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `docs/remote-sessions.md` (canonical home for the no-`!` story)

**Files:**
- Create: `docs/remote-sessions.md`

Implements spec §4.5. This is the **only** place the verbatim error string appears.

- [ ] **Step 1: Write the file**

Write `docs/remote-sessions.md` (~80–120 lines) with this exact skeleton:

````markdown
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
- **context-isolated** — it runs in its own thread and only a summary returns, so your
  main thread stays clean (see [architecture.md](architecture.md)).

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
````

- [ ] **Step 2: Verify the verbatim string appears here and links resolve**

Run:
```bash
grep -q 'Shell commands are only available in local sessions' docs/remote-sessions.md && echo "string ok" || echo "MISSING verbatim string"
for l in security.md architecture.md use-cases.md superpowers/specs/2026-05-27-peek-plugin-design.md ../standalone/README.md; do
  [ -e "docs/$l" ] || [ -e "$(cd docs && readlink -f "$l" 2>/dev/null)" ] || echo "BROKEN docs/remote-sessions.md -> $l"; done; echo "audit done"
```
Expected: `string ok`, then `audit done`, no `BROKEN` / `MISSING` lines. (`use-cases.md` is created in Task 4 — if running before then, the one `BROKEN` line for it is expected and resolved by Task 4.)

- [ ] **Step 3: Commit**

```bash
git add docs/remote-sessions.md
git commit -m "$(cat <<'EOF'
docs: add remote-sessions guide (the no-`!` story)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `docs/use-cases.md`

**Files:**
- Create: `docs/use-cases.md`

Implements spec §4.2. Cookbook: each entry = 2–4-sentence situation → one
`/peek:peek …` command → one sentence on what comes back. Scenario #1 is a ~2-sentence
summary that links to `remote-sessions.md` (do **not** duplicate that doc here).

- [ ] **Step 1: Write the file**

Write `docs/use-cases.md` with these scenarios in this order:

````markdown
# What `peek` is good for

Each recipe: the situation, the command, and what comes back. (Commands shown as the
plugin `/peek:peek …`; the standalone is `/peek …`.)

## Remote session where `!` shell mode isn't available

In remote Claude Code sessions, `! <cmd>` is disabled, so there's no shell escape for
a quick look. `/peek:peek what changed` is the in-session, read-only equivalent — same
on remote as local. Full story: [remote-sessions.md](remote-sessions.md).

## Glance at git state mid-task

You're deep in a change and want to know what's modified without the main session
ingesting the whole diff and riffing on it.

```
/peek:peek what changed
```

Returns `git status` + `git diff` verbatim; the bytes stay in the inspector.

## Read a Markdown or config file verbatim

You want to see a file exactly as written — not summarized, not rendered.

```
/peek:peek read CONTRIBUTING.md
```

Returns the file's raw text. (Useful precisely because the main session tends to
summarize or render Markdown instead of showing it.)

## Pre-commit "what am I about to ship"

Before you commit, confirm the staged set is exactly what you intend.

```
/peek:peek staged diff
```

Returns `git diff --staged` verbatim.

## Cold-start orientation in a new repo

You just opened an unfamiliar repo and want the lay of the land.

```
/peek:peek folder structure
/peek:peek last 10 commits
```

Returns a tracked-file tree and the recent history.

## Diff archaeology

You want to see a specific past change or a single file's diff.

```
/peek:peek show HEAD~2
/peek:peek diff for src/foo.ts
```

Returns `git show HEAD~2` / `git diff -- src/foo.ts` verbatim.

## "Show me, don't tell me"

The main session keeps editorializing when you just want the raw output.

```
/peek:peek what changed
```

The inspector never advises — it returns command output and stops.

## Untrusted-task safety check

You're running an agent or task you don't fully trust and want read-only ground truth
without that agent's framing.

```
/peek:peek what changed
```

Read-only by construction, so looking can't become changing.

## Choosing between the plugin and the standalone

Want the enforced, isolated guarantee, or the simplest bare `/peek`? See the
comparison in [`standalone/README.md`](../standalone/README.md) and the rationale in
[architecture.md](architecture.md#plugin-vs-standalone).

## See also

- [remote-sessions.md](remote-sessions.md) · [architecture.md](architecture.md) · [security.md](security.md)
````

- [ ] **Step 2: Verify links resolve and no prose was duplicated from remote-sessions.md**

Run:
```bash
for l in remote-sessions.md architecture.md security.md ../standalone/README.md; do
  [ -e "docs/$l" ] || [ -e "$(cd docs && readlink -f "$l" 2>/dev/null)" ] || echo "BROKEN docs/use-cases.md -> $l"; done
grep -c 'Shell commands are only available in local sessions' docs/use-cases.md | grep -qx 0 && echo "no-dup ok" || echo "DUP: verbatim string must live only in remote-sessions.md"
echo "audit done"
```
Expected: `no-dup ok`, `audit done`, no `BROKEN` lines.

- [ ] **Step 3: Commit**

```bash
git add docs/use-cases.md
git commit -m "$(cat <<'EOF'
docs: add use-cases cookbook

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `docs/README.md` (index)

**Files:**
- Create: `docs/README.md`

Implements spec §4.1.

- [ ] **Step 1: Write the file**

Write `docs/README.md` (~40–60 lines):

````markdown
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
````

- [ ] **Step 2: Verify all four doc links + the two README links resolve**

Run:
```bash
for l in use-cases.md architecture.md security.md remote-sessions.md superpowers/specs/2026-05-27-peek-plugin-design.md ../README.md ../standalone/README.md; do
  [ -e "docs/$l" ] || [ -e "$(cd docs && readlink -f "$l" 2>/dev/null)" ] || echo "BROKEN docs/README.md -> $l"; done; echo "audit done"
```
Expected: `audit done`, no `BROKEN` lines.

- [ ] **Step 3: Commit**

```bash
git add docs/README.md
git commit -m "$(cat <<'EOF'
docs: add docs/ index

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Trim the three READMEs

**Files:**
- Modify: `README.md` (root)
- Modify: `plugins/peek/README.md`
- Modify: `standalone/README.md`

Implements spec §5. Goal: READMEs summarize and link; the deep prose now lives in
`docs/`. Do **not** duplicate `docs/` paragraphs.

- [ ] **Step 1: Trim root `README.md`**

Edit `README.md`:
- **Keep:** the title + 1-paragraph pitch, the `## Install` block (marketplace add +
  install + local-clone example + the namespaced `/peek:peek …` examples), the
  `## Requirements` (`jq`) line, the `## License` line.
- **Remove:** the `## Lightweight local alternative (/peek)` *explanatory* section
  (the cp one-liner can stay as a single line under Install; the explanation now lives
  in `standalone/README.md`), and the `## Layout` tree (now covered by
  `docs/architecture.md`).
- **Add**, immediately under the opening pitch paragraph, these two lines:

```markdown
> **Especially useful on remote Claude Code sessions** (e.g. claude.ai/code) where
> `! <cmd>` shell mode is disabled — `peek` is the read-only inspection escape hatch
> that *does* work there. See [docs/remote-sessions.md](docs/remote-sessions.md).

📖 **Docs:** [use-cases](docs/use-cases.md) · [architecture](docs/architecture.md) · [security](docs/security.md) · [remote sessions](docs/remote-sessions.md)
```

- [ ] **Step 2: Trim `plugins/peek/README.md`**

Edit `plugins/peek/README.md`:
- **Keep:** the title + intro, the namespacing blockquote, `## Why`, `## Usage` (the 7
  example invocations), `## Requirements`, `## What's inside` table, and the closing
  standalone pointer.
- **Replace** the entire `## Safety model (read-only is enforced, not trusted)`
  section (the ~20 lines of deny/allow/ask detail) with this shorter version:

```markdown
## Safety model (read-only is enforced, not trusted)

A `PreToolUse` Bash hook (`scripts/peek-guard.sh`) acts **only inside the
`peek-inspector` subagent** (it keys on `agent_type`) and **no-ops in your main
session**. Inside the inspector it classifies every command **deny / allow / ask**
(deny beats ask beats allow) and hard-blocks the deny floor with `exit 2`. The
subagent also has `Write`/`Edit` disabled as a coarse tool-level boundary.

→ **Full threat model: [docs/security.md](../../docs/security.md). How it works:
[docs/architecture.md](../../docs/architecture.md).**
```

- **Add** one line directly after the `## Why` paragraph:

```markdown
If you're on a remote session where `! <cmd>` shell mode is disabled, this is the
in-session replacement — see [docs/remote-sessions.md](../../docs/remote-sessions.md).
```

- [ ] **Step 3: Augment `standalone/README.md`**

Edit `standalone/README.md`: append, just before or after the closing paragraph, one
line:

```markdown
Most [use-cases](../docs/use-cases.md) apply to both versions; for the plugin-vs-standalone
trade-off in depth see [docs/architecture.md](../docs/architecture.md#plugin-vs-standalone).
```

- [ ] **Step 4: Verify the new README links resolve and the long safety section is gone**

Run:
```bash
# root README links
for l in docs/remote-sessions.md docs/use-cases.md docs/architecture.md docs/security.md; do
  [ -e "$l" ] || echo "BROKEN README.md -> $l"; done
# plugin README links (relative to plugins/peek/)
for l in ../../docs/security.md ../../docs/architecture.md ../../docs/remote-sessions.md; do
  [ -e "plugins/peek/$l" ] || echo "BROKEN plugins/peek/README.md -> $l"; done
# standalone README links (relative to standalone/)
for l in ../docs/use-cases.md ../docs/architecture.md; do
  [ -e "standalone/$l" ] || echo "BROKEN standalone/README.md -> $l"; done
# the long deny/allow/ask bullet list should no longer be in the plugin README
grep -q 'recognized read-only inspection commands' plugins/peek/README.md && echo "WARN: old safety prose still present" || echo "safety section trimmed ok"
echo "audit done"
```
Expected: `safety section trimmed ok`, `audit done`, no `BROKEN` / `WARN` lines.

- [ ] **Step 5: Commit**

```bash
git add README.md plugins/peek/README.md standalone/README.md
git commit -m "$(cat <<'EOF'
docs: trim READMEs to summarize-and-link into docs/

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Cross-cutting verification

**Files:** none modified — this task only validates.

- [ ] **Step 1: Full relative-link audit across all docs + READMEs**

Run from the repo root:
```bash
for f in docs/README.md docs/use-cases.md docs/architecture.md docs/security.md docs/remote-sessions.md README.md plugins/peek/README.md standalone/README.md; do
  dir=$(dirname "$f")
  # extract relative link targets, drop anchors and mailto/http
  grep -oE '\]\([^)]+\)' "$f" | sed -E 's/^\]\(//; s/\)$//; s/#.*$//' | while read -r link; do
    [ -z "$link" ] && continue
    case "$link" in http*|mailto*) continue;; esac
    target="$dir/$link"
    [ -e "$target" ] || echo "BROKEN: $f -> $link"
  done
done
echo "link audit done"
```
Expected: `link audit done` with **no** `BROKEN:` lines.

- [ ] **Step 2: Terminology lint (locked phrases, no drift)**

Run:
```bash
grep -rn 'guard floor' docs/ README.md plugins/peek/README.md && echo "DRIFT: use 'deny floor'" || echo "ok: no 'guard floor'"
grep -rqn 'deny floor' docs/architecture.md docs/security.md && echo "ok: 'deny floor' present" || echo "WARN: 'deny floor' missing"
grep -rqn 'exit 2' docs/architecture.md docs/security.md && echo "ok: 'exit 2' present" || echo "WARN: 'exit 2' missing"
grep -rqn 'agent_type' docs/architecture.md && echo "ok: 'agent_type' present" || echo "WARN: agent_type missing"
```
Expected: the three `ok:` lines and `ok: no 'guard floor'`; no `DRIFT`/`WARN`.

- [ ] **Step 3: Verbatim error string appears in exactly one place**

Run:
```bash
n=$(grep -rl 'Shell commands are only available in local sessions' docs/ README.md plugins/peek/README.md standalone/README.md | wc -l | tr -d ' ')
[ "$n" = "1" ] && echo "ok: verbatim string in exactly 1 file" || echo "FAIL: verbatim string in $n files (must be 1: docs/remote-sessions.md)"
```
Expected: `ok: verbatim string in exactly 1 file`.

- [ ] **Step 4: Confirm no behavior change — guard tests still pass**

Run:
```bash
bash plugins/peek/tests/test-peek-guard.sh; echo "exit=$?"
```
Expected: the suite passes, `exit=0`. (We touched no behavior files, so this must be green.)

- [ ] **Step 5: Confirm plugin schema still validates**

Run:
```bash
claude plugin validate plugins/peek
```
Expected: validation passes. (If `claude` isn't on PATH in the execution environment, note it and skip — this is a non-blocking sanity check.)

- [ ] **Step 6: Final manual render check**

Open each new `docs/*.md` in a GitHub/Markdown preview and confirm: code fences render, tables align, and the "Pick a door" links + "See also" footers click through. No commit needed for this step.

---

## Self-review (completed by plan author)

- **Spec coverage:** §4.1→Task 5, §4.2→Task 4, §4.3→Task 1, §4.4→Task 2, §4.5→Task 3,
  §5.1/§5.2/§5.3→Task 6, §6 (cross-linking/terminology)→Tasks 1–6 + audited in Task 7,
  §7 (canonical framing + one-place verbatim string)→Task 3 + enforced in Task 7 step 3,
  §8 (scope)→file table, §9 (testing)→Task 7, §10 (open items: branch/commit)→Commit
  policy note; (responsible-disclosure pointer) left out per spec, attacker section in
  Task 2 instead routes reports.
- **Placeholder scan:** no TBD/TODO; every doc step ships full skeleton + facts; every
  verification step has an exact command + expected output.
- **Anchor/link consistency:** `architecture.md` defines `## Plugin vs standalone`
  (→ `#plugin-vs-standalone`) used by Tasks 3, 4, 6; `security.md` defines `## Why
  `exit 2`` (→ `#why-exit-2`) used by Task 5 and within Task 2; the architecture
  linchpin anchor referenced from `security.md` matches the heading `## The linchpin:
  `agent_type` scoping`. Verify these anchors during the Task 7 render check.
