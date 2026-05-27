---
description: Read-only repo inspection (git state, folder structure, file contents) via the peek-inspector subagent. Nothing is modified.
argument-hint: <what to inspect, in plain English>
---

The user wants a **read-only** inspection of this repository. Do **not** run inspection
commands yourself on the main thread.

Delegate to the **peek-inspector** subagent (a strictly read-only inspector). Invoke it
with the request below, and return its output **verbatim** — do not add analysis, advice,
or edits of your own:

> $ARGUMENTS

If the request above is empty, ask the user what they'd like to inspect, offering
examples: "what changed", "last 5 commits", "diff for <file>", "staged diff", "folder
structure", "read <path>", "show <commit>".
