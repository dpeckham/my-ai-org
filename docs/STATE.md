# State

Current status. Newest entry first. Keep it short: what is done, what is in
flight, what is blocked, what is next. Goals and milestones live in
[ROADMAP.md](ROADMAP.md).

## 2026-10-04

### Done

- **The whole system exists end to end.** `./install.sh` takes a bare
  Debian/Ubuntu, Arch or Fedora machine to a running org in ten phases:
  prereqs, sign-ins, host, base image, Paperclip, org, GitHub bot, projects,
  skills, existing boxes. Re-running reconciles rather than skipping.
- **The trust boundary.** Project boxes live in a restricted `agents` Incus
  project; Paperclip holds a certificate scoped to it, verified to refuse
  exec into the default project, privileged containers, host-path disks and
  server config changes. Fleet capped at 20GiB by default.
- **A team per project.** Product Manager, Lead Engineer, UI Designer, Coder,
  QA Lead and Security, created by `scripts/newproject.sh`, with instructions
  from `templates/` that re-runs upgrade while they are unedited.
- **Two GitHub identities.** The Coder authors as the operator; every
  reviewing role acts as one GitHub App, so reviews count and are
  distinguishable. Tokens are scoped to one repo per call (`scripts/gh-bot`).
- **Skills as a library.** `skills/sources.manifest` maps seven skills to
  roles; `scripts/skills-sync.sh` imports and attaches them. Third-party
  skills are pinned by commit or copied with attribution.
- **Work that starts on GitHub reaches the team.** `scripts/github-bridge.mjs`
  polls each project's repos on a per-project interval and turns new issues,
  outside pull requests, human comments, failed CI on the default branch and
  Dependabot alerts into Paperclip work. No AI, no inbound network access.
- **A decision record of where this is going:**
  [#1](https://github.com/dpeckham/my-ai-org/issues/1), closed as completed —
  Paperclip as control plane, git as durable memory, one container per project.

### Decided

By the operator, 2026-10-04:

- **The first pipeline run is dogfooded on this repo**, and **M1 comes before
  M2** — prove the pipeline before putting CI on the installer. Recorded in
  [decisions/0002](decisions/0002-dogfood-the-pipeline-on-this-repo.md).

Settled by observation rather than by asking:

- **`budgetMonthlyCents: 0` is not an enforced ceiling.** Every agent in this
  company carries `0`, including ones that run daily, and none is paused. What
  ceiling a project *should* get is still open (question 2 below).

### In flight

- **This document and [ROADMAP.md](ROADMAP.md)** — the Product Manager
  kickoff, on branch `pm/roadmap-and-state`, in a pull request awaiting the
  operator's merge.
- **M1, first feature: the `agent` / `ui` labels**
  ([#6](https://github.com/dpeckham/my-ai-org/issues/6)) — with the Lead
  Engineer for spec review, tracked on Paperclip as DAV-17. This is the
  change the first end-to-end pipeline run carries.
- **M1, second feature: skills on project creation**
  ([#5](https://github.com/dpeckham/my-ai-org/issues/5)) — queued behind the
  first, tracked on Paperclip as DAV-18. Both edit
  `scripts/newproject.sh`, so they go one at a time.

### Workarounds in place

- **The `agent` and `ui` labels now exist in this repo**, created by hand as
  the bot on 2026-10-04 so the first pipeline run is not blocked by
  [#6](https://github.com/dpeckham/my-ai-org/issues/6). No other repo has
  them, and nothing creates them; the fix is still owed.

### Blocked

- **macOS support ([#3](https://github.com/dpeckham/my-ai-org/issues/3))** —
  designed in detail against `apple/container` 1.5.0 but never run. Blocked on
  access to a Mac with macOS 26 on Apple silicon to settle six unknowns,
  chiefly whether a container can run systemd as a long-lived box and how
  Paperclip provisions without a remote API. Step 1 (the backend verb layer)
  is a Linux-only refactor and is not blocked.
- **Fleet upkeep ([#2](https://github.com/dpeckham/my-ai-org/issues/2))** —
  one line of intent ("a DevOps agent should keep every project container
  current with org practice: skills, hooks, tools"), not yet specified enough
  to build. Needs the operator and the Product Manager to agree what "current"
  means and how drift is detected. See M5.

### Next

In the order the roadmap argues for:

1. **Prove the pipeline once** (M1), dogfooded on this repo. The two confirmed
   defects are the subject of that first run, not a prerequisite to it:
   [#6](https://github.com/dpeckham/my-ai-org/issues/6) (nothing creates the
   `agent` / `ui` labels) first, then
   [#5](https://github.com/dpeckham/my-ai-org/issues/5) (new teams get no
   skills). Both are written up under **Known defects** in the roadmap.
2. **CI for the installer** (M2): shellcheck plus the dry-run and preflight
   paths, before agents become the main authors of ~5,000 lines of shell with
   no automated checking.
3. **Confirm the operator is actually told things** (M3): stalled work, failed
   runs and budget burn.

### Open questions for the operator

Two earlier questions are answered and have moved to **Decided** above: the
dogfood target, and whether the pipeline or installer CI comes first. A third,
what `budgetMonthlyCents: 0` means, was settled by observation. What is left:

1. **Default trust posture.** Every box is seeded with live Claude, codex and
   `gh` credentials usable by anything with a shell on it, and the egress
   allowlist is opt-in (`--egress agent`). That is right for a box the
   operator drives and questionable for an unattended agent. Should either
   default flip?
2. **Budgets.** `0` is not an enforced ceiling (see **Decided**), so the
   remaining question is a product one: what monthly ceiling should a new
   project get by default, and what should happen when it is reached — pause
   the team, or raise it to the operator and keep going?
3. **Audience, and when.** Is "anyone else can install this" a near-term goal?
   If so M2 and M4 move up; if this is the operator's own machine first, M1
   and M3 matter more.
4. **Scope of [#2](https://github.com/dpeckham/my-ai-org/issues/2).** Is it
   "re-run the current sync against existing boxes", or a standing reconcile
   loop that detects drift on its own?
