# Additional project docs for `peek` (design)

**Date:** 2026-05-27
**Author:** Steven Chang
**Status:** Design — awaiting review before implementation plan

## 1. Purpose

Introduce `peek` from four angles it currently lacks dedicated coverage for —
**use-cases**, **architecture**, **security & threat model**, and the
**remote-session / no-`!` story** — by adding four focused docs under `docs/`
and trimming the existing READMEs to point at them.

The existing READMEs are good front doors but oversized for their job: the plugin
README crams a full safety model into 15 lines, the root README mixes install with
explanation, and there is no single place to send a new user that answers *"what is
this actually good for?"*. The design spec at
`docs/superpowers/specs/2026-05-27-peek-plugin-design.md` captures the original
decision rationale but is not a user-facing introduction.

## 2. Decisions locked during brainstorming

- **Four docs**, no more (no FAQ, no plugin-author lessons, no contributing guide yet).
  The fourth — `docs/remote-sessions.md` — was added in a second review pass after
  the user asked for the no-`!` story to have its own home.
- **Reorganize into a `docs/` site**: the new docs become the canonical home for depth;
  READMEs get trimmed to summary + link.
- **Use-cases style: cookbook** — 6–10 named scenarios, each ~2–4 sentences + one
  command + one sentence on what comes back. Skimmable and copy-pasteable.
- **No new top-level files** (no `SECURITY.md`/`ARCHITECTURE.md` at the repo root) —
  everything funnels through `docs/`.
- **`CLAUDE.md` unchanged** — it is the internal Claude-facing guide, a different
  audience from the new user-facing docs.
- **The "remote session / no `!` shell mode" angle is a first-class motivation**, not a
  footnote. Its **canonical home is the dedicated `docs/remote-sessions.md`**; every
  other surface (root README, plugin README, `use-cases.md` scenario #1,
  `architecture.md` opening, `security.md` preamble) gives a short paraphrase and
  links to it. See §7 for the shared facts and the per-surface treatment.

## 3. Layout

```
docs/
  README.md             ← index: 1-paragraph pitch + links + "which doc for what"
  use-cases.md          ← cookbook of 6–10 named scenarios
  architecture.md       ← deep-dive: linchpin, three-way guard, data flow
  security.md           ← threat model: defends-against / does-not, why exit 2
  remote-sessions.md    ← canonical home for the no-`!` / remote-control story
  superpowers/specs/    ← unchanged (existing design spec stays here)
README.md               ← trimmed: pitch + install + link to docs/
plugins/peek/README.md  ← trimmed: usage + "what's inside" + link to docs/
standalone/README.md    ← mostly unchanged + links to docs/
CLAUDE.md               ← unchanged (internal guide)
```

## 4. Per-doc content

### 4.1 `docs/README.md` (~60 lines)

- One-paragraph "what peek is" — tweet-sized.
- One-line note: "If you live in a remote Claude Code session where `! <cmd>` shell
  mode is disabled, `peek` is the in-session, read-only equivalent." → links to
  `remote-sessions.md`. (See §7.)
- "Pick a door":
  - *Want to use it?* → `use-cases.md`
  - *Want to understand it?* → `architecture.md`
  - *Evaluating whether to install?* → `security.md`
  - *On a remote/web session without `!`?* → `remote-sessions.md`
- Pointer to the canonical design spec under `superpowers/specs/` for the decision
  record (why exit 2, why three-way, etc.).

### 4.2 `docs/use-cases.md` (cookbook, ~6–10 scenarios)

Each entry: 2–4-sentence situation → one `/peek:peek …` command → one sentence on
what comes back. Initial scenario list (subject to refinement during implementation):

