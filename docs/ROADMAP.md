# Roadmap

What this project is for, what we are building next, and what we are
deliberately not building. Dated entries and current status live in
[STATE.md](STATE.md); significant product decisions live in
[decisions/](decisions/).

## The product

`my-ai-org` installs a complete AI-agent organisation on one Linux machine,
for an operator with more projects than they can keep track of. One command
turns a bare machine into: Paperclip as the control plane, one container per
project, and a team of agents per project that works in the background and
surfaces only what needs a human.

The promises we are keeping, in priority order:

1. **Work happens while the operator is elsewhere.** Agents pick up issues,
   open pull requests, and review each other without being driven.
2. **What needs a human reaches the human.** Stalled work, failed runs,
   decisions above an agent's pay grade and budget burn are raised, not
   discovered.
3. **`git pull && ./install.sh` is always safe.** Every phase reconciles
   rather than skipping, so upgrading is one command on any existing install.
4. **The blast radius is bounded.** A runaway agent can wreck project boxes
   and nothing else: not the host, not Paperclip, not another project.
5. **Git is the durable memory.** Roadmaps, state and decisions live in repos,
   so the project survives losing Paperclip.

Success, stated plainly: an operator installs this, adds their repos, and a
week later finds merged pull requests they did not have to shepherd, and a
short list of things only they could decide.

There are now **two editions of the same product**, decided 2026-10-04 in
[decisions/0004](decisions/0004-github-native-is-the-single-project-edition.md):
the Paperclip edition above, and a **GitHub-native single-project edition** for
a client with nowhere to host a control plane. Same pipeline, same roles, same
skills; GitHub replaces Paperclip's coordination layer behind a thin port.
Paperclip earns its place at project three. See M6.

## Where we are

The system is **feature-complete on paper and almost entirely unexercised.**
Everything in the README exists: the installer's ten phases, the restricted
`agents` Incus project, the six-role team, the skill library, the GitHub App
bot, and the GitHub bridge. Nearly all of it landed in one commit on
2026-10-04.

What has *not* happened: no feature has travelled the full pipeline. This repo
has zero pull requests, and its three issues are a founding vision document,
a one-line idea, and a design doc. The nine handoffs between six agents have
never run end to end against a real change.

That gap sets the order of everything below. See [STATE.md](STATE.md).

## Milestones

### M1 — The pipeline works once, start to finish

**Why first:** everything else is an improvement to a machine we have not yet
seen run. Until one feature goes operator → Product Manager → GitHub issue →
spec review → build → four reviews → merge without a human unsticking it, we
do not know which parts work.

**Decided 2026-10-04** (operator): the first run is dogfooded on this repo,
and M1 comes before M2 — see
[decisions/0002](decisions/0002-dogfood-the-pipeline-on-this-repo.md).

- One real feature through all nine handoffs, dogfooded on this repo. The two
  confirmed defects below are that feature: they are small, they are in the
  installer, and fixing them is what the first run carries.
