# Pull requests: answering a review round

Part of the `pull-requests` skill. Read this when a PR comes back to you from a
reviewer. `SKILL.md` carries the build flow and the description rules.

All reviewing roles post as the same bot, so the login doesn't say who sent the
work back. **The role header at the top of each review or comment does**
(`**Lead Engineer review**`, `**UI Designer review**`, `**QA Lead review**`,
`**Security review**`), and so does the Paperclip handoff. GitHub's review state
on the PR is only the bot's latest review, whichever role posted it; don't read
it as anyone's verdict but that one.

## Read the whole round

A verdict alone is a third of the review. Read all of it before changing
anything:

```bash
# Review bodies (verdict and non-inline findings)
gh pr view <pr-url> --json reviews,headRefOid \
  --jq '.headRefOid, (.reviews[] | {state, submittedAt, commit: .commit.oid, body})'
# Top-level comments
gh pr view <pr-url> --json comments --jq '.comments[] | {createdAt, body}'
# Every unresolved thread, with the id a reply and a resolve take
gh api graphql -F owner=<owner> -F name=<name> -F n=<num> -f query='
  query($owner: String!, $name: String!, $n: Int!) {
    repository(owner: $owner, name: $name) { pullRequest(number: $n) {
      reviewThreads(first: 100) { nodes { id isResolved path line
        comments(first: 20) { nodes { author { login } body } } } } } } }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)'
```

Inline findings don't appear in a review's body: a body saying "four things
below" with three bullets is normal, and the fourth — often the only real
defect — is only inline. Read every unresolved thread, not only the latest
reviewer's: a reviewer reads open threads as outstanding work, and a human's
thread blocks a merge as surely as the bot's.

**Read an approving review's body too.** Approvals carry deferred follow-ups,
scope notes and CI triage that never arrive as findings.

## Decide

Default to fixing inside this PR: the overhead of a follow-up (an issue, a
future run reloading the context) almost always exceeds one more commit on a PR
whose context is loaded. Decline a finding only when it is wrong, or out of the
PR's scope — real scope creep that would turn a tight PR into one needing its
own review cycle. Out of scope is what qualifies a deferral, not merely having
decided against it. Name each deferral in your handoff so the Product Manager
can file it.

If the branch now conflicts with the base, surface the conflict and escalate
rather than resolving it on your own: which side wins is not yours to decide.
After any rebase or merge from base, re-read the changed files before relying on
what you knew of them.

## Answer with the most durable artifact

Put the answer where the next review will look — **test > code > prose**:

1. **A test.** It proves the claim and fails loudly if it stops being true. The
   best answer to "are you sure this handles X?" by a wide margin.
2. **The code.** If the concern is real, the fix is the answer.
3. **The PR description**, for what you verified and how, the scope you checked,
   why one approach beat another. It is the as-built record.

**A code comment is the last resort**, and only when it would have earned its
place anyway: *will it still be true after the next change, and does it change
what someone does?* An answer that exists only because someone asked once is
transient, and reads as defensiveness to the next editor. A current,
non-obvious constraint a future editor needs was worth a comment before the
review; anything else goes in the PR description.

## Reply in the thread, and resolve what you addressed

A top-level comment doesn't close a thread, so answering there leaves the
finding looking untouched however well you fixed it. Reply in the thread
(headed `**Coder**`), then resolve it:

```bash
gh api graphql -f query='mutation($t: ID!, $b: String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $t, body: $b}) {
    clientMutationId } }' -f t=<thread-id> -f b="$(cat reply.md)"
gh api graphql -f query='mutation($t: ID!) {
  resolveReviewThread(input: {threadId: $t}) { thread { isResolved } } }' -f t=<thread-id>
```

Resolve only what you actually addressed. A thread you decline stays open with
your reasoning in it: that is a disagreement to surface, not a box to tick.
Findings that were in the review body rather than a thread get one reply
comment on the PR, per finding.

When a finding you already answered is raised again, say so once and point at
where the answer lives. Don't re-litigate it.

No flattery: "Fixed in `<sha>`: …", "Declined: …", not "Great catch!".

## Hand back

1. Push, and rewrite the PR description to the new as-built state.
2. Read the checks once (`gh pr checks <pr-url>`). Don't tell a reviewer a
   finding is addressed over a red build you just pushed; a round spent on it is
   a round nobody needed. Don't wait on checks still running.
3. Per `team-workflow`, comment on the Paperclip issue — what you fixed (with
   the new head SHA), what you declined and why, any deferral — and reassign to
   the Lead Engineer: once the code moves, every earlier approval is stale, so
   the PR goes back through the review chain, each reviewer checking only what
   changed since its last review. End the run.
