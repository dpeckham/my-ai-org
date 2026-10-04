# 0001 — This repo keeps its product memory in `docs/`

- **Date:** 2026-10-04
- **Status:** accepted

## Context

This repo tells every project's Product Manager to keep durable product
memory in `docs/ROADMAP.md`, `docs/STATE.md` and
`docs/decisions/NNNN-title.md` (`templates/product-manager.md`, and the
kickoff issue `scripts/newproject.sh` files). It had none of its own.

`CLAUDE.md` describes the layout as "`install.sh` and the docs at the top"
and says "the top level stays this small", which reads as an argument for
`ROADMAP.md` and `STATE.md` beside the README.

## Options

1. **Top level** — `ROADMAP.md`, `STATE.md`, `decisions/` beside `README.md`.
   Matches the letter of the layout rule.
2. **`docs/`** — the same convention this repo prescribes to everyone else.
3. **Neither; track state in Paperclip issues only.** Rejected outright: the
   product's own premise is that git is the durable memory and Paperclip is
   disposable.

## Decision

Option 2. The repo follows the convention it ships. The alternative puts
three files and a growing directory of decision records at a top level whose
stated virtue is being small, and it means the one repo an operator reads to
learn the system is the one repo not laid out the way the system expects.

`CLAUDE.md` and the README's **Repository layout** were updated in the same
commit, so the rule now names `docs/` instead of being contradicted by it.

## Consequences

- Agents working here find roadmap and state exactly where their role
  instructions say to look, with no special case for this repo.
- `docs/` is a fourth top-level directory. The layout rule still holds for
  what matters: new scripts go in `scripts/`, and nothing else accretes at the
  top.
- If this repo ever grows user-facing documentation beyond the README, it
  lands in `docs/` too and will need separating from product memory.
