# 0002 — Prove the pipeline on this repo, before putting CI on the installer

- **Date:** 2026-10-04
- **Status:** accepted

## Context

Everything the README describes exists, and almost none of it has run. The
six-role team, the skill library, the GitHub App bot and the bridge landed in
one commit on 2026-10-04. The nine handoffs between six agents had never
carried a real change.

Two things competed for being first:

- **Prove the pipeline** (M1). Until one feature travels operator → Product
  Manager → GitHub issue → spec review → build → four reviews → merge without
  a human unsticking it, every other improvement is to a machine nobody has
  watched work.
- **CI on the installer** (M2). `install.sh` and `scripts/` are ~5,000 lines of
  shell with no shellcheck, no tests, and no automated exercise of the
  `--dry-run` and `--check` paths that exist to be safe. "`git pull &&
  ./install.sh` is safe any time" is a core promise resting on nothing — and
  agents were about to become the main authors of that shell.

The dogfood target was a second, linked question: this repo is the honest test,
but a pipeline bug here breaks the installer itself.

## Options

1. **Pipeline first, dogfooded on this repo.** The real thing, warts included.
2. **Pipeline first, on a lower-stakes repo.** Safer blast radius, but it
   proves the pipeline against a toy and leaves the installer's own workflow
   untested.
3. **CI first.** Agents merge to the installer only once something checks their
   shell — at the cost of leaving the pipeline unproven longer, while the team
   that would build the CI is itself the unproven part.

## Decision

Option 1, chosen by the operator on 2026-10-04.

The first run's subject is the two confirmed defects in **Known defects**
(https://github.com/dpeckham/my-ai-org/issues/6 then
https://github.com/dpeckham/my-ai-org/issues/5): small, self-contained, in the
installer, and blocking the pipeline anyway. They go one at a time, because both
edit `scripts/newproject.sh` and because one change at a time through an
untested pipeline keeps it clear whether a stall is the pipeline or the change.

Option 3 was rejected on sequencing, not on merit: the CI is itself a feature
someone has to build, and building it through an unproven pipeline would test
two unknowns at once.

## Consequences

- Agents will open pull requests against the installer before any automated
  check exists. The operator is the only gate, and merges nothing unread. M2
  closes this gap and is next.
- A pipeline bug found during the first run is found on this repo, where it may
  also break the installer. That is accepted: it is the same risk the product
  asks every operator to take, and finding it here is cheaper than finding it
  on someone else's project.
- Where the pipeline stalls is a deliverable of M1, recorded in the README's
  **Gotchas** or as issues — not an interruption to route around.
- The labels defect was worked around by hand (both labels created in this repo
  on 2026-10-04) so the first run is not blocked by the defect it carries. The
  fix is still owed for every other repo.
