# Pull requests: picking up an issue

Part of the `pull-requests` skill. Read this on first pickup, before touching
any file. `SKILL.md` carries the build steps that follow.

The issue body is the contract. Once the freshness probe passes, trust the
author's labelling and don't re-research what is already inline. Trusting the
research is not accepting the conclusions: the body still gets a critical read
before any code, the way code gets a review before it merges.

## Read, probe, follow links sparingly

- **Read the body first.** It usually carries enough; links are supplementary.
- **Run a cheap freshness probe.** Bodies rot: work partly ships, mechanisms get
  superseded. Mechanically check the anchors — do the named files and functions
  exist in the current tree; are referenced PRs in the state the body implies
  (`gh pr view <url> --json state`)? This is existence and state checking, not
  re-research. If the body contradicts the tree, stop (below): the issue may be
  half-shipped, and implementing it duplicates landed work.
- **Follow a link only if both hold:**
  1. Your current context doesn't answer a specific question you need to
     proceed ("what columns does the new table have?", not "what's the
     background?").
  2. The link is under "Required reading", or is called out as holding the
     answer.
- **Hard cap at depth 1.** If a followed link contains another link, stop. If a
  second hop seems necessary, ask the specific question instead (below) — one
  answer is cheaper than reading three more linked PRs.
- **Prefer one targeted fetch.** Need one file from a linked PR? Fetch it
  (`gh api repos/<owner>/<repo>/contents/<path>?ref=<sha>`), not the whole PR.

Anti-patterns: reading everything under "Related (optional)"; reading a linked
PR's full diff when its description is what matters; following links
transitively (issue → PR → design doc → discussion). When unsure whether a link
is critical, don't follow it.

## Read the issue critically before implementing it

An issue is written by a fallible author and earns the same scrutiny as code.
The freshness probe asks "is the body still true?"; this asks "was it ever
right?" — an issue can be perfectly current and still misdiagnosed. The spec
review already asked this, from someone who won't implement it; you are the one
about to, and you will read code the reviewer didn't. This pass is mandatory on
every issue, including a well-anchored one, and "it's sound" is a conclusion you
reach by probing, not the default when nothing jumps out. Probe for:

- **Misidentified problem** — the symptom is real but the stated cause is wrong.
- **Symptom, not root cause** — the fix papers over a downstream effect; the
  defect upstream will resurface.
- **Wrong approach** — correctly diagnosed, but the proposed direction is
  costlier, less safe or worse fitted to the code than an alternative.
- **False premise** — the issue assumes a behaviour, constraint or structure
  that doesn't hold. Check the load-bearing assumptions against the tree, not
  just that the anchors exist.

The output is a position: the issue is sound and you will implement it, or it
has a problem you can name. Don't silently re-route (the author may know
something the body doesn't, and diverging is a design decision), and don't
faithfully implement what you believe is wrong.

## Match your handling to how grounded the issue is

- **Grounded** — the approach is articulated against real code (a verified
  "Proposed approach"). If the critical read passes, implement it; don't
  redesign a settled direction for taste. No separate approval is needed — the
  author made the design decision and your review is the check on it. That is
  only cheap because the review was real.
- **Under-researched** — a real problem or goal, perhaps with hints, but no
  code-grounded proposal. Designing it is a new decision the author never made.

## When to stop and hand back

The run is unattended, so nobody can approve a design mid-run, and designing and
implementing in one unattended shot is exactly how a confident wrong approach
ships with no gate. Stop before writing code when:

- the freshness probe shows the body contradicts the tree;
- the critical read finds a problem you can name;
- the issue is under-researched and you would be doing the design;
- a second link hop seems necessary.

Then post on the GitHub issue (`gh issue comment <issue-url> --body-file c.md`,
headed `**Coder**`): what you found, the evidence, and — where you are proposing
a design — a recommendation with the alternatives and your reasoning, not an
open question. Per `team-workflow`, comment on the Paperclip issue linking it,
reassign to the Lead Engineer for technical questions or the Product Manager for
product ones, and end the run.
