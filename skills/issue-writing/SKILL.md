---
name: issue-writing
description: How to write and maintain a GitHub issue so whoever resolves it can do so from the body alone — capturing the direction, verified anchors, required-reading vs optional cross-references, state-independent phrasing, runnable acceptance criteria, and labels. Load before creating any GitHub issue (a feature, a bug, a follow-up), before editing an issue body, and whenever you touch an issue whose work has partly shipped or whose referenced PRs or issues have changed state. Used by the Product Manager and the Lead Engineer, and by the UI Designer when adding a design section to an issue.
---

> Adapted from [`dbaggott/claude-plugins`](https://github.com/dbaggott/claude-plugins) at commit `9a4c0b72c83ac8307d66338808f32077a923136c` (`dnbg-workflow/skills/issue-workflow/SKILL.md`, `dnbg-workflow/skills/issue-workflow/references/creating.md`, `dnbg-workflow/always-on-rules.md`), licensed under the Apache License 2.0. Changes: removed claim labels, plugin-specific tooling and interactive operator prompts; adapted to unattended Paperclip runs and the shared `gh-bot` identity.

# Issue writing

An issue is a handoff. You have rich context when you write it — the
conversation, the code you just read, the direction just agreed. The agent that
resolves it has only the body, read cold, in a short unattended run. Three
failures this prevents:

- **Wasted research.** Unlabelled cross-references force the resolver to follow
  every link (spending its budget before any code changes) or skip them (and
  maybe miss the one that mattered).
- **Wrong implementation path.** A body that was clear in the context of its
  creation reads as open-ended to a cold resolver, who picks a different
  approach. The outcome should not depend on which agent picks it up.
- **Rotted handoff.** The body was true when filed, then part of the work
  shipped or a referenced PR closed, and the resolver faithfully implements
  stale truth.

Post as the bot: `gh-bot issue create --repo <owner>/<repo> --title … --body-file
issue.md`, and `gh-bot issue edit … --body-file` for edits. Per `github-bot`,
the body and every comment you post start with your role header (for example
`**Product Manager**`). This flow is GitHub-only; if the repo is not on
`github.com`, say so on the Paperclip issue instead of trying.

## Write a self-documenting body

A cold reader must understand the problem, the intended direction, and what
"done" looks like without clicking through to anything else.

### Capture the direction, not just the problem

This is the highest-value section. There is almost always a direction in the
surrounding context when you file; that context dies with your run.

- **If a direction exists, a "Proposed approach" section is mandatory.** Name
  the approach, the files, functions or modules involved, and the alternatives
  considered and rejected, with the reason. The rejection reason is what stops
  the resolver rediscovering the dead end.
- **Anchors are verified, not recalled.** Check every file path, function name,
  schema field or external identifier against the current tree (or the external
  source) before filing, and say so ("Verified present at `src/auth.ts:40`").
  One wrong anchor costs more than none: the resolver stops trusting the whole
  body and re-researches everything.
- **If the direction is mostly set but real unknowns remain, add "Open questions
  / decisions for the implementer".** Frame each as a decision with a default —
  "X or Y; default X because Z" — never an open musing. Without the default the
  resolver stalls or silently picks.
- **If the issue is genuinely open-ended, say so** ("No preferred approach;
  evaluate X vs Y and pick"). That marks the openness as intended, not an
  omission, and licenses the design work.
- **Acceptance criteria and constraints go inline.** "See the linked PR for the
  design" is not enough; paste the relevant parts.
- **Every acceptance criterion must be runnable at the end of this issue.**
  Litmus: can it be checked against this issue's merge commit alone? A criterion
  that needs a route, schema or operation another issue introduces becomes a
  test nobody can write or a box ticked by inspection. Move it to the issue that
  supplies the missing piece and leave a pointer. For an invariant two issues
  share, **assert it in the issue that introduces the operation that could break
  it**, not the one that states it — the owning issue usually can't run it, so
  the guard ships untested exactly where the risk is.

### Inline summary over links

- Paste a schema, a reviewer's specific concern or a short code excerpt into
  the body and cite the source URL beneath it.
- Link only when the content is genuinely irreducible (a long design doc, a
  large diff, logs), and summarise its conclusions inline anyway.
- Don't link a recently merged PR in place of describing what changed.
- **Carry conclusions, not the investigation story** — each conclusion with its
  minimal supporting fact ("the retry path drops the dedup key — see
  `queue.go:112`"), not the narrative of how you found it.
- **Don't argue for the issue's own shape** (why one issue not three, why it
  isn't a duplicate). Keep any real constraint ("X cannot land before Y") and
  attach it to the thing it constrains.

Writing it this way costs you a few minutes once; every link a reader must
traverse costs every future reader the same traversal.

### Label every cross-reference

Put cross-references in one of two titled groups:

- **Required reading** — the resolver must read these before starting. Keep it
  ruthlessly short; each entry is a tax on the resolver's budget.
- **Related (optional) — do not read unless blocked** — background only. The
  literal "do not read unless blocked" tells a resolver it may skip them.

An unlabelled reference looks load-bearing, so the resolver pays for it either
way: label it or omit it. Resolvers follow links only to depth 1 (see
`pull-requests`), so anything a resolver needs must be at most one hop away.

### Write state-independent references

Where the body's truth depends on another issue or PR's future state, phrase it
as a condition that holds in every state — "while X exists", "any run without a
registration row" — not a snapshot — "until X lands", "once X merges". A
snapshot owes an edit when the world changes, even if nobody touches the issue
again; a condition never does.

The same for case lists: state the contract ("the fallback covers any request
with no session row") and mark any enumeration as illustrative.

Litmus before filing: for each cross-reference, "if the referenced thing
resolves first, does this body need editing?" If yes, rephrase.

### Reference issues and PRs by full URL

Always `https://github.com/<owner>/<repo>/issues/19` or `…/pull/35`, never bare
`#19` or `<owner>/<repo>#19` — on every surface: issue bodies, comments, PR
descriptions, commit messages, Paperclip comments. A bare number resolves only
inside its own repo, and only a full URL is clickable everywhere (raw terminal
text needs a scheme). GitHub renders full URLs to its own issues as short links,
so nothing is lost. When building a URL from a bare number of unknown type, use
`/issues/N`; GitHub redirects between `/issues/N` and `/pull/N`.

## Label the issue

Labels sort along independent axes; apply one from each that fits:

- **Type** — `bug`, `enhancement`, `documentation`, etc. Exactly one. It is the
  first filter a triager uses, so an issue without one is invisible to that pass.
- **Area** (`area:*`) — the subsystem. At least one; two if it genuinely spans
  two. The valid set is per repo and self-describing: run `gh-bot label list
  --repo <repo> --search area` and read the descriptions. If none fits and the
  issue belongs to a recurring subsystem, don't create a label yourself —
  propose `area:<kebab>` with a one-line description in your Paperclip comment
  for the operator to decide. The set stays human-curated; ad-hoc labels
  fragment it (`area:db` vs `area:database`).
- **`ui`** — add it when the change alters anything a user sees. It routes the
  issue through the UI Designer, before build and again at review
  (`team-workflow`).

## Maintaining issues

The cheapest maintenance is the one never owed: state-independent references
avoid most of it. For the drift that remains:

**The body is the current truth; comments are history.** A resolver reads the
body as "this is the work", and won't reconstruct truth from a comment thread.

This is not a patrol duty. It triggers when you touch the issue for any reason —
commenting, shipping part of it, a PR it references merging or closing. For a
merged PR, find the issues to sweep with `gh-bot pr view <url> --json
closingIssuesReferences` plus any issue URLs in the PR description (this is
maintenance, so the depth-1 reading cap doesn't apply). Then bring the body back
to current truth:

- **Mark shipped work shipped**, with the PR URL, instead of leaving it as open
  work a resolver would re-implement.
- **Promote facts from comments into the body.** Evidence or decisions that
  arrived as comments — including findings settled in a spec review — are
  invisible to the handoff until they are in the body.
- **Sweep cross-references on state changes.** When a referenced PR or issue
  closes or is superseded, fix the text that depends on it.

## Honesty

- **Verify before asserting.** Anything the body states about how code or an API
  behaves, check it (read the source or the docs) or hedge it explicitly ("not
  verified: …"). Don't write from memory.
- **No flattery** in comments or replies — no "Great point!". State the
  substance.

Handing the issue to the next role is in `team-workflow`. A spec review of what
you filed, and how to answer it, is `spec-review`.
