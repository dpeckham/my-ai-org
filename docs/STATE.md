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

### In flight

- **This document and [ROADMAP.md](ROADMAP.md)** — the Product Manager
  kickoff, on branch `pm/roadmap-and-state`.

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

1. **Prove the pipeline once** (M1), dogfooded on this repo, after fixing the
   two confirmed defects that will break it: new teams get no skills, and the
   `agent` / `ui` labels exist in no repo. Both are written up under **Known
   defects** in the roadmap.
2. **CI for the installer** (M2): shellcheck plus the dry-run and preflight
   paths, before agents become the main authors of ~5,000 lines of shell with
   no automated checking.
3. **Confirm the operator is actually told things** (M3): stalled work, failed
   runs and budget burn.

### Open questions for the operator

1. **Dogfood target.** Should the first full pipeline run be a feature on this
   repo, or somewhere lower-stakes? This repo is the honest test, but a
   pipeline bug here breaks the installer.
2. **Default trust posture.** Every box is seeded with live Claude, codex and
   `gh` credentials usable by anything with a shell on it, and the egress
   allowlist is opt-in (`--egress agent`). That is right for a box the
   operator drives and questionable for an unattended agent. Should either
   default flip?
3. **Budgets.** `scripts/newproject.sh` creates the five non-Product-Manager
   agents with `budgetMonthlyCents: 0` and the Product Manager with a budget
   only when `--budget` is given. Is 0 "no limit" in Paperclip, and what
   per-project monthly ceiling should a new project get by default?
4. **Audience, and when.** Is "anyone else can install this" a near-term goal?
   If so M2 and M4 move up; if this is the operator's own machine first, M1
   and M3 matter more.
5. **Scope of [#2](https://github.com/dpeckham/my-ai-org/issues/2).** Is it
   "re-run the current sync against existing boxes", or a standing reconcile
   loop that detects drift on its own?
