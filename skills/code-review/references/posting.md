# Code review: writing and posting the review

Part of the `code-review` skill. Read this before posting. `SKILL.md` carries
the method and the verdict rule.

## What earns a place in the body

Every observation costs a round whether or not it blocks: the author acts, HEAD
moves, and a moved HEAD owes a fresh review and a fresh CI run. That is the
right price for a real finding and pure loss for a musing. Test each one:

- **Could acting on it change a tracked file?** The bar is file-change
  potential, not interest. The PR description is the exception: editing it
  costs no push, no CI and no fresh verdict, so a stale claim there is worth
  raising precisely because fixing it is free.
- **Did this diff change it, or make it wrong?** Both count — a flipped default
  can leave a documented command wrong in a file the diff never touched.
  Neither, and it belongs to another PR.
- **Does your own phrasing argue it down?** "Defensible", "reasonable either
  way", "just noting": you've already concluded no change is needed; cut it.
- **Could you be wrong in a way only the author can check?** You see the PR and
  the repo, never the author's environment. A point that settles only by the
  author asserting private state: drop it, or phrase it so it costs no reply.
- **Re-reviewing? Would it have been worth raising in round 1 had the text
  shipped that way?** A correct fix wants confirming, not annotating. The bar
  rises each round.

Hand over the pacing decision in a sentence — "None of this needs a round before
merge" — not under a "Non-blocking" heading.

**Raise a message-only finding as "cut it", not "correct it".** Where the whole
remedy is editing shipped prose nobody acts on (a PR description, a commit
message), say the claim should come out: a corrected number drifts again next
commit.

**Keep CI status out of the body.** A check that changes your verdict is a
finding; one that doesn't belongs on the PR page, where it is live.

**Report verification selectively.** Verify as broadly as the review needs; say
so only where the author flagged an uncertainty, you checked wider than they
said, or you disagree. On an approval that narration justifies the verdict; on
a change request, compress it to a list of surfaces checked.

**A re-verdict body states the SHA, the verdict and what changed** — it doesn't
ratify the author's reasoning back at them or restate fixes visible in the diff.

## Avoid noise

No comment that is neither actionable nor informative — no "Reviewed, looks
good" filler, no recap comment after the review, no stream of top-level
comments. No flattery: "Nice work!" carries no information. A re-verdict on a
moved HEAD is not noise even when it is one sentence (`re-review.md`).

## Style

- Reference code as `api/server.go:42`, not "in api/server.go".
- Reference issues and PRs by full URL (`https://github.com/<owner>/<repo>/pull/35`),
  never bare `#35`.
- Be concrete: "returns `nil` when `lookup()` fails on line 67" beats "consider
  error handling".
- Be brief. Long reviews lose attention.

## Post one atomic review

Start the body with your role header, and end it with the SHA you reviewed, on
its own line:

```
<!-- reviewed-sha: <full 40-character head SHA> -->
```

A force-push rewrites a review's `commit_id`, so the review stops recording what
you looked at; the body is never rewritten, which makes this stamp the durable
record, and the anchor your next round diffs from.

**Verdict only** (no inline findings):

```bash
gh-bot pr review <pr-url> --approve --body-file review.md
gh-bot pr review <pr-url> --request-changes --body-file review.md
```

**With inline findings**, post the verdict and every inline comment as one
review through the reviews endpoint. Build the payload with `jq`, which handles
the quoting:

```bash
jq -n --rawfile body review.md --arg h '**Security review**' \
  '{event: "REQUEST_CHANGES", body: $body,
    comments: [
      {path: "api/server.go", line: 42, body: ($h + "\n\n<merge-blocking finding>")}
    ]}' \
  | gh-bot api repos/<owner>/<repo>/pulls/<n>/reviews --input - \
      --jq '{state, commit_id, user: .user.login}'
```

`event` is `APPROVE` or `REQUEST_CHANGES`, never `COMMENT` (and an inline comment
means `REQUEST_CHANGES`). Each comment's `line` must fall inside a diff hunk
(GitHub answers 422 otherwise) and refers to the new file (`side: RIGHT`); add
`"side": "LEFT"` for a removed line. Each inline comment starts with your role
header too.

**On a 5xx, list the reviews before retrying** — the write may have landed, and a
blind retry adds a second review:

```bash
gh-bot api repos/<owner>/<repo>/pulls/<n>/reviews \
  --jq '.[] | {id, state, commit_id, user: .user.login, submitted_at}'
```

It landed if a bot review at the head SHA starts with your header and has the
state you sent. List unfiltered; a filter that matches nothing looks the same as
nothing posted.
