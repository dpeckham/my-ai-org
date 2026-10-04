# Spec review: rounds after the first

Part of the `spec-review` skill, for the reviewer from the author's first
response onwards. `SKILL.md` carries the two passes and what a verdict comment
contains. The author obeys the matching half of the ordering rules below
(`answering.md`), which is what lets each side read the other's state from the
issue alone, across separate runs.

The Product Manager and you both post as the same bot, so the login never tells
you who wrote a comment or made an edit. **The role header does**: a response is
a comment headed `**Product Manager**`; your rounds are headed `**Lead Engineer
review**`.

## Read the delta, not the set again

You have no memory of the previous round, so reconstruct the "before" from the
issue:

1. Your last round's comment: its finding IDs and the `lastEditedAt` it
   published.
2. The author's response comment(s) since, per finding ID.
3. The body as it was at that `lastEditedAt`, from GitHub's edit history. Each
   `userContentEdits` node carries the full body text as of that edit (in the
   field named `diff`), newest first; take the newest node with `editedAt` at or
   before the stamp you published, and diff it against the current body:

   ```bash
   gh-bot api graphql -f query='{ repository(owner: "<owner>", name: "<name>") {
     issue(number: <n>) { body lastEditedAt
       userContentEdits(first: 20) { nodes { editedAt diff } } } } }'
   ```

   If the history doesn't reach back that far, read the current body against
   each finding instead, and say that is what you did.

A round reads that body diff and the response per finding ID. Nothing else: a
body that didn't move and a finding with no response are both answers.

## Ordering, and what a response means

**The author edits the body, then comments.** The comment is the receipt for
edits already made, so a response claiming a fix the body doesn't carry means
they landed out of order, not that the fix is missing.

Check before reporting a fix absent: compare the issue's `lastEditedAt` with the
response comment's `createdAt`. An edit stamped after the comment is the
out-of-order case; say so and re-read rather than reporting a false "not fixed"
the author must disprove.

**The body is quiescent once the response lands.** An author who edits again
after responding has opened a new round and says so in a fresh comment. A body
edit with no new response comment is a round still owed a receipt — say so
rather than reviewing half of it.

## Re-validate before you post — as a gate, not a step

A review takes time; on a body under active editing (the operator can edit it
too) the author can move past what you reviewed. Before composing the verdict,
re-read `lastEditedAt` for every issue in the round, in its own call, and read
the result first:

- Unmoved: post the verdict you composed.
- Moved: re-read that body and recompose its verdict against the new text.

Issuing the check in the same call as the post gates nothing — its answer
arrives after the comment has landed. The published `lastEditedAt` covers the
window this cannot close.

## Dispositioning, convergence, and the halt

A finding is **dispositioned** when the author fixed it or rejected it with
reasoning. Both are legitimate: **a rejection you accept is convergence, not a
loss.** One rebuttal each per disagreement; if it still stands after the
author's answer, it goes to the operator, not to a third exchange.

**Converged** when every blocking finding is dispositioned and you accept the
dispositions. Post the final `READY` verdict and hand the Paperclip issue on
(`SKILL.md`, "Ending the run").

**Cap unproductive rounds, not total rounds.** A round that disposes findings
and raises new ones from probing the fixes is the protocol working. Halt when a
round produces no newly dispositioned finding, or re-litigates one already
settled: post what remains as needing an operator decision, say that is what
you are doing, and per `team-workflow` comment on the Paperclip issue with the
open question, your recommendation and the options, and assign it to the
operator. Never halt a round that was still converging.

## Keeping the issue readable

Rounds pile up on a body people still have to read. At convergence you may
minimize the superseded rounds so only the final verdict stays expanded
(`RESOLVED` is the classifier that fits; `unminimizeComment` reverses it):

```bash
gh-bot api graphql -f query='mutation($id: ID!) {
  minimizeComment(input: {subjectId: $id, classifier: RESOLVED}) {
    minimizedComment { isMinimized } } }' -f id=<comment-node-id>
```
