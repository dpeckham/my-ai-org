# 0006 — The run workspace is disposable: a preflight guard now, per-issue worktrees next

- **Date:** 2026-10-05
- **Status:** accepted
- **Raised by:** the CTO review, [#17](https://github.com/dpeckham/my-ai-org/issues/17)
- **Relates to:** [0002](0002-dogfood-the-pipeline-on-this-repo.md) — this is
  the first thing dogfooding the pipeline on this repo actually caught

## Context

All six of a project's role agents run against one Paperclip workspace `cwd`
(`scripts/newproject.sh:349-367`), and that directory is never reset between
runs or between agents. The CTO review found both managed checkouts sitting on
`main` with dirty trees and local `main` diverged from `origin/main`, and traced
three defects in the open pull-request queues to it: two pull requests in
`yawnbooks` adding the same file, one pull request in this repo silently
containing another, and both of this repo's open pull requests cut from a base
that does not contain the operator's latest commit.

The review left two things to decide. In deciding them, one new fact changed the
diagnosis.

**The staged copy arrives with no remote-tracking refs at all.** Verified in a
Product Manager run on 2026-10-05, before touching anything: `git branch -a`
listed only `* main`; `git config --get branch.main.remote` was empty; and
`git fetch origin` reported *every* remote ref, including `origin/main`, as
`[new branch]`. The consequence is that the rule we already had —
`skills/pull-requests/SKILL.md:63`, "`git switch -c <branch>
origin/<default-branch>`" — **fails outright** at the start of a run, so an
agent that skips the fetch branches from the stale local `main` instead, and
`git status -sb` prints a bare `## main` with no ahead/behind to warn it.

That reframes the problem. This was not six agents ignoring a written rule. The
rule was unrunnable as written, and the staleness it guards against was
invisible from inside the run.

## Decision

**A run's working copy is disposable, and an agent proves that before it
works.** Two parts, in sequence.

1. **A preflight guard, in this repo, first**
   ([#17](https://github.com/dpeckham/my-ai-org/issues/17)). Fetch `origin`,
   resolve the default branch from the remote, and **fail loudly** — naming the
   offending paths or commits — on a dirty tree or on a default branch carrying
   commits `origin` does not have. One script, made mandatory in the
   instructions that currently carry it as prose.
2. **Per-issue worktrees, second**
   ([#19](https://github.com/dpeckham/my-ai-org/issues/19)). Set the project's
   `executionWorkspacePolicy` with `workspaceStrategy.type: "git_worktree"` in
   `scripts/newproject.sh`, and reconcile the projects that already exist with
   `PATCH /api/projects/{id}`. This removes the shared mutable directory rather
   than teaching agents to live with it.

**Part 1 goes first and is not merely a stopgap.** It lives entirely in this
repo, so it lands without depending on platform behaviour we have not
exercised; and after part 2 it is still the check that a worktree really is
clean and really is based on `origin/<default>`. Part 2 is the one that fixes
the cause.

**Clearing the two damaged checkouts is DevOps' or the operator's, not a
project team's** ([#20](https://github.com/dpeckham/my-ai-org/issues/20)). The
directories are `$PC_HOME/code/<org>/<repo>` inside the `paperclip` container;
a project role agent runs on its own box against a staged copy and cannot reach
them (verified 2026-10-05: `/home/paperclip/code` does not exist from inside a
project run). It is filed as a runbook with preserve-before-reset steps, not as
pipeline work, because it is a one-off hand operation whose failure mode is
losing unpushed agent commits.

## Options considered

- **The preflight guard alone.** Cheap, and it stops the observed damage.
  Rejected as the whole answer: two agents can still be told, as one was on
  2026-10-05, that their "shared workspace is concurrently held by run
  `bf40be51…`". A guard makes collision visible; it does not remove it.
- **The worktree change alone.** Fixes the cause and skips the interim work.
  Rejected as the whole answer because it depends on Paperclip's `git_worktree`
  strategy behaving as documented on this box, which nothing has yet
  exercised — and because a worktree does not by itself guarantee a clean tree
  at a known base, which is what the acceptance criteria need to assert.
- **Leaving the shared copy on `main` and telling agents to clean up after
  themselves.** Rejected: the state crosses runs and agents, so whoever fails
  to clean up penalises the next agent rather than itself. That is already
  exactly what happened.
- **Fixing only the two checkouts by hand.** Rejected as a fix; kept as
  necessary damage-clearing, since the mechanism's fix does not undo its
  effects.
- **Doing part 1 platform-side** via
  `executionWorkspacePolicy.workspaceStrategy.runtimeProvisionCommand`. Likely
  the better long-term home, and deliberately folded into part 2 rather than
  blocking part 1 on it.

## Consequences

- **The first pipeline run this repo dogfooded has paid for itself.** Three
  pull-request defects had a single upstream cause that no amount of reading the
  installer would have surfaced; it took running the pipeline against this repo
  to see it. That is the argument of
  [0002](0002-dogfood-the-pipeline-on-this-repo.md), now with evidence.
- **Both of this repo's open pull requests are cut from a stale base**
  ([#4](https://github.com/dpeckham/my-ai-org/pull/4),
  [#12](https://github.com/dpeckham/my-ai-org/pull/12)), and
  [#12](https://github.com/dpeckham/my-ai-org/pull/12) contains
  [#4](https://github.com/dpeckham/my-ai-org/pull/4) in full. Reviewers and the
  operator need telling before they merge, because GitHub reports both
  `MERGEABLE/CLEAN` and nothing flags a semantically stale base.
- **A standing risk until part 1 merges:** a `git push` on `main` from either
  managed checkout would put unreviewed agent commits straight onto
  `origin/main`, and neither repo has branch protection. That raises the
  priority of
  [#11](https://github.com/dpeckham/my-ai-org/issues/11) (a project's repos get
  none of the GitHub security settings the README describes), which is the issue
  that would have made this merely a nuisance.
- **`executionWorkspacePolicy: null` is a fleet-wide condition**, not this
  project's: all four projects on this Paperclip report it. So part 2 has to
  reconcile existing projects, not only configure new ones — which is
  `CLAUDE.md`'s "re-running must upgrade, not just skip" applied to a project
  record rather than a file.
- **Reversibility.** Part 1 is a script and two instruction edits: trivially
  reversible. Part 2 changes a project record, reversible by `PATCH`-ing the
  policy back to null; the risk is not reversibility but a teardown that deletes
  a worktree whose branch was never pushed, which is why
  [#19](https://github.com/dpeckham/my-ai-org/issues/19) defaults teardown to
  off.
