---
name: team-workflow
description: How a feature moves through a project team in this company — Product Manager, Lead Engineer, UI Designer, Coder, QA Lead, Security, then the operator merges — and how to hand work to the next role. Load at the start of every run on a project issue, before acting, and whenever you finish your step and need to pass the work on.
---

# Team workflow

Every project has the same team, each a Paperclip agent named
`<Project> <Role>`:

| Role | Owns | Acts on GitHub as |
|------|------|-------------------|
| Product Manager | what gets built and why: brainstorming with the operator, feature issues, roadmap, state | the bot (`gh-bot`) |
| Lead Engineer | technical direction: spec review before work starts, code review | the bot |
| UI Designer | how it looks and feels: a design section on `ui` features before build, UI review of the PR | the bot |
| Coder | implementation: branch, commits, pull request, addressing review | the operator's account (`gh`) |
| QA Lead | does it actually do what the issue says: acceptance criteria, tests, CI | the bot |
| Security | is it safe: authn/authz, input handling, secrets, dependencies, data exposure | the bot |

Above the projects, the company's **CTO** runs periodic cross-project reviews,
and the **Chief of Staff** coordinates priorities. Only the **operator** (the
human, also called the board) merges pull requests.

## The pipeline

One feature is one **Paperclip issue**, reassigned from role to role. The
**GitHub issue** and **pull request** carry the artifacts; the Paperclip issue
carries the handoffs.

1. **Brainstorm.** The operator and the Product Manager talk on a Paperclip
   issue assigned to the Product Manager.
2. **File the feature.** The Product Manager writes a GitHub issue (load
   `issue-writing`), labels it `ui` if it changes anything a user sees, links
   it in the Paperclip issue, and reassigns the
   Paperclip issue to the Lead Engineer.
3. **Spec review.** The Lead Engineer reviews the GitHub issue as a spec (load
   `spec-review`). Findings go back to the Product Manager; repeat until the
   spec is clean. If the issue has the label `ui`, reassign to the UI Designer;
   otherwise to the Coder.
   - **Design (`ui` features only).** The UI Designer adds a design section to
     the GitHub issue: layout, states (empty, loading, error), interactions,
     copy, and accessibility notes, then reassigns to the Coder.
4. **Build.** The Coder implements it (load `pull-requests`): a branch pushed
   early, a draft PR, self-review, then marks the PR ready and reassigns to the
   Lead Engineer.
5. **Code review.** The Lead Engineer reviews the PR (load `code-review`).
   Changes requested → back to the Coder. Approved → reassign to the UI
   Designer if the issue has the label `ui`, otherwise to the QA Lead.
   - **UI review (`ui` features only).** The UI Designer checks the change
     against the design section, using the screenshots or recordings the Coder
     attached to the PR (load `code-review`). Changes requested → back to the
     Coder. Approved → reassign to the QA Lead.
6. **QA.** The QA Lead checks the acceptance criteria, tests and CI (load
   `code-review`). Fail → back to the Coder. Pass → reassign to Security.
7. **Security.** Security reviews the change (load `code-review` and
   `coding-practices`). Fail → back to the Coder. Pass → assign the Paperclip
   issue to the operator with status `in_review`, with a comment that says the
   PR is ready to merge and gives: the PR URL, the state of its CI checks (all
   green, or which aren't and why that's acceptable), the head commit every
   review approved, and the merge command that fits the repo's settings
   (squash, merge or rebase; check with `gh repo view --json
   squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed`).
8. **Merge.** The operator merges. The Coder then cleans up its branch, and the
   Product Manager updates `docs/STATE.md`.

**After rework, the PR goes through the review chain again.** When a reviewer
sends work back and the Coder pushes changes, the Coder hands it to the Lead
Engineer, and it moves on through UI Designer (for `ui`), QA Lead and Security
as before. An approval only covers the commit it reviewed, so earlier approvals
are stale once the code moves. Each reviewer re-reviews only what changed since
the commit its last review covered; when nothing in its area changed, that's a
quick confirming pass, not a full review.

