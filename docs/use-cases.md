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