1. **Remote session where `!` shell mode isn't available** *(placed first
   intentionally — see §7)* — In remote Claude Code sessions, `! <cmd>` is
   disabled, so there's no shell escape for a quick look. `/peek:peek what changed`
   is the in-session, read-only equivalent. *Keep this entry to ~2 sentences and
   link to `remote-sessions.md` for the full story* (that doc is the canonical home;
   don't duplicate it here).
2. **Glance at git state mid-task** — `/peek:peek what changed`.
3. **Read a Markdown/config file verbatim** — `/peek:peek read CONTRIBUTING.md`
   (defeats the main session's tendency to summarize/render Markdown).
4. **Pre-commit "what am I about to ship"** — `/peek:peek staged diff`.
5. **Cold-start orientation in a new repo** — `/peek:peek folder structure`
   then `/peek:peek last 10 commits`.
6. **Diff archaeology** — `/peek:peek show HEAD~2`, `/peek:peek diff for src/foo.ts`.
7. **"Show me, don't tell me"** — escape hatch when the main session keeps
   editorializing instead of just showing the bytes.
8. **Untrusted-task safety check** — when running an agent you don't fully trust,
   `/peek:peek` gives you read-only ground truth without that agent's framing.
9. **Choosing between plugin and standalone** — short callout linking
   `standalone/README.md` and `architecture.md#plugin-vs-standalone`.

### 4.3 `docs/architecture.md` (~250–350 lines)

Sections (in order):

0. **Why this exists.** Briefly: `peek` is the structural answer to "I want to
   look at the repo without mutating it or flooding the main thread's context" —
   and it's the *only* in-session way to do that on remote sessions, which lack
   `!` shell mode. Keep this to ~3 sentences from the architecture angle (read-only
   by construction + context isolation), and link to `remote-sessions.md` (the
   canonical home) for the full motivation. See §7.
1. **The one fact that makes it all work** — `agent_type` scoping. The guard is
   registered session-wide on `Bash` but the first check is `agent_type ==
   "peek-inspector"`; absent on the main thread → `exit 0` with no output.
2. **Three-way classifier** — deny / allow / ask, with the precedence rule (deny
   beats ask beats allow). Why this matches Claude Code's native model.
3. **The deny floor is `exit 2`** — why other non-zero exits fail open; why this
   matters under `bypassPermissions`. `ask`/`allow` stay as exit-0 JSON.
4. **Compound-command handling** — splitting on `; | & && ||` and newlines, the
   reduction rule, `classify_git_dual` for read/write-overloaded git subcommands
   (`branch`, `config`, `remote`, `stash`, `worktree`, `reflog`, `tag`, `notes`,
   `symbolic-ref`).
5. **Defense in depth** — `disallowedTools: Write, Edit` on the subagent as the
   tool-level boundary that complements the Bash guard.
6. **Plugin vs standalone** — two delivery forms of the same idea: one
   enforced + isolated, one inline + trust-based. Explains *why* both exist and
   the trade-off; **defers the feature-by-feature comparison table to
   `standalone/README.md`** (canonical home) and links to it, per §6.
7. **Data flow** — ASCII diagram: `/peek:peek` → main agent → `peek-inspector`
   subagent → guard hook → Bash → output back.
8. **See also** — design spec, security doc.

### 4.4 `docs/security.md` (~200–300 lines)

Sections (in order):

1. **Threat model preamble.** Actor = a model that has been instructed (or
   coerced via prompt injection) to attempt mutation while inside the inspector.
   We do **not** model a malicious *user* — they don't need the inspector to run
   `rm`. We do **not** model platform/OS-level threats (kernel, shell-injection
   into bash itself, etc.). **Contrast with `!` shell mode**: `!` runs your raw
   shell as you, with no classifier and no isolation — it is fine because *you*
   typed the command. `peek` accepts the command from a *model*, so it needs the
   enforcement layer described below.
2. **What peek defends against** (with one-line examples for each):
   - Direct mutating commands (`rm`, `mv`, `git commit`, …).
   - Output redirection (`>`, `>>`, `2>`, `&>`).
   - Command/process substitution (`` ` `` …`` ` ``, `$(...)`, `<(...)`, `>(...)`).
   - Interpreter escapes (`bash -c …`, `python -c …`, `awk`, …).
   - Git write subcommands, including `--output`/`--output-directory` on
     read-form subcommands like `diff`/`show`/`log`.
   - `find` with `-delete`/`-exec`/`-execdir`/`-fprintf`/`-fls`/`-ok`.
   - Dangerous env overrides (`env -…`, `GIT_DIR=…`, etc.).
3. **What peek does *not* defend against**:
   - Main-session calls (out of scope by design — guard no-ops there).
   - `ask`-classified commands that the user's own permission config then allows.
   - Reading sensitive files — peek can read anything you can read; that's the
     point.
   - TOCTOU between classification and execution (acceptable for read-only
     commands; the worst case is reading a different file than expected).
4. **Why `exit 2`** — only exit 2 blocks the tool call in every permission
   mode including `bypassPermissions`; other non-zero exits fail **open**. This
   is the single most important security invariant. (Cross-link to the canonical
   design spec's §11 — `docs/superpowers/specs/2026-05-27-peek-plugin-design.md`
   — which documents how this was resolved.)
5. **Failure modes**:
   - `jq` missing → fail-closed *inside* the inspector (denies with install
     hint), no-op outside.
   - Guard script crash → no-op outside (scope gate is the first action and
     `jq`-free); inside, the inspector can't run anything because Bash returns
     control to the guard first.
6. **What an attacker would have to do.** Concrete walkthrough: to mutate via
   peek, an attacker would need to either (a) bypass `agent_type` scoping
   (requires a platform bug — please report to Anthropic), (b) find a
   classification gap in the guard (please report via repo issues), or (c)
   trick the user into approving an `ask`-classified command.
7. **See also** — architecture doc, design spec.

### 4.5 `docs/remote-sessions.md` (~80–120 lines) — canonical home for the no-`!` story

This is the single source of truth for the remote-session motivation; every other
surface paraphrases and links here. Sections (in order):

1. **The gap.** Local Claude Code terminal has `! <cmd>` as a quick shell escape;
   remote-control sessions (claude.ai/code; any session reached over the network)
   do not. The exact message, quoted verbatim **here and only here**:
   > Shell commands are only available in local sessions.
2. **Why it stings.** On remote sessions the fastest "just let me look" affordance
   is gone; the only way to inspect the repo from inside the session is to ask the
   model, via its tools, to do it for you.
3. **Why asking the model directly is not great.** Two failure modes: (a) the model
   can *mutate* (a stray `git checkout`, an over-eager "fix"), and (b) whatever it
   reads is *pulled into the main thread's context*, derailing the task you were on.
4. **How `peek` closes the gap.** A subagent that is **physically read-only** (the
   guard hook + `disallowedTools: Write, Edit`) and **context-isolated** (runs in
   its own thread; only a summary returns). Same UX local or remote.
5. **The three ways to "look," compared.** A small table:
   `! <cmd>` (local only, raw shell, no isolation) ·
   ask Claude directly (works everywhere, can mutate, pollutes context) ·
   `/peek:peek` (works everywhere, can't mutate, context-isolated).
6. **Caveat for the standalone `/peek`.** The lite standalone command runs *inline*
   (no subagent, no guard), so on remote sessions it restores read-only inspection
   but **not** the context isolation or the enforced guard — link to
   `architecture.md#plugin-vs-standalone` and `security.md`.
7. **See also** — use-cases, architecture, security, design spec.

## 5. README trims

### 5.1 `README.md` (root): ~74 lines → ~30 lines

- **Keep:** 1-paragraph elevator pitch, install block, standalone one-line
  install pointer, `jq` requirement, license.
- **Move out:** the "Lite local alternative" *explanation* (already in
  `standalone/README.md`), the "Layout" tree (move to `architecture.md` or drop),
  the longer safety prose (now in `security.md`).
- **Add:** one line near the top — *"More: [use-cases](docs/use-cases.md) ·
  [architecture](docs/architecture.md) · [security](docs/security.md)"*.
- **Add (callout near the pitch):** "Especially useful when you're on a remote
  Claude Code session (e.g. claude.ai/code) where `! <cmd>` shell mode is
  unavailable — `peek` is the read-only inspection escape hatch that does work
  there." Link to `docs/use-cases.md` for detail.

### 5.2 `plugins/peek/README.md`: ~75 lines → ~30 lines

- **Keep:** what it is (1 paragraph), usage block (the 7 example invocations),
  requirements, "what's inside" table.
- **Move out:** the full safety-model section (~15 lines) → replaced by a
  2-sentence summary + *"Full threat model:
  [docs/security.md](../../docs/security.md). How it works:
  [docs/architecture.md](../../docs/architecture.md)."*
- **Add (one line, after the "Why" paragraph):** "If you're on a remote session
  where `! <cmd>` shell mode is disabled, this is the in-session replacement."
  Link to `docs/remote-sessions.md` (paraphrase only — the verbatim error string
  is quoted there, not here, per §7).

### 5.3 `standalone/README.md`: ~28 lines → mostly unchanged

- Already lean. Add one link to `docs/use-cases.md` (most use-cases apply to
  both versions) and to `docs/architecture.md#plugin-vs-standalone`.

## 6. Cross-linking & terminology

- **One canonical home per topic.** Safety details live only in
  `docs/security.md`; architecture only in `docs/architecture.md`; use-cases
  only in `docs/use-cases.md`. READMEs *summarize and link* — never duplicate
  paragraphs.
- **Bidirectional**: each `docs/*.md` page ends with a *See also* footer linking
  siblings and the design spec.
- **Terminology consistency** (locked phrases): *linchpin*, *three-way guard*,
  *deny floor*, *`agent_type` scoping*, *exit 2*, *fail closed inside, open
  outside*. These are already established in `CLAUDE.md` and the design spec;
  use them verbatim across docs.
- **Internal links use relative paths**, never absolute URLs, so the docs render
  correctly on GitHub, in a local clone, and on any mirror.

## 7. The remote-session / no-`!` framing (canonical wording)

The **canonical home for this topic is `docs/remote-sessions.md`** (§4.5). Every
other surface paraphrases the facts below in its own voice and **links** to that
doc — never pastes its prose. The shared facts:

- **Local Claude Code terminal** supports `! <cmd>` as a quick shell escape.
- **Remote Claude Code sessions** (claude.ai/code; any session reached over the
  network rather than from a local terminal) **do not** support `!`. The exact
  message users see is verbatim:
  > Shell commands are only available in local sessions.
- That removes the fastest "let me just look at the repo" affordance for remote
  users, leaving only model-driven tool calls.
- Model-driven inspection has two failure modes worth naming: it can **mutate**
  by accident, and it **drags whatever it reads into the main thread's context**.
- `peek` is structured to remove both: a subagent that is **physically read-only**
  (guard hook + `disallowedTools: Write, Edit`) and **context-isolated**
  (subagent results return as a summary, not as ambient context for the main
  thread).
- This makes `peek` useful **everywhere**, but it is *especially* useful on
  remote sessions, where it is the closest in-session equivalent to a shell-mode
  affordance that simply does not exist.

Per-surface treatment:

| Surface | What it says about this | Roughly how long |
|---|---|---|
| `docs/remote-sessions.md` | **Canonical home** — the full story (§4.5). | ~80–120 lines |
| Root `README.md` | One-sentence callout near the pitch → link. | 1–2 lines |
| `plugins/peek/README.md` | One sentence after the "Why" paragraph → link. | 1–2 lines |
| `docs/README.md` (index) | One-line note + a "door" → link. | 1–2 lines |
| `docs/use-cases.md` | **Scenario #1**, ~2-sentence summary → link. | ~3 lines |
| `docs/architecture.md` | Opening **"Why this exists"** (§4.3 item 0), architecture angle → link. | ~3 sentences |
| `docs/security.md` | Contrast paragraph in the threat-model preamble (why `!` is fine and `peek` needs more enforcement). | ~3 lines |

**Important — do not duplicate prose.** Each surface paraphrases the facts above
in its own register and links to `docs/remote-sessions.md`. The verbatim error
string (*"Shell commands are only available in local sessions"*) is quoted in
exactly **one** place — `docs/remote-sessions.md` §1.

## 8. Scope / YAGNI

**In:**
- 4 new docs (`use-cases.md`, `architecture.md`, `security.md`,
  `remote-sessions.md`).
- 1 new index (`docs/README.md`).
- Trim 2 READMEs (root, `plugins/peek/`); minor addition to `standalone/README.md`.

**Out (for now):**
- FAQ / troubleshooting doc.
- Plugin-author lessons doc.
- Restructuring `docs/superpowers/specs/`.
- Screenshots, GIFs, or any non-Markdown assets.
- A docs website / static site generator.
- CI link-rot checks.
- Any change to `CLAUDE.md`.
- Any change to plugin or standalone *behavior* — i.e. the agent
  (`plugins/peek/agents/peek-inspector.md`), command
  (`plugins/peek/commands/peek.md`), hook (`plugins/peek/hooks/hooks.json`),
  guard (`plugins/peek/scripts/peek-guard.sh`), tests
  (`plugins/peek/tests/test-peek-guard.sh`), or `standalone/peek.md`. **The
  three README files (`README.md`, `plugins/peek/README.md`,
  `standalone/README.md`) *are* in scope** — they are docs, not behavior.

## 9. Testing & validation

- **Local render check** — verify each new doc renders correctly in a GitHub
  preview (relative links resolve, code blocks fence properly, tables align).
- **Link audit** — every `[text](path)` in every doc and trimmed README must
  resolve to an existing file in the repo; broken-link grep before commit.
- **No behavior change** — none of the *behavior* files listed under §8 "Out"
  are edited (agent, command, hook, guard, tests, `standalone/peek.md`); only
  the three README files and the new `docs/` Markdown change. So
  `bash plugins/peek/tests/test-peek-guard.sh` must still pass unchanged.
- **Terminology lint** — manual sweep: every doc uses the locked terms from §6
  consistently (no "guard floor" vs "deny floor" drift, etc.).

## 10. Open items to confirm at build time

- Whether to commit on `main` or a feature branch (raise with user before any
  commit; this is a docs-only change, so `main` is probably fine).
- Final scenario list for `use-cases.md` — the §4.2 list is a starting point;
  the implementation plan may trim or add based on what reads well together.
- Whether to add a brief "responsible disclosure" pointer in `security.md`
  (e.g., an email or "open a private GitHub security advisory") — currently
  out of scope; raise with user.
