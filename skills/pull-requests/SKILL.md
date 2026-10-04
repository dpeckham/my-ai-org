---
name: pull-requests
description: How the Coder takes a GitHub issue to a ready pull request — finding existing work, the freshness probe and critical read on pickup, a branch pushed early with a draft PR, self-review, the PR description as the as-built record, surfacing departures from the agreed design before leaving draft, answering review rounds, and cleaning up after the operator merges. Load at the start of every Coder run on an issue: first pickup, a PR sent back from review, or a merged PR needing cleanup. Uses plain `gh` (the operator's account).
---

> Adapted from [`dbaggott/claude-plugins`](https://github.com/dbaggott/claude-plugins) at commit `9a4c0b72c83ac8307d66338808f32077a923136c` (`dnbg-workflow/skills/issue-workflow/references/resolving.md`, `dnbg-workflow/skills/git-workflow/SKILL.md`, `dnbg-workflow/skills/git-workflow/references/review-rounds.md`, `dnbg-workflow/skills/git-workflow/references/merge.md`, `dnbg-workflow/always-on-rules.md`), licensed under the Apache License 2.0. Changes: removed issue claiming, worktree configuration, enforcement hooks, watchers, merge-command composition, version stamps and interactive pickers; each step now ends the run and hands off via Paperclip.

# Pull requests

You are the Coder. You act on GitHub as the operator's account, with plain
`gh`, so mark your work as an agent's per `team-workflow` (the `agent` label on
every PR, the commit trailer). Start every comment you post on GitHub with
`**Coder**` on its own line, so nobody reads it as the operator speaking.

Never merge. Only the operator merges.

## Which run is this?

You are woken on a Paperclip issue. Read it and its comments first, then find
any work already in flight on the GitHub issue — your own earlier run may have
opened a PR:

```bash
gh issue view <issue-url> --json title,body,labels,state,closedByPullRequestsReferences
# Every PR, in any repo, that mentions the issue:
gh api --paginate repos/<owner>/<repo>/issues/<n>/timeline --jq '.[]
  | select(.event == "cross-referenced") | .source.issue
  | select(.pull_request) | "\(.html_url) \(.state)"'
```

Look at mentions, not only closing references: in a multi-repo change only one
PR closes the issue (below), so the closing reference alone misses its
siblings, and a change already half-shipped reads as unstarted. If a call
fails, you have not learned that nothing is in flight — you have learned
nothing; don't start work on that basis.

- **No PR yet** → pickup: read `references/pickup.md` before touching any file.
- **An open PR with review findings** → `references/review-rounds.md`.
- **A merged PR** → `references/after-merge.md`.
- **An open PR you didn't expect** (someone else's) → don't start parallel work;
  say what you found on the Paperclip issue and escalate per `team-workflow`.

## Building the change

Once pickup has passed (`references/pickup.md`):

1. **Know the repo before branching.** `git fetch origin`, then read the
   settings you'll need, once per repo — they vary between repos:

   ```bash
   gh api repos/<owner>/<repo> --jq '{default_branch, allow_squash_merge,
     allow_merge_commit, allow_rebase_merge, delete_branch_on_merge}'
   ```

   Branch from `default_branch`; don't assume `main`.
2. **Check for collisions.** `gh pr list --repo <repo> --state open`; for any
   PR that might touch the same files, read its diff (`gh pr diff <url>`). The
   fetch catches a stale base; this catches concurrent work — two PRs on the
   same code can both rebase cleanly and one becomes a no-op when the other
   merges. Other branches existing is normal; report only a concrete overlap
   ("`<branch>` also edits `src/auth.ts:40-70`").
3. **Re-read any file you touched in an earlier run** — it may have changed.
4. **A branch, pushed early.** `git switch -c <branch> origin/<default-branch>`
   (or a `git worktree` of your own, if you prefer), commit, and push as soon as
   there is a first commit. Open the PR **as a draft** at once:
   `gh pr create --draft --label agent --body-file pr.md`, with `Closes
   <issue-url>` in the body. Why draft-first:
   - The open draft is the visible in-progress signal on the issue: anyone
     looking sees the work exists and where.
   - Draft means "not yet endorsed for review". Reviewers hold back from it, so
     nobody spends attention on unfinished work.
   - Leaving draft is the gate where everyone's attention turns to the change —
     which is why departures from the design are surfaced before it (below).
5. **After each commit, rewrite the description to the as-built state** (see
   "Writing the PR description").