- Sequenced, not parallel. The labels defect
  ([#6](https://github.com/dpeckham/my-ai-org/issues/6)) goes first because it
  is the smaller of the two and both edit `scripts/newproject.sh`; the skills
  defect ([#5](https://github.com/dpeckham/my-ai-org/issues/5)) follows it. One
  change at a time through an untested pipeline keeps it clear whether a stall
  is the pipeline or the change.
- Write down every place the pipeline stalled, in the README's **Gotchas**
  or as issues.

**Done when:** a pull request on this repo was specified, built, reviewed by
Lead Engineer, QA Lead and Security, and handed to the operator to merge, and
the operator did not have to intervene to move it between roles.

### M2 — Safe to re-run, hard to break

**Why:** "`git pull && ./install.sh` any time" is promise 3, and it rests on
~5,000 lines of shell with no automated checking of any kind — no CI, no
shellcheck, no exercise of the `--dry-run` and `--check` paths that exist
precisely to be safe. Agents are about to become the main authors of that
shell. A single bad merge breaks the upgrade path for every install.

- CI on pull requests: shellcheck across `scripts/` and `install.sh`.
- The dry-run and preflight paths exercised automatically
  (`newproject.sh --check`, `provision.sh --dry-run`,
  `install.sh --no-projects` as far as it can go unprivileged).
- A documented way to verify a change to the installer without a spare
  machine.

**Done when:** a pull request that breaks a script fails CI before a human
reads it.

### M3 — The operator actually sees the state of things

**Why:** promise 2 is the reason to run this rather than a pile of terminals,
and it is the one we have the least evidence for. The Chief of Staff and the
CTO's weekly review are configured; neither has been observed raising
anything.

- Confirm stalled work, failed runs and budget burn reach the operator, and
  fix them where they do not.
- Settle budgets: `newproject.sh` creates the five non-Product-Manager agents
  with `budgetMonthlyCents: 0`, and the Product Manager gets a budget only
  when `--budget` is passed. `0` is not an enforced ceiling — every agent in
  this company carries it, including ones that run daily, and none is paused —
  so the question is not what `0` means but what ceiling a project should get
  and what should happen when it is reached.
- One place that answers "what is every project doing, and what did it cost".

**Done when:** the operator can answer both of those questions without
opening an agent's run log.

### M4 — Someone else's machine

**Why:** the README is written for "its owner and for anyone else", and that
has never been true in practice: every install so far is the one it was
developed on. Portability failures are also the most expensive kind to find
late.

**Pulled forward 2026-10-04** (operator): clients are a real, near-term goal
with one client in view, so this stopped being a README promise and became a
dated requirement. See
[decisions/0004](decisions/0004-github-native-is-the-single-project-edition.md).

- A cold install verified on a machine that is not the development one, on
  each distro the README claims (Debian/Ubuntu, Arch, Fedora).
- macOS as a second box backend: designed in
  [#3](https://github.com/dpeckham/my-ai-org/issues/3), waiting on someone
  with Apple silicon. Step 1 of that issue, the backend verb layer, is a
  Linux-only refactor that can start any time and is filed separately as
  [#16](https://github.com/dpeckham/my-ai-org/issues/16). **Now load-bearing, not
  optional:** a Mac-only client has no LXC, and access to a Mac with macOS 26
  on Apple silicon is an escalation for the operator rather than a background
  wish.
- **But Apple silicon is no longer the only route to a Mac client.** The
  standing default since 2026-10-04 is to write the Lima-class Linux VM backend
  first — it runs the existing Incus install unchanged, works on Intel and
  older macOS, and needs no hardware we do not have — with Apple's runtime as
  the intended destination behind the same verbs. See
  [briefs/agent-runtime.md](briefs/agent-runtime.md) §10 and §14.
- The first-run experience judged by someone who did not write it.

### M5 — The fleet stays current

**Why:** boxes are created once and then drift. Skills, hooks and tooling
improve in this repo and never reach the containers already running. This is
[#2](https://github.com/dpeckham/my-ai-org/issues/2), and the skills defect in
M1 is the first instance of it.

- The DevOps agent reconciles every existing box against current org practice,
  not just boxes it creates.
- Skill, instruction and toolchain updates reach running projects without a
  full `install.sh`.

### M6 — The GitHub-native edition

**Why:** a client with nowhere to host Paperclip is nearly always a client with
one project, who was never buying Paperclip's cross-project half. Decided in
[decisions/0004](decisions/0004-github-native-is-the-single-project-edition.md),
on the research in
[briefs/github-native-edition.md](briefs/github-native-edition.md).

**After M1, not instead of it:** a second control plane under a pipeline we
have never seen run end to end leaves us unable to tell which half is broken.
The operator has not contradicted that, and reversing it is one word.

- Extract the **control-plane port**: the seven agent verbs (list my work, read
  a thread, comment, set status, reassign, ask the human, create a child issue)
  become one thin interface the skills and `templates/` call instead of
  Paperclip's API. Worth doing on its own merits — it is how we stop being
  exposed to Paperclip's experimental surface.
- Settle the three spikes that can reshape or kill the design: delivery-log
  retention, prompt assembly against a Paperclip wake payload, and the question
  loop end to end including an operator answering only by email. Not yet filed
  as issues.
- A **dispatcher** in the box: event source, claims, a `git worktree` per run,
  prompt assembly, the question loop. This is the real work, and the part
  Paperclip gives us free today.
- A **spend ledger and a kill switch in the box**, shared by both editions —
  `budgetMonthlyCents: 0` enforces nothing today, so this is owed either way
  (see M3).
- Dogfooded on this repo, GitHub-native, with the same agents and skills.

**Refined by [0005](decisions/0005-coordination-state-lives-in-the-github-thread.md):**
[briefs/agent-runtime.md](briefs/agent-runtime.md) takes the runtime apart —
triggers, the wake, and the four kinds of context an agent points at. Its
central proposal is now decided: **coordination state lives in the GitHub
thread**, so the box holds nothing durable and a run can resume on any machine.
Three things that reach back into this list:

- **The backend verb layer is filed as
  [#16](https://github.com/dpeckham/my-ai-org/issues/16)** (step 1 of
  [#3](https://github.com/dpeckham/my-ai-org/issues/3)), and it is the seam
  this milestone's dispatcher needs on either platform. 0005 made it
  load-bearing rather than merely useful: with no state in the box, the backend
  is a per-install config and that layer is where the choice lives. Shared with
  M4, a Linux-only refactor, needs no Mac — the first thing anyone can usefully
  do here.
- **The verb layer must carry stdin in and stream stdout out of `box_exec`.**
  The dispatcher needs no eighth verb if it does, and retrofitting it later is
  awkward (brief §12).
- **The worktree is created inside the box, not mounted into it.** The `agents`
  Incus project refuses host-path disks by design, so the Paperclip pattern of
  staging a run directory on the host does not port. Each box keeps a bare
  mirror of the repo and adds a worktree per run — a cache, not state.

Still running on standing defaults rather than decisions: the two macOS
questions, 5 and 6 in [STATE.md](STATE.md).

**Done when:** one feature travels the full pipeline on this repo with no
Paperclip running, and the operator answers one agent question by email.

## Known defects

Confirmed by reading the code on 2026-10-04, both affecting M1:

1. **A project created outside a full install gets no skills** ([#5](https://github.com/dpeckham/my-ai-org/issues/5)).
   `scripts/newproject.sh` creates the six agents and fires the kickoff issue
   immediately, but never attaches skills; only `scripts/skills-sync.sh`
   (install phase 8) does that. So the documented way to add a project later —
   and the DevOps agent's normal tool — produces a team whose agents are
   missing every skill their role depends on, including `team-workflow`, which
   is how they know the pipeline exists at all.
2. **The `agent` and `ui` labels are load-bearing and nothing creates them** ([#6](https://github.com/dpeckham/my-ai-org/issues/6)).
   `scripts/github-bridge.mjs` skips pull requests labelled `agent` to tell
   its own team's work from an outside contributor's, and the whole UI Designer
   branch of the pipeline keys off `ui`. No script creates either label.
   Unlabelled, the Coder's own pull request reads as an outside contribution and
   the bridge opens a review issue for work already in the pipeline. Both
   labels were created by hand in this repo on 2026-10-04 to unblock the first
   pipeline run; that is a one-repo workaround and the defect is unchanged for
   every other repo.

## Out of scope

Deliberately not building these. Revisit only with a reason that has changed.

- **Two installs sharing one repo.** Paperclip's assignment is a claim inside
  one install, so two would duplicate each other's work. Outside contributors
  use GitHub issues and pull requests; the bridge brings those in.
- **Paperclip itself.** It is an upstream dependency. We work around its
  rough edges in **Gotchas** and report upstream; we do not fork it.
- **API-key billing.** Agents run on the operator's Claude and codex
  subscriptions. The long-lived token path stays the only supported one.
- **Windows hosts, and macOS before #3's unknowns are settled on real
  hardware.**
- **A hosted or multi-tenant service.** This installs on a machine its
  operator controls. Nothing here is designed for untrusted tenants. M6 does
  not cross this line: it still installs on a machine the client controls.
- **A second product with its own control plane.** The GitHub-native edition is
  a second adapter behind one port, not a fork. A fork would mean paying for
  every pipeline, role and skill change twice, for ever
  ([0004](decisions/0004-github-native-is-the-single-project-edition.md)).
- **Agents merging their own work.** Only the operator merges. Not a
  limitation to remove later.
