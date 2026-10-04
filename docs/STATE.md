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
- **A brief on running without Paperclip**
  ([briefs/github-native-edition.md](briefs/github-native-edition.md)) — asked
  for by the operator for clients with nowhere to host the control plane.
  Finding: the pipeline, roles, skills and bot are already GitHub-native, and
  Paperclip supplies only a seven-verb coordination layer, so the route is to
  extract that port and write a second adapter rather than build a second
  product. GitHub's notification inbox turns out to need a classic PAT; an
  App's own webhook delivery log is the better event source. **Answered and
  promoted** to
  [decisions/0004](decisions/0004-github-native-is-the-single-project-edition.md);
  the brief is kept as the research behind that record, not as live direction.
- **A decision record of where this is going:**
  [#1](https://github.com/dpeckham/my-ai-org/issues/1), closed as completed —
  Paperclip as control plane, git as durable memory, one container per project.

### Decided

By the operator, 2026-10-04:

- **The first pipeline run is dogfooded on this repo**, and **M1 comes before
  M2** — prove the pipeline before putting CI on the installer. Recorded in
  [decisions/0002](decisions/0002-dogfood-the-pipeline-on-this-repo.md).
- **Clients are a real, near-term goal** — there is one client in view, so plan
  for it. Which settles the long-open "audience, and when" question: not the
  operator's own machine first. M4 pulls forward, and macOS
  ([#3](https://github.com/dpeckham/my-ai-org/issues/3)) becomes load-bearing
  rather than optional, since a Mac-only client has no LXC.
- **GitHub-native ships as the single-project edition of the same product**,
  reached by extracting the seven-verb control-plane port and writing a second
  adapter behind it — not as a fork. Event source: the App's own webhook
  delivery log, with per-repo polling as the fallback; the notification inbox is
  rejected because it accepts only a classic PAT. Recorded in
  [decisions/0004](decisions/0004-github-native-is-the-single-project-edition.md),
  now M6 in the roadmap.
- **Coordination state lives in the GitHub thread**, not in a file in the box —
  one bot comment per issue, edited in place, carrying the cursor, the holder
  and the run log ("take the portability"). The box becomes disposable and a
  run can resume on any machine. Recorded in
  [decisions/0005](decisions/0005-coordination-state-lives-in-the-github-thread.md).
  Its largest consequence is not portability but that it **demotes the macOS
  backend from a product decision to a per-install config** behind the verb
  layer: if nothing durable lives in the box, nothing in the pipeline depends
  on what the box is.
- **Still open, by omission:** whether M1 comes before that work. The brief's
  recommendation (yes) stands as the default and is cheapest to reverse before
  the port is extracted.

Settled by observation rather than by asking:

- **`budgetMonthlyCents: 0` is not an enforced ceiling.** Every agent in this
  company carries `0`, including ones that run daily, and none is paused. What
  ceiling a project *should* get is still open (question 2 below).

### In flight

- **A second brief, on the runtime itself**
  ([briefs/agent-runtime.md](briefs/agent-runtime.md)) — the operator's framing
  of Paperclip as triggers plus portable Claude/Codex invocations, made exact,
  and what it looks like on macOS and Linux. Four additive refinements to
  [0004](decisions/0004-github-native-is-the-single-project-edition.md) (the
  wake payload is the unnamed half of the port; coordination state lives in the
  GitHub thread, not the box; the dispatcher sits on the host and mints a
  one-hour token per run; role context resolves only at the default branch) and
  three roadmap consequences ([#3](https://github.com/dpeckham/my-ai-org/issues/3)
  step 1 is on M6's critical path, #3's broker drops out of this edition, and
  macOS needs an answer for Macs that cannot run Apple's runtime). **Its
  central question is now answered and promoted to
  [0005](decisions/0005-coordination-state-lives-in-the-github-thread.md);**
  §10-§14, written after that answer, specify the state comment, the dispatcher
  loop, what each platform's install actually contains, and the standing
  defaults for the two questions the operator left open. On branch
  `pm/github-native-edition-brief` in
  [PR #12](https://github.com/dpeckham/my-ai-org/pull/12), awaiting the
  operator's merge.
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
- **A licence for this repository**
  ([#8](https://github.com/dpeckham/my-ai-org/issues/8)) — the operator chose
  MIT, copyright holder Dave Peckham; see
  [0003](decisions/0003-mit-licence-for-this-repo.md). With the Lead Engineer
  for spec review, tracked on Paperclip as DAV-15. Until it merges the repo is
  public with no licence, so nobody who finds it may legally use it.

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
4. **Get ready for a client** (M4, and M6 behind it): a cold install on a
   machine that is not this one, and the control-plane port. New as of the
   audience answer above; it does not displace 1, and it does raise the
   priority of the blocked macOS work, which needs hardware the operator has
   to find.

### Open questions for the operator

Three earlier questions are answered and have moved to **Decided** above: the
dogfood target, whether the pipeline or installer CI comes first, and audience
(clients, near-term). A fourth, what `budgetMonthlyCents: 0` means, was settled
by observation. What is left:

1. **Default trust posture.** Every box is seeded with live Claude, codex and
   `gh` credentials usable by anything with a shell on it, and the egress
   allowlist is opt-in (`--egress agent`). That is right for a box the
   operator drives and questionable for an unattended agent. Should either
   default flip?
2. **Budgets.** `0` is not an enforced ceiling (see **Decided**), so the
   remaining question is a product one: what monthly ceiling should a new
   project get by default, and what should happen when it is reached — pause
   the team, or raise it to the operator and keep going?
3. **Does M1 still come first?** Now that clients are real and near-term, M6
   (the GitHub-native edition) competes with proving the pipeline. The
   recommendation is M1 first; see **Decided** above. Answering "no" is the one
   thing that would re-order **Next** above.
4. **Scope of [#2](https://github.com/dpeckham/my-ai-org/issues/2).** Is it
   "re-run the current sync against existing boxes", or a standing reconcile
   loop that detects drift on its own?
Two more were answered or defaulted on 2026-10-04. Coordination state in the
thread is **decided** and has moved to **Decided** above. The two macOS
questions were left unanswered and now run on standing defaults, which hold
until the operator moves them and are cheap to reverse while the verb layer is
the only thing written
([briefs/agent-runtime.md](briefs/agent-runtime.md) §14):

5. **macOS: Apple's runtime, or a Linux VM? — default: both, Linux VM first.**
   [0005](decisions/0005-coordination-state-lives-in-the-github-thread.md)
   turned this from a product fork into a per-install config behind the verb
   layer, so the only live content is ordering. The Linux VM (tier 2) is the
   one that needs no Apple silicon, so it goes first and the Mac story becomes
   "works today"; Apple's runtime stays the intended destination.
6. **Do we ship a no-container tier with a warning? — default: document the
   risk, do not ship the backend.** Note for whoever revisits it: tier 0 is the
   *null* implementation of the verb layer (`box_create` is `mkdir`,
   `box_exec` is a subshell), so this is purely a question of whether we
   endorse it, not of engineering cost.
