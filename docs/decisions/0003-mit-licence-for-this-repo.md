# 0003 — MIT, with the upstream Apache-2.0 material kept as it is

- **Date:** 2026-10-04
- **Status:** accepted

## Context

This repository is public and had no licence file, so default copyright
applied: nobody who found it could legally copy, modify or run it. That
contradicts what the repository is. `CLAUDE.md` says `./install.sh` builds the
organisation "for its owner and for anyone else", and the whole README is
written as a manual for a reader who is not the author, under a standing rule
that nothing project-specific appears in it. The repository had been
generalised for other people to use, and the one file that would let them was
missing.

The third-party half was already correct, which is what made the gap
conspicuous. `skills/sources.manifest` pins the one externally-sourced skill
to a commit of `dbaggott/claude-plugins`,
`skills/LICENSE-dbaggott-claude-plugins` carries that project's Apache-2.0
text, and `skills/THIRD_PARTY_NOTICES.md` records the attribution, the
derivative-work relationship and the modifications. Four skills here
(`code-review`, `issue-writing`, `pull-requests`, `spec-review`) are modified
derivatives of that Apache-2.0 material.

Which licence is not an agent's call: it decides what other people may do with
the work, and it is effectively one-way once anyone relies on it. It was put
to the operator rather than guessed.

## Options

1. **Apache-2.0.** Matches the upstream the adapted skills derive from, so the
   whole tree lands on one licence and the derivative-work question
   disappears. Longer, and carries an explicit patent grant and a
   NOTICE/state-changes obligation.
2. **MIT.** Short and permissive, and the licence most readers of a shell
   installer expect. Leaves two licences in the tree.
3. **Leave it unlicensed.** Rejected: it is the status quo that caused this,
   and on a public repository it is a barrier, not a neutral position.

## Decision

Option 2 — **MIT**, copyright holder **Dave Peckham**, year 2026 (the
repository's first commit, `eb6df10`, is dated 2026-09-16). The operator chose
the licence directly and gave the holder line in answer to a question raised
for the purpose; neither half was inferred.

The existing Apache-2.0 material stays exactly as it is. The operator's
decision says so explicitly, and nothing about adding MIT at the root requires
touching it: Apache-2.0 permits the modified derivatives, and the attribution
already in each `SKILL.md` and in `skills/THIRD_PARTY_NOTICES.md` is what
satisfies it.

Per-file SPDX headers were rejected as the mechanism. They are defensible for
a library meant to be copied file-by-file; here they are churn across 19 shell
scripts, they fight this repo's comment rule ("comments that explain *why*"),
and a root `LICENSE` covers the repository without them.

## Consequences

- Two licences live in the tree: MIT for this repository's own scripts,
  templates and locally-authored skills, and Apache-2.0 for the upstream
  material the four adapted skills derive from. A reader needs both
  `/LICENSE` and `skills/THIRD_PARTY_NOTICES.md`, so the README's licence
  section points at the second from the first.
- `LICENSE` must hold the canonical MIT text unaltered. GitHub detects a
  licence by matching that template, so a reworded MIT would leave the
  repository reporting no licence at all — the thing this decision exists to
  fix.
- The same decision covers the operator's other repository, which takes MIT
  under the same holder line. Nothing here depends on that.
- Reversing this is not practical once anyone relies on it, which is why it
  went to the operator rather than being chosen here.
