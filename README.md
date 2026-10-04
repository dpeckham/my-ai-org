# my-ai-org: run a company of AI agents from one machine

## Why this exists

This is for operators with more projects than they can keep track of. It
gives you a complete agent organisation that works in the background, keeps
every project moving, and puts the things that need you in front of you:

- **Agents run in the background.** Each project has its own agents, working
  on issues while you do something else.
- **Problems come to you.** Stalled work, failed runs, decisions only a human
  should make and budget burn are raised by the agents, not found by you
  digging.
- **Agents fill the roles a company needs.** Project management, QA,
  development, DevOps, marketing, finance (CFO): each is an agent with a job
  description, a manager and a budget.

In practice you can run a company from inside here. You set direction as the
board, a Chief of Staff turns it into work, a Product Manager leads each project, and
specialists join where needed.

The repo holds no secrets and nothing project-specific. Credentials are
installed from the machine running the scripts, and your project list lives
in the gitignored `local/`.

## Quick start

### 1. Before you start

You need:

- a Linux machine running **Debian/Ubuntu, Arch or Fedora**, with `sudo`. The
  installer adds everything else: Incus, mise, gh, jq, git. **macOS isn't
  supported yet**, because project boxes are Linux (Incus) containers. Support
  using Apple's own [`container`](https://github.com/apple/container) runtime
  is designed in [#3](https://github.com/dpeckham/my-ai-org/issues/3) and
  waiting for someone with a Mac to pick it up. Until then, run the install on
  a Linux machine, or in a Linux VM on the Mac.
- a **GitHub account** that can see the repos you want as projects.
- a **Claude subscription** (Pro or Max). Agents run on it through a
  long-lived token, not an API key.
- nothing else listening on **localhost:3100**, where Paperclip's UI goes.

### 2. Get the repo

```
git clone https://github.com/<org>/<this-repo>.git
cd <this-repo>
```

### 3. Files to create or edit (all optional)

| File | Why you'd touch it |
|------|--------------------|
| `local/projects.manifest` | **Which repos become projects.** Skip it on the first run, and the installer writes one listing every repo you can access, all commented out. Or start from the example: `mkdir -p local && cp examples/projects.manifest local/projects.manifest`. Never committed (`local/` is gitignored). |
| `templates/*.md` | The instructions each agent role starts with. Changes reach existing agents on the next `./install.sh` too, unless you've edited that agent's instructions in the Paperclip UI. |
| `skills/sources.manifest` | Which skills each role gets, and where they come from. |
| `scripts/pixels-config.toml` | Default size of a project box (4 CPU / 4GiB) and the egress allowlist. |

Sizing is set by environment variables instead of a file. The default cap for
all project boxes together is 20GiB of memory, which is about four boxes.
For more, run the installer as `AGENTS_MEMORY=40GiB ./install.sh` (see **The
`agents` project**).

### 4. Terminal steps beforehand (optional)

The installer asks for each of these when it needs it, so doing them first
only saves interruptions:

```
gh auth login              # GitHub, for cloning private repos
claude setup-token         # prints a long-lived Claude token; keep it for the installer's prompt
codex login                # only if you want codex agents as well
```

If you were just added to the `sudo` group, log out and in again first.

### 5. Run the installer

```
./install.sh               # asks for your company's name; --company "Name" skips that
```

Run it in a real terminal; it prompts for sudo and for sign-ins. It works in
phases and skips any that are already done:

| Phase | What happens |
|-------|--------------|
| 0. prereqs | installs Incus, mise, gh, jq, git; sets up subordinate IDs; starts and initialises Incus; joins `incus-admin` (and carries on under it, no logout); creates `~/.ssh/id_ed25519` if missing |
| 1. sign-ins | `gh auth login`, and the long-lived Claude token (`claude setup-token`, then a hidden paste prompt), each only if missing |
| 2. host | `scripts/host-setup.sh`: the restricted `agents` project, the Incus API on the bridge, `.incus` DNS, pixels |
| 3. base image | the template every project box is cloned from, about 3 minutes the first time |
| 4. paperclip | `scripts/paperclip-up.sh`: the Paperclip container, its service, credentials, and the GitHub bridge |
| 5. org | `scripts/paperclip-org.sh`: your company, a Chief of Staff, a CTO (with a weekly review) and a DevOps agent |
| 6. GitHub bot | `scripts/github-apps.sh`: the GitHub App the reviewing roles act as. Two browser clicks the first time (create, install); after that, a check |
| 7. projects | `scripts/provision.sh local/projects.manifest`: one box and a six-agent team per project |
| 8. skills | `scripts/skills-sync.sh`: loads `skills/sources.manifest` into Paperclip and attaches each skill to the roles that use it |
| 9. boxes | refreshes the tools this repo ships (`gh-bot`) on boxes that already exist |

**The first run stops after phase 7 writes your project list.** Open
`local/projects.manifest`, uncomment the repos you want (several repos on
one line become one project), then run it again:

```
$EDITOR local/projects.manifest
./install.sh               # or just: scripts/provision.sh local/projects.manifest
```

Each new project's Product Manager starts right away on a kickoff issue: it reads the repo
and opens a pull request with a roadmap. Add `--no-kickoff` to that project's
line to hold it back.

### 6. After installing

- **Paperclip:** <http://localhost:3100>. The Chief of Staff, CTO, DevOps and
  each project's team are in the org chart.
- **Start a feature:** open an issue in Paperclip, assign it to a project's
  Product Manager, and brainstorm with it there. It files the GitHub issue and
  the team takes it from there (see **The team and its pipeline**).
- **A project box:** `ssh px-<name>`, or `pixels console <name>`.
- **More projects later:** add lines to the manifest and re-run, or
  `scripts/newproject.sh <name> <org/repo>`. Or ask the DevOps agent in
  Paperclip to do it.

Options: `--company "Name"`, `--projects FILE`, `--no-projects`.

### 7. Upgrading

```
git pull && ./install.sh
```

That's the whole upgrade, and it's safe to run any time. Every phase
reconciles rather than skipping what exists:

- **The template rebuilds** when `scripts/base-setup.sh` has changed (its
  checksum is stored in the template). New boxes get the new toolchain;
  existing boxes keep theirs until rebuilt.
- **Paperclip updates itself** to the latest release (database backed up
  first, previous version kept for `paperclipai update --rollback`), and the
  container's tools upgrade. `PAPERCLIP_UPDATE=0 ./install.sh` skips both.
- **Agents are brought into line:** missing team members are hired, and
  runtime, role, manager and credentials are reconciled. Instructions are
  rewritten from `templates/` **only while they are still exactly what this
  repo last wrote**: each agent stores a checksum of that text. If you edited
  an agent's instructions in the UI, they're left alone and the run says so.
  `RESET_INSTRUCTIONS=1 ./install.sh` overwrites them anyway.
- **Skills re-sync**, so new and changed skills reach every agent.
- **`gh-bot` is refreshed** on existing boxes, and the GitHub bridge in the
  Paperclip container.

The installer also tells you when your checkout is behind its upstream.
After a failure, fix the cause and run it again; finished work is skipped.

## Architecture

```
 your machine (the Incus host)
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │  you: browser ──► localhost:3100            you: ssh px-foo / pixels         │
 │                       │ (proxy)                      │                       │
 │  Incus ───────────────┼──────────────────────────────┼─────────────────────  │
 │  ┌ default project ───▼─────────────────────┐        │                       │
 │  │ paperclip container                      │        │                       │
 │  │   Paperclip server + Postgres            │        │                       │
 │  │   Chief of Staff, DevOps  (run here)     │        │                       │
 │  │   repo checkouts Paperclip owns          │        │                       │
 │  └──────┬──────────────────────┬────────────┘        │                       │
 │         │ restricted cert      │ ssh (agent runs)    │                       │
 │         │ (provisioning)       │                     │                       │
 │  ┌ agents project ─▼───────────▼─────────────────────▼───────────────────┐   │
 │  │ px-base  template + `ready` snapshot                                  │   │
 │  │ px-foo, px-bar, ...   one per project: repos, toolchain, its agents   │   │
 │  └───────────────────────────────────────────────────────────────────────┘   │
 └──────────────────────────────────────────────────────────────────────────────┘
```

### The layers

| Layer | What it is | Why it's separate |
|-------|------------|-------------------|
| **Host** | your machine, running Incus | Kept clean for your own work. Nothing agent-related runs on it beyond the Incus client, pixels and your own `claude`. |
| **Paperclip container** | the control plane: org chart, issues, schedules, approvals, budgets, UI; the Chief of Staff and DevOps agents run here | One place to look at everything. Its UI is reachable only from the host's `localhost`. |
| **`agents` Incus project** | a walled-off area holding every project box | What Paperclip can create and destroy. It's capped and restricted, so the worst a runaway agent can do is wreck project boxes, never the host or Paperclip. |
| **Project box** (`px-<name>`) | one container per project, cloned in seconds from a template, with the repos and toolchain installed | The project's agents run here, so projects can't reach each other's files, processes or credentials, and a box can be thrown away and rebuilt. |
| **Git** | each project's repo | The durable memory: roadmaps, state and decisions live in the repo, not in chat history. |

### The organisation

Everything lives in **one Paperclip company**, which stands for you. You are
the board: you set direction and approve anything irreversible.

- **Chief of Staff** (role `ceo`): turns your requests into work, sets
  priorities across projects, watches for stalled work and failed runs, and
  reports up.
- **CTO:** a weekly review across all projects for security, engineering
  practice and compliance; files what it finds and reports to the Chief of
  Staff.
- **DevOps:** provisions and maintains project boxes, using the same scripts
  you would.
- **A team per project:** a Product Manager (what to build and why), Lead
  Engineer, UI Designer, Coder, QA Lead and Security. See **The team and its
  pipeline**.
- **More roles as needed:** marketing, CFO and so on, hired into the org chart
  with their own instructions and budgets.

Each project is a Paperclip *project* inside the one company, so work can be
handed between projects with ordinary issue assignment. A project that grows
into a real business of its own can later be split into a separate Paperclip
company.

### How work happens

1. **Starting a project.** You, or DevOps, run `scripts/newproject.sh <name>
   <org/repo>`. It clones a box from the template, checks the repo out, and
   creates the Paperclip side: an SSH environment pointing at the box, the
   project's six-agent team, the project, and a kickoff issue.
2. **A feature.** You brainstorm with the Product Manager; it files a GitHub
   issue; the Lead Engineer reviews it as a spec; the Coder builds it as a pull
   request; Lead Engineer, UI Designer, QA Lead and Security review it in turn;
   you merge.
3. **An agent run.** When an agent is woken (an issue assigned, a comment, a
   schedule), Paperclip copies the project's workspace into a fresh directory
   on the box, runs `claude` or `codex` there over SSH, and copies the changes
   back. The agent reports progress to Paperclip through a tunnel inside that
   SSH session, so boxes need no network route to it.
4. **Results.** Code lands as branches and pull requests on the project's
   repo. Status, questions and blockers land as comments on the Paperclip
   issue, where the Chief of Staff and you see them.

### Credentials and trust

- **Agents use your subscriptions, not API keys:** a long-lived Claude token
  (`claude setup-token`) and your codex and GitHub logins, installed into each
  box at creation and never baked into the template.
- **Two GitHub identities.** The Coder acts as your account; every reviewing
  role acts as one GitHub App (the bot), so reviews and approvals are separate
  from the author, and only you merge.
- **Paperclip's Incus access is restricted** to the `agents` project:
  unprivileged containers only, no host paths, capped memory, CPU and
  instance count.
- **Agent forwarding is off** everywhere, so no box can borrow your SSH keys.
- **An optional egress allowlist** (`--egress agent`) limits a box to the
  hosts on an approved list.

The sections after **Repository layout** cover each piece in depth.

## Repository layout

```
README.md           this manual
install.sh          the one command
CLAUDE.md           rules for agents working in this repo (including the DevOps agent)
templates/          instructions (AGENTS.md) for every agent role
skills/             skills the agents load, and sources.manifest listing which roles get which
examples/           manifest format, with placeholder names
local/              your project list and other machine-local files (gitignored)
scripts/            everything install.sh runs, usable one at a time
```

| Script | Runs on | Does |
|--------|---------|------|
| `host-setup.sh` | Incus host | the restricted `agents` project, Incus API on the bridge, `.incus` DNS, pixels and the `px-*` SSH block |
| `base-setup.sh` | template container (root) | git, gh, mise, herdr, t3 and the agent CLIs in the base image |
| `paperclip-up.sh` | Incus host | builds or updates the Paperclip container end to end |
| `paperclip-setup.sh` | Paperclip container (root) | node, Paperclip and its service, pixels, incus client, SSH key |
| `paperclip-org.sh` | Incus host | the root company, and the Chief of Staff, CTO and DevOps agents |
| `newproject.sh` | host or Paperclip | one project: box, SSH environment, six-agent team, Paperclip project, kickoff issue |
| `provision.sh` | host or Paperclip | `newproject.sh` for every line of a manifest, with a preflight and summary |
| `list-repos.sh` | host | writes `local/projects.manifest` from every repo the `gh` login can see |
| `newbox.sh` | host or Paperclip | a bare box: clone the base, authorize keys, seed creds, check out repos |
| `github-apps.sh` | host | creates and installs the company's GitHub App bot; stores its key as Paperclip secrets |
| `gh-bot` | boxes, Paperclip | `gh` acting as the bot, with a token scoped to one repo per call (installed at `~/.local/bin/gh-bot`) |
| `skills-sync.sh` | host or Paperclip | loads `skills/sources.manifest` into Paperclip and attaches skills by role |
| `github-bridge.mjs` | Paperclip container (timer) | polls each project's repos and turns GitHub activity into Paperclip work |
| `lib/paperclip.sh` | — | shared helpers: the Paperclip API, and `ensure_agent`, which creates or reconciles an agent |
| `set-claude-token.sh` | host | installs the long-lived Claude token on the host, in Paperclip, and on every box |
| `seed-agent-auth.sh` | host | copies claude / codex / gh credentials into a box or the Paperclip container |
| `t3-connect.sh` | host | connects the T3 Code client to a box from the CLI |
| `pixels-config.toml` | — | pixels settings shared by every caller |
| `bootstrap.sh`, `firstboot.sh`, `laptop-setup.sh` | — | the optional **remote box** layout (see the end) |

## The `agents` project: the trust boundary

Paperclip's DevOps agent has to be able to create and destroy containers.
Full access to the Incus API is equivalent to root on the host, so it doesn't
get that. Instead, every project box lives in a separate Incus project, and
Paperclip holds a client certificate **restricted to that project**.

`host-setup.sh` creates it with `restricted=true`, which blocks privileged
containers, nesting, disks that are not on a managed pool, `raw.*` keys,
backups and so on. On top of that it adds:

| Key | Value | Why |
|-----|-------|-----|
| `restricted.snapshots` | `allow` | pixels checkpoints are snapshots; restricted blocks them by default |
| `restricted.networks.access` | `incusbr0` | boxes may only join the shared bridge |
| `limits.memory` | `20GiB` | caps the whole fleet; see below |
| `limits.cpu` | `32` | sum of per-box `limits.cpu` |
| `limits.instances` | `10` | |

All of these are env knobs on `host-setup.sh` (`AGENTS_MEMORY=...`).

**Project limits count every instance's cap, running or stopped**, the
template included. At the default 4GiB per box, 20GiB means the template plus
four boxes. When the cap is hit, creation fails with a limits error. Destroy
a box or raise the cap.

The project has `features.networks=false`, so boxes share the default
project's bridge and DNS. They resolve as plain `<name>.incus` from anywhere
on the bridge, whatever project they are in.

What the restricted certificate was verified to refuse: exec into anything
in `default` (including the Paperclip container itself), privileged
containers, host-path disks, and any server config change.

The Incus API listens on the **bridge address only** (`core.https_address =
<bridge-ip>:8443`). Containers can reach it, but still need a trusted
certificate. The LAN cannot reach it at all. If your host already serves the
API on another address, `host-setup.sh` leaves it alone and says so.

## Paperclip

### What runs where

| | Where | Notes |
|-|-------|-------|
| Paperclip server + embedded Postgres | `paperclip` container, `default` project | systemd **user** service, `127.0.0.1:3100` inside the container |
| UI | `http://localhost:3100` on the host | Incus proxy device `ui` (`bind=host`); nothing else can reach it |
| State | `/home/paperclip/.paperclip` in the container | config, DB, logs, secrets key, backups |
| Agents doing project work | the project boxes | over Paperclip's SSH environment driver |
| The DevOps agent | the `paperclip` container | runs `newbox.sh` / `pixels` from its checkout of this repo |

Paperclip runs in `local_trusted` mode, with no login. That's safe only
because the only way in is the host's loopback. Do not switch the proxy to
`0.0.0.0`. For access from another device, reconfigure Paperclip for
`authenticated` mode (`paperclipai configure --section server`) and put it
on a tailnet instead.

`paperclip-up.sh` is idempotent. Re-run it after changing any of the
scripts. It also seeds this machine's agent credentials into the container
(`--no-auth` skips that) and clones this repo there over HTTPS. A private
fork needs the seeded `gh` token.

Telemetry: Paperclip reports usage by default. `paperclip-setup.sh` turns it
off (`PAPERCLIP_TELEMETRY_DISABLED=1` in the user manager's environment). Run
`PAPERCLIP_TELEMETRY=on scripts/paperclip-up.sh` to leave it on.

```
incus exec paperclip -- su - paperclip                     # a shell as the service user
# then, inside:
export XDG_RUNTIME_DIR=/run/user/$(id -u)                  # needed for systemctl --user under su
paperclipai service status | logs -f | restart
paperclipai doctor
paperclipai update                                         # new release; swaps the managed install
```

### Pointing Paperclip at a project box

Paperclip reaches boxes with its **SSH environment** driver, which is still
**experimental**. `paperclip-setup.sh` turns it on at install through the API
(`PATCH /api/instance/settings/experimental {"enableEnvironments": true}`);
in the UI it's under Settings → Instance settings → Experimental.
`newproject.sh` creates the environment for each project. By hand, the fields
are:

| Field | Value |
|-------|-------|
| Driver | SSH |
| Host | `px-foo` |
| Port | `22` |
| Username | `pixel` |
| Remote workspace path | `/home/pixel/paperclip` |
| Private key | leave empty |
| Known hosts | leave empty |
| Strict host key checking | on |

Agents assigned to it need **engine `cli`** in their adapter settings (see
**Gotchas**).

Paperclip shells out to the system `ssh` without `-F`, so the `paperclip`
user's `~/.ssh/config` applies. The `px-*` block there maps `px-foo` to
`px-foo.incus` and keeps host keys in `~/.ssh/known_hosts.pixels`. With the
key and known-hosts fields empty, it uses the user's own `~/.ssh/id_ed25519`
and that file. `newbox.sh` authorizes the key and records the host key when
it waits for sshd, which is why strict checking passes without pasting
anything. That exact command line (`BatchMode=yes`,
`StrictHostKeyChecking=yes`, no `-i`) was tested against a fresh box.

How a run on a box works:

- Agents talk back to Paperclip through a bridge tunnelled over that same SSH
  session. Boxes need no route to Paperclip, so `--egress agent` boxes are
  fine.
- `claude_local` runs authenticate with the long-lived subscription token
  bound on the environment (`CLAUDE_CODE_OAUTH_TOKEN`; see **Agent
  credentials**). They stay on your subscription, with no API key.
- `codex_local` is different. It uploads the Paperclip container's
  `~/.codex/auth.json` to the box, shadowing the box's own login. So the
  Paperclip container needs a codex login too (`paperclip-up.sh` seeds one if
  the host has it).

Known rough edges in the SSH driver, as of Paperclip 2026.1001:

- Cancelling a run or hitting a timeout stops only the local `ssh` client, not
  the agent on the box
  ([#14704](https://github.com/paperclipai/paperclip/issues/14704)).
- Paperclip-managed MCP tools show up on SSH targets, but calls are blocked by
  the fixed `--allowedTools` list
  ([#14940](https://github.com/paperclipai/paperclip/issues/14940)).
- Per-run workspace copies under `.paperclip-runtime/runs/` are never cleaned
  up on the box
  ([#14527](https://github.com/paperclipai/paperclip/issues/14527)). Prune
  them now and then.

**Agents on a box do not work in the box's own checkout.** Each run, the
SSH driver:

1. uploads the project workspace from the Paperclip side to
   `<remote workspace path>/.paperclip-runtime/runs/<run id>/workspace` on the
   box (a git import plus the tracked files);
2. runs the agent there;
3. copies the changes back.

So the checkout Paperclip treats as the project's workspace lives in the
**Paperclip container**, at `~/code/<org>/<repo>`. The box's checkout at the
same path is the human's copy, for `ssh`, herdr and T3. The two meet through
the git remote, which is the durable memory either way. `newproject.sh` sets
up both. The `claude` or `codex` binary must already be on the box's PATH,
since the SSH driver installs nothing; the base image has both.

### Company model

One Paperclip **company** stands for the operator, and every project lives
inside it as a Paperclip **project**: its own box, its own SSH environment,
and a Product Manager agent as lead. Paperclip companies are strict silos. Cross-company
API calls return 403, and there's no parent/holding relationship. Inside one
company, though, projects can hand work to each other through ordinary issue
assignment and share roles like a CEO or DevOps agent. If a project later
needs walled-off budgets and agents, it can be split into its own company,
which the operator then runs alongside the first.

### The team and its pipeline

Every project gets the same six agents, named `<Project> <Role>`:

| Role | Paperclip role | Owns | GitHub identity |
|------|----------------|------|-----------------|
| Product Manager | `pm` | what gets built and why: brainstorming with you, feature issues, roadmap, state | bot |
| Lead Engineer | `engineer` | spec review before work starts; code review | bot |
| UI Designer | `designer` | a design section on `ui` features before build; UI review of the PR | bot |
| Coder | `engineer` | implementation: branch, commits, draft PR, review rounds | **you** |
| QA Lead | `qa` | acceptance criteria actually met, tests, CI | bot |
| Security | `security` | authn/authz, input handling, secrets, dependencies | bot |

A feature is one Paperclip issue, reassigned from role to role; the GitHub
issue and pull request carry the work itself:

```
you ⇄ Product Manager ─► GitHub issue ─► Lead Engineer (spec review) ─┬─► UI Designer (design, `ui` only) ─┐
                                                                     └──────────────────────────────────┴─► Coder ─► draft PR ─► ready
   ─► Lead Engineer (code review) ─► UI Designer (`ui` only) ─► QA Lead ─► Security ─► you merge
```

- **Handoffs are Paperclip assignments.** Each agent comments its outcome on
  the Paperclip issue and reassigns it, which wakes the next one; nothing
  polls or waits.
- **Rework goes back through the chain.** An approval covers one commit, so
  when the Coder changes code after a review, the PR starts again at the Lead
  Engineer, and each reviewer checks only what changed since its last review.
- **Security hands the PR to you** with the CI state, the commit every review
  approved, and the merge command for the repo's settings. Only you merge.
- **Telling agents apart.** Reviewing roles share the bot, so every review
  starts with a bold role header (`**QA Lead review**`); the Coder's PRs carry
  the label `agent` and its commits the trailer `Agent: Coder (Paperclip)`.
- **Screenshots for `ui` features** go on a separate `pr-assets` branch and are
  linked from the PR, because GitHub's CLI can't upload images.

The full process, written for the agents, is the `team-workflow` skill.

### Work that starts on GitHub

**A project runs in exactly one Paperclip company.** The operator who runs it
is the only one with agents working on it; everyone else contributes the
ordinary way, by opening GitHub issues and pull requests. Two installs working
the same repo would duplicate each other's work, because Paperclip's
assignment is only a claim inside one install.

Outside activity reaches the team through the **GitHub bridge**
(`scripts/github-bridge.mjs`): a small poller in the Paperclip container, run
by a systemd user timer every minute. Each project is polled at its own
interval. It contains no AI and costs one or two GitHub API calls per repo per
poll; an agent only runs when an event turns into a Paperclip issue or comment,
which is what wakes it.

| GitHub event | Becomes |
|---|---|
| a new issue (from anyone but the bot) | a triage issue for the **Product Manager**: accept and assign, ask for more, or decline |
| a new PR without the `agent` label | a review issue for the **Lead Engineer**; it enters the pipeline at code review, and changes are requested from its author |
| a human's comment on an issue or PR | a comment on the Paperclip issue tracking it (which wakes whoever holds it), or a Product Manager issue if nothing tracks it |
| a failed CI run on the default branch | an issue for the **Lead Engineer** |
| a new Dependabot alert | an issue for **Security** |

- **Near real time, by interval:** 5 minutes by default; per project with
  `scripts/newproject.sh <name> <repo> --watch-every 1m` (`30s`–`1d`, or `off`;
  the timer's 1-minute tick is the floor). The company default is
  `defaultIntervalSec` in the container's `~/.config/my-ai-org/bridge.json`.
- **Polling only, by design.** GitHub webhooks would need a public URL into
  Paperclip, which runs without a login because only your localhost can reach
  it. Polling needs no inbound access at all.
- **It starts from "now".** The first pass for a repo records the time and
  routes nothing, so years of history don't flood the agents. To backfill after
  an outage: `node ~/.local/share/my-ai-org/github-bridge.mjs --since <time>`
  (add `--dry-run` to preview).
- **Telling humans from agents.** Bots are skipped; so are posts that open with
  an agent's role header (the Coder posts as your account, so its comments
  start with `**Coder**`), and PRs labelled `agent`. Everything else counts as
  human.
- **Finding the tracking issue.** The bridge matches GitHub URLs in Paperclip
  issue descriptions, so the team keeps the GitHub issue URL on the first line
  and the PR URL on the second.
- **Duplicates:** every Paperclip issue it opens carries an idempotency key, so
  a re-read window or a retry never creates a second one.
- Logs: `journalctl --user -u my-ai-org-github-bridge` in the container (the
  full command is printed by `paperclip-up.sh`).

### Skills

Skills are delivered through **Paperclip's company skill library**, which
gives the same skills to claude and codex agents alike. `skills/sources.manifest`
lists each skill, where it comes from, and which roles get it;
`scripts/skills-sync.sh` (phase 8) imports them and attaches them by role.

| Skill | Source | Roles |
|-------|--------|-------|
| `team-workflow` | ours | everyone in a project, CTO, Chief of Staff |
| `github-bot` | ours | every role that acts as the bot |
| `coding-practices` | [dbaggott/claude-plugins](https://github.com/dbaggott/claude-plugins), unmodified, pinned to a commit | Lead Engineer, Coder, QA Lead, Security, CTO |
| `issue-writing`, `spec-review`, `pull-requests`, `code-review` | adapted from [dbaggott/claude-plugins](https://github.com/dbaggott/claude-plugins) | by role, see the manifest |

The rule for third-party skills: **use as-is by reference when possible**
(`github:<owner>/<repo>/<path>@<commit>`), and copy into `skills/` only when
we need to change something. Copies say where they came from and what changed,
and `skills/THIRD_PARTY_NOTICES.md` records the licence obligations. The four
adapted skills keep Dan Baggott's craft (issue quality, spec review, draft-first
PRs, review method) and drop his process plumbing (enforcement hooks,
watchers, claim labels, interactive prompts), which doesn't fit unattended
runs or codex.

Paperclip only imports local skills from approved directories, so the sync
copies ours into the company's managed-skill directory in the container
first. Removing a line from the manifest stops new agents getting that skill
but doesn't detach it from existing ones.

### The GitHub bot

GitHub never lets a pull request's author approve it. The Coder authors as
you, so every reviewing role acts as one **GitHub App**, `<your-login>-bot`.
One App rather than one per role: an App per role only changes the name on a
review, and the role header already does that.

`scripts/github-apps.sh` (phase 6) creates it through GitHub's App manifest
flow: a local page sends the App's definition to GitHub, you click **Create**,
and the private key comes back to the script without any copying. Then you
click **Install** and choose **All repositories**, so future project repos are
covered. The key is stored in `~/.config/my-ai-org/github-app/` (mode 600)
and as two Paperclip secrets, which `paperclip-org.sh` and `newproject.sh`
bind on the reviewing agents only (`GITHUB_BOT_APP_ID`,
`GITHUB_BOT_PRIVATE_KEY`). The Coder never gets it.

Agents call `gh-bot` exactly like `gh`. Each call signs a short-lived App
token and exchanges it for an installation token **limited to the one
repository** the command targets, so a token can't reach other repos.

The App's permissions are contents write, pull requests write, issues write,
and read on checks, actions, statuses, security events and vulnerability
alerts. Contents write isn't for pushing code: GitHub leaves an App's review
out of a PR's review decision without it, so approvals would post but never
count.

Repos in an organisation you don't own need that org's owner to install the
App. Until then, `gh-bot` fails there with a clear message, and the agent
hands the issue to you rather than falling back to your account.

### Starting a project

```
scripts/newproject.sh <name> <org/repo> [<org/repo>...] [options]
scripts/provision.sh  <manifest> [--dry-run]       # many at once
```

`newproject.sh` takes a project from repo to a working team in eight steps. Each
step finds its object by name and skips it if it already exists, so a failed
run can simply be repeated:

| Step | Creates |
|------|---------|
| 1. box | `px-<name>` via `newbox.sh`, with every repo at `~/code/<org>/<repo>` |
| 2. host key | records the box's host key for the Paperclip user (strict checking needs it) |
| 3. checkouts | the repos again, in the Paperclip container (see above for why) |
| 4. environment | SSH environment `<name>` → `px-<name>`, then probes it |
| 5. team | `<Name> Product Manager`, `Lead Engineer`, `UI Designer`, `Coder`, `QA Lead`, `Security`, all on that environment. The Product Manager reports to the CEO if there is one; Coder to Lead Engineer; the rest to the Product Manager |
| 6. project | project `<name>`, Product Manager as lead, one workspace per repo (the first is primary) |
| 7. kickoff | an issue for the Product Manager: read the repos, write `docs/ROADMAP.md` + `docs/STATE.md`, open a PR. It is assigned as `todo`, so **the Product Manager starts working immediately** |
| 8. GitHub watch | sets how often the GitHub bridge polls the project's repos (`--watch-every`), or reports the current interval |

Options: `--prodmgr-adapter claude|codex`, `--prodmgr-model`,
`--team-adapter claude|codex` (the other five), `--watch-every <duration>`,
`--reports-to <agent>`,
`--budget <dollars>`, `--prodmgr-instructions <file>`, `--no-kickoff`,
`--egress agent` and `--no-auth` (both passed to `newbox.sh`), `--company`,
and `--dry-run`. `scripts/newproject.sh --check` runs only the preflight.

The Product Manager's instructions come from `templates/product-manager.md`, rendered with the
project name and repo list, and are stored by Paperclip as the agent's
`AGENTS.md`. Edit the template to change every future Product Manager. Existing ones are
edited in the UI.

`provision.sh` takes a manifest with one project per line. Each line is a
`newproject.sh` command line without the script name, and `defaults` lines are
prepended to every project (see `examples/projects.manifest`). It runs a
preflight first (Paperclip, company, the experimental flag, and memory
headroom in the `agents` project for the boxes it will add), keeps going when
one project fails, and prints a summary. It never deletes anything. **Keep real
manifests out of this repo**, since they name real orgs and repos. `local/` is
gitignored for exactly this.

To start from everything you have access to:

```
scripts/list-repos.sh                                  # -> local/projects.manifest
$EDITOR local/projects.manifest                  # uncomment what you want
scripts/provision.sh local/projects.manifest --dry-run
```

The generated file lists every repo the `gh` login can clone (owned,
collaborator, and org member), grouped by owner and tagged
private/public/archived/fork with the last push date. Every line starts
commented out, except projects whose box already exists, so running it as-is
creates nothing new. Names are the repo name, made safe for `newproject.sh`;
when two owners share a repo name, the owner is prefixed. `list-repos.sh`
never overwrites an existing manifest. A re-run writes `….new` for you to diff
and merge.

Before the first run:

- SSH environments sit behind an experimental flag. `paperclip-setup.sh` turns
  it on at install. `newproject.sh` checks for it and stops if it has been
  turned off since.
- The Product Manager's adapter needs credentials. `claude_local` uses the box's own login,
  which `newbox.sh` seeds. `codex_local` uploads the **Paperclip container's**
  codex login, so the container needs one. For private repos, the Paperclip
  container needs a `gh` token to clone them. `seed-agent-auth.sh --incus
  paperclip:paperclip` covers all of these.
- With no CEO in the company, Product Managers report to nobody until you set
  `--reports-to` or fix it in the UI.

### Standing agents

`paperclip-org.sh` gives every install the same shape:

| Agent | Role | Runs | Job |
|-------|------|------|-----|
| Chief of Staff | `ceo` | Paperclip container | triage, cross-project priorities, oversight, reporting to the operator |
| CTO | `cto`, reports to Chief of Staff | Paperclip container | a weekly review across all projects (a Paperclip routine, Mondays 09:00 in your timezone; `REVIEW_CRON` / `REVIEW_TZ` change it) |
| DevOps | `devops`, reports to Chief of Staff | Paperclip container, from its checkout of this repo | starts projects (`newproject.sh`), maintains boxes, keeps this repo current |

Each project's six agents come from `newproject.sh` (see **The team and its
pipeline**). All of them run claude with `engine: cli` on the long-lived token
by default. Their instructions come from `templates/` and are upgraded on
re-runs while they're unedited (see **Upgrading**); agents are matched by name,
and each records its role in its metadata (`metadata.myAiOrg.role`), which is
how skills and credentials find it.

There's one exception. An agent created by Paperclip's own onboarding wizard
is bound to an "AI connection", and Paperclip won't move a bound agent to
another provider's runtime. There's no way to unbind it, and binding a Claude
connection runs into Paperclip's broken subscription check (see **Gotchas**).
So if you onboarded through the UI with codex, `paperclip-org.sh` fixes that
agent's role and title but leaves it on codex. Installs made with
`install.sh` never go through the wizard, so they don't have this problem.

You don't need to finish the onboarding wizard. Paperclip only sends you there
while no company exists, and `paperclip-org.sh` creates one through the API.

### The DevOps agent

Give it a `claude_local` (or `codex_local`) adapter with **no environment**,
so it runs inside the Paperclip container as the `paperclip` user. Point its
working directory at this repo's checkout there (`~/code/<org>/<repo>`). It
then has:

- `pixels`, preconfigured for the `agents` project through the restricted
  certificate;
- `newbox.sh`, which works there as written; it authorizes both your key and
  Paperclip's on every new box;
- `seed-agent-auth.sh`, which copies the container's own claude / codex / gh
  credentials into the boxes it creates.

`CLAUDE.md` in this repo is written for it, with the provisioning steps and
the rules about what goes into the repo. Its normal tool is `newproject.sh`,
which does the box, the SSH environment and the Product Manager in one go. `newbox.sh` on
its own is for boxes that aren't projects.

## Dev base image

Project boxes are clones of one template: the `base` container's `ready`
checkpoint. [pixels](https://github.com/deevus/pixels) drives the lifecycle
through the Incus API. It snapshots, clones, and can put an nftables egress
allowlist around each container.

Tools inside the image are managed by mise, so versions live in one manifest
(`/home/pixel/.config/mise/config.toml`, written by `base-setup.sh`) rather
than being scattered across install commands.

The image carries both the control planes (herdr, T3 Code) and the agents they
drive (`claude-code`, `codex`, `opencode`). The agents are declared explicitly
because `provision.devtools` is off. pixels would otherwise have installed
that set, and without them T3 Code connects to a box with no providers and
shows an empty shell.

### Why Debian, not Alpine or NixOS

The toolchain decides this. Every tool here is a prebuilt binary fetched at
runtime, and only one of them is portable:

| Tool | Linux build | musl (Alpine) | NixOS |
|------|-------------|---------------|-------|
| herdr | static-pie musl | works | works |
| t3    | dynamic, needs `GLIBC_2.28`+ | **no** | needs `nix-ld` |
| mise runtimes | prebuilt glibc node/python | **no** | needs `nix-ld` |

`t3` links `/lib64/ld-linux-x86-64.so.2` and bundles only
`@yuuang/ffi-rs-linux-x64-gnu`. There is no musl build to fall back to, and
its installer picks on `uname -s`/`uname -m` alone. Alpine would lose t3
entirely to save ~80MB. NixOS fails for the same reason (no
`/lib64/ld-linux-x86-64.so.2`), and since mise would still be managing the
toolchain, its declarative half would only cover git, openssh and nix-ld.

Debian 13 ships a newer git than Ubuntu 24.04 (2.47 vs 2.43). Change
`defaults.image` in `pixels-config.toml` to switch.

### Updating the image

`./install.sh` does this for you whenever `scripts/base-setup.sh` has changed
(see **Upgrading**). By hand: `base-setup.sh` is idempotent, so updating means
re-running it on the template and taking a fresh checkpoint. Existing boxes are unaffected; they are
already-diverged clones.

```
pixels start base || true                          # errors if already running
incus file push scripts/base-setup.sh px-base/root/base-setup.sh --project agents
incus exec px-base --project agents -- bash /root/base-setup.sh
incus exec px-base --project agents -- bash -c 'rm -f /root/base-setup.sh /etc/ssh/ssh_host_*'
pixels checkpoint delete base ready
pixels checkpoint create base --label ready
```

`gh`, `herdr` and `node` track `latest`. **t3 is pinned by exact version**,
because it is installed from a release tarball URL rather than a registry.
Bump `T3_VERSION` at the top of `base-setup.sh` and re-run. Check
<https://github.com/pingdotgg/t3code/releases> for the current one.

## Project boxes

```
scripts/newbox.sh foo                                  # clone -> keys -> ssh -> creds -> herdr
scripts/newbox.sh foo --repo org/repo                  # ...with a repo checked out
scripts/newbox.sh foo --repo org/api --repo org/web    # ...several
scripts/newbox.sh foo --egress agent                   # ...with the outbound allowlist on
scripts/newbox.sh foo --no-auth                        # ...without seeding agent credentials

ssh px-foo                                       # pixel@px-foo.incus
pixels console foo                               # no SSH at all; Incus exec API
pixels list / pixels destroy foo
```

`newbox.sh` runs the same from the host and from the Paperclip container.
pixels' config decides which daemon and project it talks to. A clone carries
the template's `authorized_keys`, so the script adds its caller's key, plus
any listed in `~/.config/pixels/authorized_keys`. `paperclip-up.sh` lists
each side's key in the other's file, so a box made by either is reachable by
both. Boxes that predate that need the key added by hand.

### Repo layout

`--repo org/name` is repeatable and checks out to `~/code/<org>/<name>` inside
the box, mirroring the host. Keeping the org level matters once a box holds
more than one repo: paths match muscle memory, anything in a repo that refers
to a sibling by relative path still resolves, and two repos sharing a name in
different orgs do not collide. Each clone with a `mise.toml` is trusted and
its toolchain installed.

A per-project `[env]` in a repo's `mise.toml` (`_.path = ["bin"]` and the
like) is applied by mise's activate hook, which fires in interactive shells
only. `ssh box 'some-tool …'` will not see it. Use `mise exec --` for
non-interactive invocations, which is also how agents driven over SSH run:

```
ssh px-foo 'cd ~/code/org/repo && mise exec -- just test'
```

Two more things that bite on a clean box:

- Dependencies a repo installs outside its `mise.toml`, such as a
  `requirements.txt` that only CI reads, are missing until installed by hand.
- Manual pins a repo documents (a setuptools cap inside a tool's venv, say)
  get undone by any `mise install` that rebuilds that venv.

Put the fix in the repo, not in the image.

### How SSH reaches a box

Boxes live on the NAT'd `incusbr0` bridge, and the bridge's dnsmasq answers
for `<name>.incus`. The SSH config differs only in how a caller gets there:

| Caller | `px-*` block | Why |
|--------|--------------|-----|
| the Incus host | `HostName %h.incus` | on the bridge; `host-setup.sh` points systemd-resolved's `~incus` domain at the bridge (the unit from the Incus docs) |
| the Paperclip container | `HostName %h.incus` | dnsmasq is already its resolver |
| a laptop, remote box layout | `ProxyCommand ssh box 'nc $(dig … @bridge) 22'` | not on the bridge; hop through the box |

Host keys are kept in `~/.ssh/known_hosts.pixels`. Every clone regenerates its
host key and names get recycled, so `newbox.sh` clears the stale entry on each
create. Do not set `UserKnownHostsFile=/dev/null` to avoid that. `herdr
machine add` fails with "lost connection to server" when host keys are not
persisted, and Paperclip's strict host key checking needs them too.

Agent forwarding is deliberately off. These containers run AI coding agents,
and a forwarded agent would hand them your keys. Use the seeded `gh` token or
a scoped deploy key inside the box.

### Connecting T3 Code to a box

```
scripts/t3-connect.sh px-foo
```

That starts a t3 server on the box, tunnels it to `localhost:3799`, mints a
pairing token and opens the client on the pairing URL. The server binds
**loopback inside the container**, so it is reachable only through the
tunnel, not from other containers on the bridge or from the LAN. (`t3 serve
--host 0.0.0.0`, which the docs suggest, exposes it to both.)

The script works around two things:

- `t3 pair` prints a URL pointing at the container's bridge IP, which the
  client may not be able to route to. The script keeps the token and rebuilds
  the URL against the tunnel.
- `ssh -f -N` backgrounds itself but inherits stdout, which hangs anything
  capturing the script's output. The script detaches the tunnel's descriptors.

Drop the tunnel with `pkill -f 'ssh -f -N -L 3799:127.0.0.1:3773'`.

The T3 Code desktop app can do the same through Settings → Connections → Add
environment → SSH, but that can't be scripted: T3 keeps its environments in an
encrypted `connection-catalog.json` and has no add command. Enter the alias
(`px-foo`), **not** an IP. An IP does not match the `Host px-*` pattern, so
the block above never applies. Behind a ProxyCommand that fails like this:

```
Could not prepare the SSH environment: ... SshCommandError:
ssh: connect to host 10.x.y.z port 22: Operation timed out
```

The app shells out to the system `ssh` with `BatchMode`, so the hop has to
work without prompts. On first connect it installs its runtime to
`~/.t3/runtime` on the box, which is why `curl`, `tar` and `sha256sum` are in
the base image. Pairing from a phone needs the phone to reach the box, which
wants Tailscale in the container (`t3 pair --tailscale`).

### Agent credentials

`claude`, `codex` and `gh` are signed in on every box at creation, so there's
nothing to log into per box. `gh` matters for `--repo`: the template ships the
CLI but no token, so without seeding, a fresh box cannot clone a private repo.

**Claude uses one long-lived token, not copied logins.** A Claude Code login
(`~/.claude/.credentials.json`) rotates its refresh token on every refresh.
Copy it to three machines, and the first copy to refresh logs the other two
out ("OAuth session expired and could not be refreshed"), usually within hours.
Instead:

```
claude setup-token          # once, in a real terminal: browser sign-in, prints a token
scripts/set-claude-token.sh       # paste it at the hidden prompt
```

`claude setup-token` mints a long-lived token billed to the same
subscription. Claude reads it from `CLAUDE_CODE_OAUTH_TOKEN`, and it never
rotates, so one token serves everything. `set-claude-token.sh` checks that
claude accepts it, then puts it in four places:

| Where | How it's used |
|-------|---------------|
| `~/.config/my-ai-org/claude-oauth-token` on the host (600) | the copy every other script reads; re-used by `paperclip-up.sh` on a rebuild |
| the same path in the Paperclip container | that container's own `claude`, and boxes the DevOps agent creates |
| Paperclip company secret `claude-oauth-token` | bound as `CLAUDE_CODE_OAUTH_TOKEN` on every SSH and local environment, so every agent run gets it; `newproject.sh` binds it on new environments |
| every running box | the same file, plus a hook at the top of `~/.bashrc` (and in `~/.profile`) that exports it, including for non-interactive `ssh box cmd` |

Re-run it with a new token to rotate. The secret binding follows the latest
version, so nothing needs re-binding.

**codex** still copies `~/.codex/auth.json`: it has no long-lived token for
ChatGPT sign-in, only `--with-api-key`, which is a different billing path.
ChatGPT logins rotate refresh tokens too, so copies can log each other out the
same way. Where that bites, give each place its own `codex login
--device-auth`. Paperclip already requires its own separate codex sign-in for
this reason.

`seed-agent-auth.sh` installs all three, streaming over SSH (or `incus exec`,
for the Paperclip container). Nothing goes to a temp file and no value is
printed. `--only claude|codex|gh` limits it to one. The `gh` token comes from
`gh auth token` and goes over stdin, never as an argv value that would show in
the box's process list.

Credentials are seeded per box rather than baked into the `ready` checkpoint.
That keeps the template credential-free, and nothing long-lived sits in a
snapshot every clone inherits.

**This hands live subscription tokens to anything with a shell on the box.**
That is usually what you want on a box you drive yourself, and not what you
want around an untrusted unattended agent. `scripts/newbox.sh foo --no-auth` skips
it, and `scripts/seed-agent-auth.sh px-foo` adds them later.

### Egress allowlist

`--egress agent` installs an nftables ruleset (default `policy drop`, with the
resolved allowlist in an `allowed_v4` set). It also swaps the blanket
`NOPASSWD` sudo for a restricted one, so an agent cannot switch the firewall
off. Package installs then go through the wrapper rather than apt directly:

```
sudo safe-apt update
```

The stock preset covers the AI APIs, npm/PyPI/crates/Go, GitHub and the Ubuntu
mirrors. `pixels-config.toml` adds what this setup needs on top:

- `deb.debian.org` and `security.debian.org`, because the preset has only
  Ubuntu mirrors;
- `herdr.dev` and `t3.codes`, without which `herdr machine add` and t3 pairing
  fail.

The allowlist is IPv4-only. The chain is `policy drop` on an `inet` table, so
IPv6 is dropped rather than allowed through.

## Gotchas

Each of these was found the hard way and will look like unrelated breakage
if you hit it cold.

**pixels 0.6.2 silently half-provisions.** Leave `provision.devtools = false`.
With it enabled, the Incus backend pushes
`/home/pixel/.config/mise/config.toml` without creating the parent directory.
The Incus file API does not create parents, and the error is discarded by
`_ = err` in `sandbox/incus/backend.go`. Provisioning aborts *before*
`rc.local` runs, so the container comes up with no `pixel` user and no sshd,
while `pixels create` still reports success.

**`pixels exec` with stdin attached allocates a PTY.** Piped input is echoed
back and EOF never arrives, so `… | pixels exec box -- sh -c 'cat > f'` hangs
forever. Pass data as arguments (as `newbox.sh` does for keys), or use
`incus file push`.

**t3 must not be installed from npm.** mise's npm backend does not fetch
node-pty's native module. `npm:t3` yields a `t3` that answers `t3 --version`
but dies on `t3 serve` with "Failed to load native module: pty.node". The
vendor's release tarball ships `build/Release/pty.node`, so it is installed
through mise's `http` backend with `bin_path` pointing at the extracted
directory.

**Non-interactive SSH sees no mise activation.** `ssh host cmd` is neither a
login nor an interactive shell, and Debian's `.bashrc` returns early, so
`base-setup.sh` puts the mise shims on PATH via `/etc/environment` (pam_env).
That is what makes `herdr`, T3 and Paperclip's SSH runs find their tools. The
Paperclip container does the same for its systemd user service through
`~/.config/environment.d`.

**Agents on SSH environments need `engine: "cli"`.** `claude_local` and
`codex_local` default to their ACP engine, which supports sandbox targets
only. On an SSH environment, every run fails in under a second with
`adapter_engine_unavailable`: "Claude ACP supports sandbox remote targets
only…". `newproject.sh` sets `adapterConfig.engine = "cli"`. For an agent
made by hand, set it in the agent's adapter settings.

**Distro herdr may predate `herdr machine`.** Registration arrived in 0.9.
Older packaged builds (0.8.x) only have `herdr --remote <target>`, which needs
no registration at all. `newbox.sh` detects which one it has and treats
registration as best-effort, so herdr can never fail a box.

**Copied Claude logins log each other out.** Claude rotates its refresh token
on every refresh, so copies of one `~/.claude/.credentials.json` on several
machines fail with "OAuth session expired and could not be refreshed" as soon
as any one of them refreshes. Use the long-lived token (**Agent
credentials**).

**Paperclip can't verify a Claude subscription connection** (as of
2026.1001). Its check calls Anthropic's usage endpoint without a Claude Code
`User-Agent`, gets 429, and reports "Could not verify the local subscription".
Nothing here depends on that flow: agents authenticate with the token bound
on their environment.

**mise must trust Paperclip's staging directory.** Each agent run on a box
happens in a fresh directory with the repo's `mise.toml` copied in. mise
refuses untrusted config, and Paperclip's callback bridge starts `node`
through the shims, so every issue-bound run died with "Config files in … are
not trusted" before the agent started. `base-setup.sh` sets
`trusted_config_paths` to the staging root.

**A run started without an issue can't write to issues.** A bare "wake now"
(the agent's Run button, or `POST /agents/:id/wakeup` with no issue) runs
with no issue scope. Every comment or status change it makes gets 403
(`cross_issue_…`), and it gets an empty fallback workspace instead of the
project's. Wake agents through their issues: assign one, or comment on it.

**`exit` under `su -` in a Debian container returns 1.** A login shell runs
`~/.bash_logout` on `exit`, and Debian's stock one ends with a test for a
`clear_console` program the container doesn't have. The failed test becomes
the shell's status, so `su - user -c '…; exit 0'` reports failure. Scripts
that run snippets that way (`incus exec … su - paperclip -c`) use if/else
instead of an early `exit`.

**`incus exec` eats the input of the loop around it.** It reads stdin, so
`while read line; do incus exec …; done < file` processes only the first line.
Read loops on another file descriptor (`read <&3 … done 3< file`).

**Paperclip imports local skills only from approved directories:** its
company managed-skill directory (`~/.paperclip/instances/default/skills/<company>/`)
or a project workspace. Anywhere else fails with
`skill_workspace_boundary_denied`, which is why `skills-sync.sh` copies skills
there first.

**Restricted projects block snapshots by default.** Without
`restricted.snapshots=allow`, `pixels checkpoint create` fails, and so does
every `--from base:ready` clone.

**AppImages work without SUID `fusermount`.** They print `trying to
unshare...` and fall back to user namespaces. That's expected, not a failure.

One non-issue worth recording, since it looks alarming: under `--egress
agent`, `sudo apt-get update` fails with a password prompt. That's not the
firewall. pixels deliberately replaces blanket `NOPASSWD` sudo with a
restricted list; use `sudo safe-apt` instead.

## Working with Incus directly

Everything above goes through pixels and the scripts. These are the underlying
commands, for one-off containers and for digging into what pixels built. Add
`--project agents` for project boxes.

```
incus list --all-projects                 # everything, both projects
incus snapshot create px-foo clean --project agents     # before letting an agent loose
incus snapshot restore px-foo clean --project agents
incus exec px-foo --project agents -- bash
incus config set px-foo limits.memory=8GiB --project agents   # counts against the project cap
incus file push ./thing px-foo/root/ --project agents
```

Need a VM instead (kernel isolation, awkward Docker stacks)? Restricted
projects allow VMs, but not the low-level options:

```
incus launch images:debian/13 vm-foo --vm --project agents -c limits.cpu=4 -c limits.memory=8GiB
```

## Maintenance

- **Paperclip:** `paperclipai update` inside the container. It keeps the
  previous payload (`--rollback`) and backs up the DB first. Snapshot the whole
  container before big jumps: `incus snapshot create paperclip pre-update`.
- **Paperclip data** is the one stateful thing here. It takes its own daily DB
  dumps in `~/.paperclip/instances/default/data/backups`. For a full copy,
  `incus export paperclip paperclip.tar.gz`.
- **Project boxes** are cheap to rebuild with `newbox.sh`. What's worth saving
  is whatever has not been pushed to its remote yet.
- **Dev image:** see **Updating the image**. Host updates don't touch
  containers.

## Remote box layout (optional)

The scripts above assume Incus runs on the machine you sit at. The original
layout of this repo is a separate headless box, driven from a laptop. It is
still supported:

1. Install Debian 13 netinst on the box: no desktop, SSH server ticked, with a
   spare raw partition for the ZFS pool. **Disable Secure Boot**, because the
   ZFS DKMS module won't load with it on.
2. From the laptop: `NO_TAILSCALE=1 scripts/bootstrap.sh <ip> <user> /dev/<partition>`.
   It copies your key, runs `firstboot.sh` as root (ZFS, Incus on the ZFS pool,
   Avahi, Tailscale, key-only sshd, a 4GB ARC cap, nc/dig for the SSH hop),
   registers the box as the Incus remote `box`, and reboots it.
   `firstboot.sh` serves the API on `[::]:8443`, since the laptop has to reach it.
3. On the box: `NO_DNS=1 scripts/host-setup.sh` to create the `agents` project.
   There's no mise there, so it stops after that, and leaves the existing API
   address alone.
4. On the laptop: `BOX_HOST=<box>.local scripts/laptop-setup.sh` for pixels and the
   ProxyCommand SSH block.
5. Build the base image with the commands under **Updating the image**, with `box:` in front of
   instance names (`incus exec box:px-base --project agents …`).

`firstboot.sh` also creates a `dev` profile and two shared volumes (`cache`,
`repos`) from before pixels. Nothing uses them; they are there for
hand-rolled containers that want storage shared with siblings.

Paperclip is not scripted for this layout yet. `paperclip-up.sh` assumes the
local Incus socket, and it seeds credentials from the machine it runs on.

If bootstrap did not finish the remote step: on the box run `incus config
trust add laptop`, then on the laptop `incus remote add box <box>.local
--token <token> --accept-certificate`. Tokens are single-use.
