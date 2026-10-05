# 0008 — The diverged checkouts held nothing wanted

- **Date:** 2026-10-05
- **Status:** accepted
- **Filed as:** https://github.com/dpeckham/my-ai-org/issues/20 (step 8)
- **Context:** https://github.com/dpeckham/my-ai-org/issues/17 is the mechanism;
  this is the disposal decision about its effects.

## Context

Two Paperclip-owned workspace checkouts had a local `main` ahead of
`origin/main` with a dirty working tree — the shared-working-copy failure in
issue #17. DevOps cleared them to a clean `main` at `origin/main` without
deleting anything, parking every local-only commit and the dirty tree on pushed
branches first:

| Branch | Tip | Holds |
|--------|-----|-------|
| `rescue/my-ai-org-2026-10-05` | `d4d3bc6` | the 10 former local-only commits |
| `rescue/my-ai-org-2026-10-05-worktree` | `12127c3c` | the dirty tree at cleanup |

The remaining question was a product one, and only a product one: **is any of
that parked work wanted that is not already in an open pull request?**

The reported state was nine local-only commits; it was ten. The tenth,
`d4d3bc6`, was the only one of them absent from every branch on the remote, so
the premise that the nine named commits were the whole set would have lost it.
That is why this was checked rather than assumed.

## Decision

**Nothing in either rescue branch is wanted. Both are disposable.** All the
product content they carry is already on open pull requests awaiting the
operator's merge, and the two artefacts unique to the checkout carry no content
at all.

Three findings, each verified rather than inferred:

**1. Nine of the ten commits are already on PR #12.** `git branch -r --contains`
puts `e0518df`, `98510d8`, `ef24a56`, `c4b1aa2`, `4e99896`, `79dcff6`,
`64ae53d`, `e102ede` and `4f3898b` on `pm/github-native-edition-brief`
(https://github.com/dpeckham/my-ai-org/pull/12), and the first four of them
also on `pm/roadmap-and-state`
(https://github.com/dpeckham/my-ai-org/pull/4). Nothing to recover.

**2. The tenth commit carries no unique content.** `d4d3bc6` "Paperclip SSH
sync merge 4f3898b757b5" is a two-parent merge of `origin/main` (`1c9c1b4`) with
`4f3898b`, and it is a plain automatic merge with no conflict resolution and no
edits of its own:

```
$ git merge-tree --write-tree 1c9c1b4 4f3898b
ff5c58ce8a1aa9356113b5d1749223dcd5cf0919
$ git rev-parse d4d3bc6^{tree}
ff5c58ce8a1aa9356113b5d1749223dcd5cf0919
```

The recomputed merge tree is the commit's own tree, byte for byte. There is
nothing in `d4d3bc6` that is not in one of its parents, so there is nothing in
it to want. Its only effect was to put nine unreviewed commits one `git push`
away from `origin/main`.

**3. The dirty tree was stale sync output, not work.** It changed three files,
and all three *removed* content: the `.paperclip-runtime/` ignore rule from
`.gitignore`, and the description of `docs/` from `CLAUDE.md` and `README.md`.
Each of the three is byte-identical to `origin/main`'s version of that file and
differs from PR #12's:

| File | Dirty tree | `origin/main` | PR #12 |
|------|-----------|---------------|--------|
| `.gitignore` | `479c7221` | `479c7221` | `0182b2cf` |
| `CLAUDE.md` | `47588742` | `47588742` | `8e7b1d58` |
| `README.md` | `b0c9b79a` | `b0c9b79a` | `f65a10a0` |

So the uncommitted change was not someone editing those files; it was the sync
writing `main`'s older content over the branch's newer content. Taking it would
revert work that PR #12 is open to land. **Rejected**, and it would have been
rejected even read as authored work: the `docs/` descriptions and the
`.paperclip-runtime/` ignore rule are all wanted.

## Consequences

- **Nothing is lost and nothing needs rescuing.** The wanted content sits on
  four open pull requests, awaiting the operator's merge.
- **The rescue branches can be deleted** once PR #12 is merged. They are kept
  until then only as cheap insurance; nothing references them.
- **PR #12 carries the `.paperclip-runtime/` ignore rule**, so until it merges,
  every agent run's workspace reports `.paperclip-runtime/` as untracked. That
  noise is part of what made this diverged tree hard to read, which is a small
  argument for merging it sooner rather than later.
- **This repo's `docs/ROADMAP.md` and `docs/STATE.md` are themselves still
  unmerged** (PR #4), so this record cannot cite or update them. The state entry
  for the cleanup rides on that stack.
- **The standing push risk from issue #20 is gone** — both checkouts are clean,
  so no `git push` from them can carry unreviewed commits onto `origin/main`.
  The missing branch protection (issue #11) and the mechanism that diverged the
  checkouts (issues #17, #19) are untouched by this and remain open.

## The open pull requests are not a clean stack

Checking the above turned up something worth recording, because it is invisible
in the pull request list. The three Product Manager branches are **not** nested:

- `pm/roadmap-and-state` (#4, 4 commits) **is** contained in both of the others.
- `pm/github-native-edition-brief` (#12, 10 commits) and
  `pm/recovery-path-decision` (#21, 11 commits) have **diverged**. Neither
  contains the other. #12 carries `174f8ce`; #21 carries `ac51ea5` and
  `4c0eb67`.

Both of those branches add a decision record **numbered 0006** — #12 as
`0006-the-run-workspace-is-disposable.md`, #21 as
`0006-a-sweep-routine-re-wakes-stalled-work.md`. Different filenames, so git
merges both without a conflict and `main` silently ends up with two decision
0006s, after which "decision 0006" names two different decisions and the
sequence has forked.

**Resolved by renumbering, not deferred to merge time.** #12 keeps 0006: it is
the older pull request and issue #20 already cites that filename. #21's becomes
`0007-a-sweep-routine-re-wakes-stalled-work.md`, with its references in
`docs/ROADMAP.md` and `docs/STATE.md` updated on that branch. This record is
0008 for the same reason.

Both branches do edit `docs/ROADMAP.md` and `docs/STATE.md`, so merging the
second of them will need a real conflict resolution. That is expected and is the
operator's to sequence; the renumbering is what stops a silent duplicate.
