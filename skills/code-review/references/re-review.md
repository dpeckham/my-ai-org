# Code review: re-reviewing

Part of the `code-review` skill. Read this when you are handed a PR you have
reviewed before — the Coder pushed fixes, or the PR moved after your approval.
`SKILL.md` carries the first-review method.

## Find where you left off

You have no memory of the last run, so read it off the PR. Your last review is
the newest bot review whose body starts with your role header; its
`<!-- reviewed-sha: … -->` stamp is the SHA you reviewed (prefer it over the
review's `commit_id`, which a force-push rewrites).

```bash
gh-bot api --paginate repos/<owner>/<repo>/pulls/<n>/reviews \
  --jq '.[] | {submitted_at, state, commit_id, body}'
gh-bot pr view <pr-url> --json headRefOid --jq .headRefOid
```

## Review the delta

Diff from your last-reviewed SHA to the current head — exactly what your last
verdict didn't cover:

```bash
gh-bot api repos/<owner>/<repo>/compare/<last-reviewed-sha>...<head-sha> \
  --jq '.status, (.files[] | {filename, status, patch})'
```

- If the comparison fails or reports `diverged` (a force-push or rebase rewrote
  history), the delta isn't trustworthy: re-review the whole PR at the head SHA.
- Re-check the changed-file list against the merge-base every round
  (`gh-bot pr view <url> --json files`); base movement is invisible to the
  delta.
- Read the Coder's replies in your threads and their Paperclip handoff for what
  they claim to have fixed, then check each claim against the delta.
- **Review the delta before re-approving.** A verdict nobody stood behind is
  worse than silence: it is confidently wrong and gets merged on.

## Re-post a verdict whenever HEAD has moved past your last one

- **Prior verdict approve**: re-post at the new HEAD — `--approve` if the delta
  is clean, `--request-changes` if it introduces problems — even when the verdict
  is unchanged and even for no-substance pushes (formatter, merge from base).
  Name the SHA ("Re-approving at `1a2b3c4`"). The trigger is the SHA mismatch,
  not whether the change was substantive: a fresh review re-attaches the
  approval to the current HEAD, so "was HEAD reviewed?" can be answered from the
  PR without asking anyone.
- **Prior verdict request-changes**: `--approve` if the delta fixes your
  findings; `--request-changes` again if not, naming which finding IDs or
  threads still stand.

The body states the SHA, the verdict and what changed; follow `posting.md`, and
remember the bar for new observations rises each round.

## Resolve what has been answered

When a thread you filed has been answered — by the new diff, the author's
clarification, or verified evidence — resolve it, so the operator sees no
outstanding asks. Only threads whose concern was actually answered; a thread
where the author replied without addressing the point stays open.

```bash
gh-bot api graphql -F owner=<owner> -F name=<name> -F n=<num> -f query='
  query($owner: String!, $name: String!, $n: Int!) {
    repository(owner: $owner, name: $name) { pullRequest(number: $n) {
      reviewThreads(first: 100) { nodes { id isResolved path line
        comments(first: 1) { nodes { body } } } } } } }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)'
gh-bot api graphql -f query='mutation($t: ID!) {
  resolveReviewThread(input: {threadId: $t}) { thread { isResolved } } }' -f t=<thread-id>
```

Your threads are the ones whose first comment starts with your role header —
every bot thread has the same author login.

The one exception: if a nit of yours should never have been a thread and is the
last thing blocking, resolve it and restate it in-thread as a suggestion. A
genuine finding stays open as the last blocker; that is a blocked merge working
correctly.

## Replies and disagreements

Reply only with something substantive — never "I agree" filler. Reply in-thread
with your role header:

```bash
gh-bot api repos/<owner>/<repo>/pulls/<n>/comments -F in_reply_to=<comment-id> \
  -f body="$(cat reply.md)" --jq .user.login
```

If the author rebuts a finding and you're convinced, say so briefly and resolve
it. **One back-and-forth per disagreement.** If it still stands after the
author's answer, state your position once, and per `team-workflow` take it to
the operator on the Paperclip issue rather than to a third exchange.
