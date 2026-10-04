# Spec review: answering a review

Part of the `spec-review` skill, for the issue's author (usually the Product
Manager) when spec-review findings come back. Writing the body in the first
place is `issue-writing`. This is not the review of the PRs that resolve the
issue; those are answered through `pull-requests`.

## What a round looks like

One comment per issue, headed `**Lead Engineer review**`, carrying a verdict —
`READY` or `CHANGES REQUESTED` — the `lastEditedAt` it was reviewed against, and
findings with IDs: `<issue>-B<n>` blocking, `<issue>-O<n>` observations.
`CHANGES REQUESTED` means at least one blocking finding; observations don't
block `READY`.

Compare that published `lastEditedAt` with the body's current one. If the body
moved after it, the round was made against text already replaced; say so rather
than answering findings that may no longer apply.

## Answering

**Edit the body first, then comment.** The comment is the receipt for edits
already made. The other order makes the reviewer read a body that doesn't yet
carry what you claimed, and report a fix missing that isn't.

Edit with `gh-bot issue edit <url> --body-file issue.md`, holding the new text
to `issue-writing`. Then post one response comment per issue, headed
`**Product Manager**`, **dispositioning every finding by ID**:

- **Fixed** — point at what changed in the body. The reviewer diffs the body,
  so don't reproduce the change.
- **Rejected, with reasoning** — a legitimate outcome, not stalling. A reviewer
  who accepts the reasoning converges on it.

A finding answered with neither is undispositioned, and a round of those halts
the review. Observations deserve a disposition too, but don't block. No
flattery: "Fixed: …" or "Rejected: …", not "Great catch!".

If a finding turns on a product question you can't settle — scope, priority,
anything the operator owns — don't guess: answer what you can, and say in the
response which finding waits on the operator. Escalate per `team-workflow`.

**Don't edit the body again after posting the response.** From that moment the
receipt is fixed and the reviewer reads against it. An edit you genuinely need
afterwards opens a new round: make it, then say so in a fresh comment.

## Handing back

Comment on the Paperclip issue (what you changed, what you rejected, the
response comment URL) and reassign it to the Lead Engineer. End the run; don't
wait for the next round.

## Where it ends

The review converges when every blocking finding is dispositioned and the
reviewer accepts; the final verdict says so and the issue moves on to be built. It
can also halt, when a round settles nothing new; the remainder then goes to the
operator.

Anything the review established that changes what a resolver should build must
be in the body, not only in the comments (`issue-writing`, "Maintaining
issues"): a fact living only in a comment is invisible to the handoff.
