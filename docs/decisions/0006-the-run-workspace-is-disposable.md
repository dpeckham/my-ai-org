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

**We observe platform behaviour once before a script commits to it.** Part 2
rests on Paperclip's `git_worktree` strategy, and five of the values it has to
choose — the base ref and its spelling, `branchTemplate`'s placeholder
vocabulary, where the worktree lands, whether anything cleans it up, and whether
a staged copy of a worktree is still a working repository — carry no description
anywhere in Paperclip's OpenAPI document. Rather than let `newproject.sh` encode
guesses that would fail silently in some future run, we spent one reversible
experiment first: record the current policy, apply the candidate to a single
low-traffic project, take one run under it, write down what happened, roll back,
verify the rollback ([#22](https://github.com/dpeckham/my-ai-org/issues/22)).
The answers then went into the issue body, so the handoff to the implementer
states facts rather than defaults. This is now the pattern for any change where
a script must commit to undocumented platform behaviour: one scoped,
rolled-back observation, with its answers carried into the issue that needs
them — not a plausible default shipped into a provisioning script, because a
provisioning script's wrong guess is discovered by whoever is unlucky rather
than by whoever wrote it. The cost was one spike; it paid for itself immediately
by finding that part 2 cannot work at all yet (see Consequences) and by catching
two silent failure modes — a bare branch name quietly resolving to a different
commit, and an unrecognised `branchTemplate` placeholder collapsing every issue
in a project onto one branch.

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
- **Part 2 is gated behind a setting no agent here can reach**, found by that
  observation on 2026-10-05. Paperclip discards a project's
  `executionWorkspacePolicy` unless the instance-level experimental setting
  `enableIsolatedWorkspaces` is on, and it is off by default; a second, narrower
  flag `enableWorktreeRunExecution` may also be required. An agent key cannot
  even read them (`{"error":"Board access required"}`). So part 2 lands as
  provisioning that is inert until an operator enables the flag — correct to
  land, because the policy must exist before the flag can act on it, and
  deliberately written to change no behaviour while the flag is off. The choice
  between enabling it and accepting the shared workspace permanently is with the
  Chief of Staff. Until that is decided, **part 1 is the only protection in
  force**, which raises its priority rather than lowering it.
- **The shared checkout's `main` is hard-reset to `origin/main` at staging.**
  Also found by that observation (its reflog shows `reset: moving to
  origin/main`), and it is the mechanism behind the diverged-workspace symptom
  this decision started from: unpushed commits sitting in the shared checkout
  are dropped under whoever is holding it. During the spike that discarded four
  commits; none were lost, because all four exist on `origin` as
  `rescue/my-ai-org-2026-10-05` and `rescue/my-ai-org-2026-10-05-worktree`. It
  is also the sharpest argument for part 2: a per-issue worktree is not reset
  under a running agent.