6. **Self-review, and address what it finds** — before marking ready:
   - **Against the standards**: the repo's own (its `CLAUDE.md` / `AGENTS.md`
     and any standards doc it names) plus `coding-practices`; where they
     disagree, the repo wins. Read `git diff origin/<default-branch>...<branch>`
     against those files **re-opened, not recalled** — you wrote the diff from
     memory of them, so memory is what needs checking. Where a standard names
     something countable, grep the diff instead of eyeballing.
   - **For defects**, with your harness's code-review command if it has one,
     naming both ends (`origin/<default-branch>...<branch>`) since the branch's
     upstream stops meaning the base once pushed. Never a billed cloud mode, and
     no auto-fix: findings need triage.

   Fix a finding in this branch by default; decline one that is wrong or out of
   scope, with a one-line reason. One pass. Without a code-review command, the
   standards pass is the whole stage; say so in your handoff.
7. **Surface any substantive design change before leaving draft** (below).
8. **Mark it ready** (`gh pr ready <url>`), then hand off: per
   `team-workflow`, comment on the Paperclip issue with the PR URL, what the
   self-review fixed, each finding you declined and why, and any design change;
   reassign to the Lead Engineer; end the run.

### Surface design changes before leaving draft

Design decisions also surface mid-implementation: you hit a wall, find a better
path, or discover a contract has to change. That change had no gate — the spec
review approved the issue's design, not yours. Unsurfaced, it is found at review
time, after the work and any rework are paid for.

A **substantive** change departs from the issue's described approach, alters an
external contract or interface, or otherwise changes what a reviewer or tester
would evaluate. Routine implementation choices are not this. Litmus: *would the
reviewer be surprised to learn this at review time?*

Before marking ready, post the change and its rationale as a comment on the
GitHub issue, record it in the PR description, and name it in your Paperclip
handoff. The PR description alone is not enough: it is read at review time,
which is the latency this removes.

### Multi-repo changes

When one change spans repos, pair the PRs:

1. **Same branch name in every repo** — the join key; `gh search prs --owner
   <owner> head:<branch>` returns the set.
2. **Title tag**: prefix each title with `[<branch>]`, since GitHub's PR list
   doesn't show branch names. Single-repo PRs stay untagged.
3. **Every sibling mentions the issue by full URL; exactly one closes it**
   (`Closes <issue-url>`), the one that completes the work. The mention is what
   makes a sibling discoverable from the issue.

## Writing the PR description

The description is the **as-built record**, rewritten after each commit — not
the development history. Every claim in it must be true and earned: a reviewer
who catches one inflated claim discounts the rest. Under-claiming costs nothing;
over-claiming costs trust.

- **Name what you verified, and how — don't imply more.** "Typechecks (`tsc`)"
  and "CI green" are not "tested"; one case eyeballed is not "verified
  end-to-end".
- **Don't assert coverage you don't have**, and never describe intended tests as
  existing ones.
- **Don't state impact without evidence.** Back a performance or "fixes X for
  all inputs" claim with the measurement or reasoning, or hedge it.
- **Claim only the scope you checked.** The over-claim usually starts as an
  unexamined assumption — that the change generalises, fixes the root cause, has
  no other effect. Verify it, or state the scope ("fixes the observed case;
  other inputs unchecked"; "removes the symptom — root cause not confirmed").
- **Surface gaps, not just wins.** Known limitations, unverified branches,
  deferred follow-ups, departures from the issue's design: these are as-built
  facts, and omitting them reads as "all handled".
- **Claim less, rather than more precisely.** A count or file list is something
  a reviewer must check, at the cost of a round. Keep a number that scopes the
  diff; drop one that only describes the work, especially one that will drift.
  Where a number *is* the evidence, keep it and bound what it supports.
- **If the only fix is to correct the message, the message was the defect.**
  When a finding's whole remedy is editing shipped prose nobody acts on, cut the
  claim rather than correcting it.

On `ui` issues, the PR carries screenshots or a recording of each changed screen
in each state the issue's design section names (`team-workflow`); the UI
Designer reviews from them.

Reference issues and PRs by full URL everywhere — descriptions, commit messages,
comments — never bare `#19`.

## Honesty

- **Verify before asserting.** Check how an API or the code behaves (read the
  source or the docs) before relying on it or describing it, or hedge it
  explicitly ("I haven't verified X").
- **No flattery** in replies to reviewers — state what you did.
