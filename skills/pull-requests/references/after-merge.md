# Pull requests: after the operator merges

Part of the `pull-requests` skill. Read this when woken on a PR the operator has
merged. Clean up before starting any new work.

## Confirm it merged

Words on a Paperclip issue are not state: "merged" can mean "the button was
clicked and auto-merge is queued". Check:

```bash
gh pr view <pr-url> --json state,mergedAt,autoMergeRequest
```

- `MERGED` — clean up below.
- `CLOSED` without a merge — say so and stop; leave the branch in case it is
  reopened.
- `OPEN` with `autoMergeRequest` set — the merge is queued, not done. Say so on
  the Paperclip issue and end the run.
- `OPEN`, nothing queued — it hasn't merged. Say so; don't clean up.

## Clean up, in this order

1. If you used a worktree, remove it: `git worktree remove <path>`. Remove only
   what you created.
2. `git switch <default-branch> && git pull --ff-only --prune` — be on the
   default branch before fast-forwarding, so the pull can't move the wrong one.
3. Delete the local branch: `git branch -d <branch>`. On a squash-merge repo
   this fails, as expected: a squash rewrites the commits, so the branch tip is
   never an ancestor of the base. Where squash is the repo's method
   (`allow_squash_merge`), use `git branch -D` — the confirmed `MERGED` state
   is what authorises the force delete.
4. Delete the remote branch only if the repo doesn't (`delete_branch_on_merge`
   off): `git push origin --delete <branch>`. When it's on, step 2's `--prune`
   already cleared your view.

## Close the loop

Comment on the Paperclip issue under exactly these three headings, in order.
Print all three every time; an empty one says so in a few words — an omitted
section reads as both "nothing there" and "never considered".

- **Summary** — the PR by full URL, what shipped as built, and how review went
  (rounds, which roles sent it back, what review changed). If it shipped only
  part of the issue, say which part, so the Product Manager can mark it shipped
  in the body (`issue-writing`, "Maintaining issues").
- **Observations** — informational only: something surprising in the code you
  touched, an assumption the change now rests on.
- **Actionable** — the narrow section; doubt resolves toward Observations. A
  follow-up a reviewer raised that you deferred as out of scope, config the
  merged change now needs, an out-of-scope defect you left alone. One line each,
  naming the concrete next step and where. A clean cycle often leaves it empty.

Don't act on the Actionable list yourself: filing and fixing are the Product
Manager's and operator's call. Hand off per `team-workflow` and end the run.
