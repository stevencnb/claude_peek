---
description: Read-only repo inspection — git state, folder structure, file contents. Lightweight local version of the peek plugin (runs inline; no isolated subagent or guard hook).
argument-hint: <what to inspect, in plain English>
disallowed-tools: Write Edit
---

Read-only inspection of this repository — the user wants to look, not change anything.

Run the **minimal** set of **read-only** commands that answer the request below, then
return their **raw output verbatim** in fenced code blocks (label each block with its
command when you run more than one). Do **not** modify anything, and do **not** advise,
suggest fixes, or summarize away detail — just show what the commands produced.

> $ARGUMENTS

If the request above is empty, ask what to inspect, offering examples: "what changed",
"last 5 commits", "diff for <file>", "staged diff", "folder structure", "read <path>",
"show <commit>".

## Read-only command guidance
- "what changed" → `git status`, then `git diff` (add `git diff --staged` for staged).
- "staged diff" → `git diff --staged`.
- "last N commits" → `git log -N` (or `git log --oneline -N`).
- "diff for <file>" → `git diff -- <file>` (and `git diff --staged -- <file>`).
- "show <commit>" → `git show <commit>`.
- "branches" → `git branch -a`.
- "folder structure" → `git ls-files` (tracked, respects `.gitignore`); for a fuller tree
  `tree -L <depth>`, falling back to `find . -not -path './.git/*'` when `tree` is missing.
- "read <path>" → the **Read** tool. Search inside files with **Grep**; find files with **Glob**.

Never run mutating or escaping commands: no `add`/`commit`/`push`/`checkout`/`reset`/
`restore`/`rm`/`mv`/`stash`/…, no output redirection (`>`/`>>`), no command substitution.
If a request would require changing anything, reply exactly: **"peek is read-only and does
not do that."** and stop.
