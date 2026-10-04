---
name: spec-review
description: Review a GitHub issue as a spec before anyone implements it — is it correctly diagnosed, resolvable cold, with runnable acceptance criteria, and does a set of issues hang together — posting one READY / CHANGES REQUESTED verdict per issue per round with finding IDs; and how the issue's author answers such a review. Load when the Lead Engineer is handed a GitHub issue to review before work starts, or asked whether an issue is ready to pick up; and when the Product Manager is handed back spec-review findings to answer. Not for reviewing a pull request — that is `code-review`.
---

> Adapted from [`dbaggott/claude-plugins`](https://github.com/dbaggott/claude-plugins) at commit `9a4c0b72c83ac8307d66338808f32077a923136c` (`dnbg-workflow/skills/issue-reviewer/SKILL.md`, `dnbg-workflow/skills/issue-reviewer/references/rounds.md`, `dnbg-workflow/skills/issue-workflow/references/spec-review-rounds.md`), licensed under the Apache License 2.0. Changes: removed the reviewer App setup, token minting, watchers and interactive prompts; rounds now span separate Paperclip runs, post via `gh-bot` with a role header, and hand off by Paperclip reassignment.

# Spec review

The artifact is the **issue body**, and the question is whether someone who
reads only that body can resolve it correctly. No code is written here.

- **Reviewing** (Lead Engineer): this file, then `references/rounds.md` from
  the second round on.
- **Answering a review** (Product Manager): `references/answering.md`.

**Spec review or code review?** If you were handed the issue itself to judge
("review the spec", "is this ready to pick up"), it is this skill. If you were
handed a PR, or the work resolving the issue, it is `code-review`. Decide from
what the Paperclip issue asks, not from whether a PR exists yet. If it is
genuinely unclear, take the spec review and say so in your handoff: it
terminates, and a wrong guess costs one bounded review.

## Before the first round

**Read every issue in the set before judging any of it** — set-level findings
are visible only once every body is in hand. Snapshot them in one call:

```bash
gh-bot api graphql -f query='{
  repository(owner: "<owner>", name: "<name>") {
    a: issue(number: <n>) { number title body lastEditedAt createdAt state }
    b: issue(number: <n>) { number title body lastEditedAt createdAt state }
  }
}'
```

Note each issue's `lastEditedAt`: your verdict publishes it, and the next round
is read against it. **A null `lastEditedAt` means the body has never been
edited** — treat it as unmoved, and use `createdAt` for its age.

## The mechanical pass comes first

Issue bodies have no CI, so broken markup, dead URLs and anchors that don't
exist reach the reader intact, and get missed when they share attention with
judgment. Compute these rather than eyeballing them:

- **Markup that won't render as intended** — unclosed or stray tags, broken
  tables, fences that never close.
- **Every URL resolves, to the thing the body implies.** Check a referenced
  issue or PR for state as well as existence (`gh-bot pr view <url> --json
  state`): a body that reads as if a PR is open when it merged sends the
  resolver somewhere that no longer exists.
- **Every cited anchor exists** — the file is at that path and the construct
  named at that line is the one there. A drifted line number is blocking when
  the argument rests on what sits there, an observation when the prose still
  locates the thing.

**Triage every match before reporting it.** Is it live text, or quoted (inside a
fence, backticks or a blockquote — a specimen, not a defect)? Is the path
resolved from the right root (repo-relative paths resolve from the repo root)?
A check that cries wolf gets skimmed.

## The judgment pass

Per issue:

- **Is the problem correctly diagnosed?** A real symptom with the wrong cause
  named, or a fix aimed at a downstream effect while the upstream defect
  survives to resurface (symptom, not root cause).
- **Do the load-bearing premises hold?** The mechanical pass showed the anchors
  exist; this asks whether the claims *about* them are true. Check the
  assumptions against the tree (false premise).
- **Is the approach the right one?** The problem can be real and correctly
  diagnosed while the proposed direction is costlier, less safe or worse fitted
  to the code than an alternative.
- **Can a cold resolver finish it?** With the body and nothing else, do they
  know what to build, which decisions are made, and how to tell they are done?
  Acceptance criteria that can't be run against this issue's merge commit are
  not acceptance criteria. Hold the body to `issue-writing`: direction captured,
  anchors verified, cross-references labelled, state-independent phrasing.

Across the set:

- **Overlap** — two bodies claiming the same work; each coherent alone.
- **Phasing** — an issue whose approach depends on what a later issue delivers.
- **Orphaned work** — something the plan implies that no issue owns.

**A set-level finding attaches to the issue whose body has to change**, which is
often not the one it is about: a phasing error goes on the issue that would
move, an overlap on the one that should shed scope. Orphaned work goes on the
nearest owner and says explicitly that it is unowned.

**Verify before asserting.** A finding about how the code behaves rests on code
you read, not memory; where you couldn't check, say so.

## Verdicts and findings

- **One verdict per issue per round: `READY` or `CHANGES REQUESTED`.** No third
  option; it leaves the author nothing to act on.
- **Every finding is blocking or an observation.** If you'd be content to see it
  left as it stands, it is an observation. `READY` may carry observations;
  `CHANGES REQUESTED` means at least one blocking finding.
- **Every blocking finding names the cost to a cold resolver** — what they would
  build wrong, waste, or miss. One that can't name a cost is an observation.
- **Findings carry IDs**: `<issue>-B<n>` blocking, `<issue>-O<n>` observation
  (`155-B1`, `156-O1`). The author answers per ID and the next round is read
  against them.
- **You do not edit the bodies.** A reviewer who fixes the artifact erases the
  record of what was wrong, and nobody reviews the fix.

## Posting a round

One comment per issue per round, never one per finding:

```bash
gh-bot issue comment https://github.com/<owner>/<repo>/issues/<n> --body-file round.md
```

The comment carries, in order: the role header `**Lead Engineer review**` on its
own line, the verdict, the `lastEditedAt` you reviewed against, the blocking
findings by ID, then the observations. Put long detail in a `<details>` block.
No flattery; findings only.

**Publishing `lastEditedAt` makes a round that straddled an edit detectable
afterwards**, and it is the "before" your next round diffs from.

**The comment is the record.** Anything you would tell anyone about the issue
goes in the GitHub comment; your Paperclip handoff links it rather than adding
to it. A conclusion only in Paperclip is invisible to the next reader of the
issue.

## Ending the run

Per `team-workflow`: comment on the Paperclip issue with the verdict per issue
and the comment URLs, then reassign — **all `READY`** to the UI Designer if the
issue is labelled `ui`, otherwise to the Coder; **any `CHANGES REQUESTED`** back
to the Product Manager. Then end the run; you are
woken again when the answer comes back.