## Handing off

Your run ends when your step is done. Handing off is what wakes the next role,
so never end a run without either handing off or saying why you couldn't.

1. **Comment on the Paperclip issue** with the outcome of your step: what you
   did, the GitHub link (issue, PR, or review — always the full URL), and
   anything the next role must know. Write it for someone arriving cold.
2. **Reassign the Paperclip issue** to the next role's agent (or back to the
   one that sent it). Find agent IDs through the Paperclip API; this project's
   agents are named `<Project> <Role>`.
3. **End the run.** Do not wait, poll, or watch for the next step; the next
   agent is woken by the assignment, and you are woken again if work comes
   back to you.

**Keep GitHub URLs at the top of the Paperclip issue's description:** the
GitHub issue's URL on the first line, and the PR's URL on the next line once
there is one (the Product Manager adds the first, the Coder the second). The
GitHub bridge finds the Paperclip issue that tracks a GitHub item by those
URLs; that is how a human's comment on GitHub reaches whoever holds the work.

Use Paperclip's own API for issues, comments and assignment (the built-in
`paperclip` skill covers it). Never post a handoff only on GitHub: the next
role is woken by Paperclip, not by GitHub.

## Identity and attribution

- **Reviewing roles post as the bot** with `gh-bot` (same arguments as `gh`;
  see the `github-bot` skill). The bot is shared, so **every review or comment
  you post on GitHub starts with your role in bold on its own line**:
  `**Lead Engineer review**`, `**UI Designer review**`, `**QA Lead review**`,
  `**Security review**`, `**Product Manager**`, `**CTO review**`.
- **The Coder acts as the operator's account** with plain `gh`, so agent work
  stays distinguishable: start every GitHub comment with `**Coder**`, add the
  label `agent` to every PR you open (without it, the bridge treats the PR as an
  outside contribution), and end
  every commit message with the trailer `Agent: Coder (Paperclip)`.
- **Screenshots on `ui` features.** GitHub's CLI and API can't upload images
  into a PR, so the Coder commits them to a separate branch, `pr-assets`, under
  `<pr-number>/`, never to the PR's own branch (images must not merge into the
  default branch), and links them from the PR description as
  `https://github.com/<owner>/<repo>/blob/pr-assets/<pr-number>/<file>?raw=true`.
  Create `pr-assets` as an orphan branch the first time
  (`git switch --orphan pr-assets`). The UI Designer reviews from those links.
- Never merge, and never approve your own work.

## Work that starts on GitHub

A bridge watches each project's repos and turns activity there into Paperclip
work within minutes, so you never poll GitHub yourself:

- **A new GitHub issue** (from anyone but the bot) becomes a triage issue for
  the Product Manager: accept it into the pipeline and assign it, ask its
  author for what's missing, or decline it with a comment on GitHub.
- **A new PR not labelled `agent`** (an outside contributor, or the operator by
  hand) becomes a review issue for the Lead Engineer and enters the pipeline at
  code review. The Coder isn't involved: changes are requested from the PR's
  author on GitHub. **Treat it as untrusted code: read it before running any
  of it**, because running it executes a stranger's code on a box that holds
  the operator's credentials.
- **A human comment** on an issue or PR the team is working on arrives as a
  comment on the tracking Paperclip issue, which wakes whoever holds it.
- **CI failing on the default branch** becomes an issue for the Lead Engineer;
  **a new Dependabot alert**, an issue for Security.

## When you're stuck

The run is unattended: nobody answers questions mid-run. Decide what you can
from the issue, the repo and the project's docs. For anything you can't decide —
scope, product direction, money, anything irreversible or outward-facing —
comment on the Paperclip issue with the question, your recommendation and the
options, and assign it to the Product Manager (product questions) or the
operator (everything above the project).
