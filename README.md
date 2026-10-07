# my-ai-org: many coding agents, one terminal

## Why this exists

This is for people with more repos than they can keep track of, who want to
run several coding agents at once and see all of them in one place. It is
deliberately small. You get:

- **One box per repo.** Each repo gets its own Incus container (`px-<name>`),
  so agents in one cannot touch another, or your machine.
- **One worktree per task.** Inside a box, every task gets its own git
  worktree and branch, so several agents can work on one repo without
  colliding.
- **One terminal that shows everything.** [herdr](https://herdr.dev) runs on
  the host: one workspace per box, one tab per task, and a sidebar that shows
  which agent is working, which is blocked waiting for you, and which is done.
  You SSH or mosh in, run `herdr`, and it's all there. Detach, and the agents
  keep going.
- **Subscriptions, never API keys.** Agents are the official `claude` and
  `codex` CLIs on your Claude and ChatGPT subscriptions. Nothing here sets
  `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`, and the scripts refuse to run if
  one is set.

The repo holds no secrets and nothing project-specific. Credentials come
from the machine running the scripts, and your repo list lives in the
gitignored `local/`.

## Quick start

### 1. Before you start

You need:

- a Linux machine running **Debian/Ubuntu, Arch or Fedora**, with `sudo`. The
  installer adds everything else: Incus, mise, gh, jq, git, herdr, mosh.
  This machine is "the host": the boxes and herdr run there, and you connect
  to it from anywhere.
- a **GitHub account** that can see your repos.
- a **Claude subscription** (Pro or Max), and a **ChatGPT plan** if you want
  codex as well.

### 2. Get the repo

```
git clone https://github.com/<org>/<this-repo>.git
cd <this-repo>
```

### 3. Run the installer

```
./install.sh
```

Run it in a real terminal; it prompts for sudo and sign-ins. It works in
phases and skips what is already done:

| Phase | What happens |
|-------|--------------|
| 0. prereqs | installs Incus, mise, gh, jq, git, mosh and herdr; sets up subordinate IDs; starts and initialises Incus; joins `incus-admin` (and carries on under it, no logout); creates `~/.ssh/id_ed25519` if missing |
| 1. sign-ins | `gh auth login`, and the long-lived Claude token (`claude setup-token`, then a hidden paste prompt), each only if missing |
| 2. host | `scripts/host-setup.sh`: the restricted `agents` Incus project, `.incus` DNS, pixels |
| 3. base image | the template every box is cloned from, about 3 minutes the first time |
| 4. boxes | `scripts/boxes.sh local/boxes.manifest`: one box per line |
| 5. task | links `scripts/task` to `~/.local/bin/task` |

**The first run stops after phase 4 writes your repo list.** Open
`local/boxes.manifest`, uncomment the repos you want, then run it again:

```
$EDITOR local/boxes.manifest
./install.sh               # or just: scripts/boxes.sh
```

Options: `--boxes FILE`, `--no-boxes`.

### 4. Sign codex in, once per box

```
scripts/codex-login.sh <box>
```

It prints a URL and a code; open the URL on any device. Skip this if you
only use claude. (Why per box: **Credentials**.)

### 5. Upgrading

```
git pull && ./install.sh
```

The template rebuilds when `scripts/base-setup.sh` has changed (its checksum
is stored in the template), and new manifest lines become boxes. Existing
boxes are never rebuilt for you: they hold your work. To rebuild one, push
its branches, `pixels destroy <box>`, and run `scripts/boxes.sh` again.

### Coming from the Paperclip version

Earlier versions of this repo ran Paperclip in its own container, with T3
Code and herdr inside every box. The installer doesn't remove any of that
for you, because some of it holds data. Once you've saved what you want:

```
# 1. Your repo list: projects.manifest becomes boxes.manifest
#    (same lines, minus `defaults` and `--type liaison`)
$EDITOR local/boxes.manifest

# 2. Paperclip: its container (and database), its Incus certificate, the
#    Incus API it used on the bridge, and its SSH key in new boxes
incus delete paperclip --project default            # stop it first if running
incus config trust list                             # remove the `paperclip` entry:
incus config trust remove <fingerprint>
incus config unset core.https_address
rm ~/.config/pixels/authorized_keys                 # if it lists only paperclip@paperclip

# 3. The template and boxes: they carry opencode, t3, herdr and the old
#    egress list. Check each box for unpushed work first.
pixels destroy base --force
pixels destroy <box> --force                        # for each box
./install.sh                                        # rebuilds base and the boxes
scripts/codex-login.sh <box>                        # for each box that uses codex
```

If you set up the GitHub App for Paperclip's reviewers, delete it in GitHub's
settings, along with its key in `~/.config/my-ai-org/github-app`.

## Daily use

### Attach

```
herdr                       # on the host
ssh -t <host> herdr         # from another machine
mosh <host> -- herdr        # from a phone or a flaky network
```

Detach with `ctrl+b q`. Agents keep running in herdr's server, and `herdr`
reattaches. `task` starts the server if it is not running, so you can start
tasks before you ever open the UI.

### Tasks

```
task new <box> <task> [claude|codex]      # worktree + branch + herdr tab running the agent
task rm  <box> <task> [--force]           # close the tab, remove the worktree, keep the branch
task ls                                   # every task in every running box, and its agent's state
```

- `<box>` is the name from your manifest (`foo` for `px-foo`). It is also
  the herdr workspace.
- `<task>` is the branch name, the worktree directory and the tab label, so
  it is limited to lowercase letters, digits, `-`, `_` and `.`.
- The worktree is `~/worktrees/<repo>/<task>` in the box, branched from the
  remote's default branch right after a `git fetch`. An existing branch of
  that name is checked out rather than recreated.
- A box with several repos needs `--repo <name>` to say which one.
- `task new` on a task that already has a worktree reopens it. If its tab is
  still open, it says so and does nothing.
- `task rm` refuses a worktree with uncommitted or untracked changes unless
  you pass `--force`. It never deletes the branch.
- When the agent exits, the tab drops back to a host shell. Press up and
  Enter to start it again.
- `HERDR_SESSION=<name> task ...` targets a named herdr session instead of
  the default one.

The sidebar states mean:

| State | Meaning |
|-------|---------|
| working | the agent is mid-turn |
| blocked | it is showing an approval, question or trust prompt: it needs you |
| done | it finished while you were looking elsewhere |
| idle | it is waiting for input, and you have seen it |
| unknown | codex only: herdr cannot tell whether a turn ended (see herdr's docs) |

### Add a repo

Add a line to `local/boxes.manifest` and run `scripts/boxes.sh`. Or make
one directly:

```
scripts/newbox.sh foo --repo org/repo
scripts/codex-login.sh foo                  # if you use codex there
task new foo first-task
```

`scripts/list-repos.sh` writes a fresh menu of every repo you can see (to
`<file>.new` if the manifest exists, so you can diff the two).

## Architecture

```
 the host
 ┌────────────────────────────────────────────────────────────────────────────┐
 │  you ──ssh/mosh──► herdr (one server, one session)                         │
 │                     workspace "foo"           workspace "bar"              │
 │                      tab fix-login ─┐          tab new-api ─┐              │
 │                      tab refactor ──┤                       │              │
 │                                     │ HERDR_AGENT=claude    │              │
 │                                     │ incus exec px-foo …   │ incus exec … │
 │  ┌─ Incus project `agents` (restricted, capped) ────────────┼───────────┐  │
 │  │  px-base  (template, checkpoint `ready`)                 │           │  │
 │  │  px-foo   ~/code/org/foo            ◄────────────────────┘           │  │
 │  │           ~/worktrees/foo/fix-login   claude                         │  │
 │  │           ~/worktrees/foo/refactor    codex                          │  │
 │  │  px-bar   ~/code/org/bar, ~/worktrees/bar/new-api                    │  │
 │  └──────────────────────────────────────────────────────────────────────┘  │
 └────────────────────────────────────────────────────────────────────────────┘
```

### How a task pane works

Each tab runs, in a host shell:

```
HERDR_AGENT=claude incus exec px-foo --project agents --user <uid> --group <uid> \
  --env HOME=/home/pixel --cwd /home/pixel/worktrees/foo/fix-login -- bash -lc 'exec claude'
```

- **`incus exec`, not SSH or `pixels console`.** One layer, no keys, no
  sshd, and no second multiplexer: herdr owns persistence. pixels' own
  console uses zmx sessions, which would be a multiplexer inside a
  multiplexer.
- **`HERDR_AGENT`.** herdr finds agents by their process, and here the
  pane's foreground process is `incus`. The variable tells herdr which agent's
  screen rules to use for that command, and with it the idle / working /
  blocked states are read from the screen as usual. It has to be set on the
  host side; set inside the box, herdr cannot see it.
- **`bash -lc`.** `incus exec --user` starts the program with no shell
  startup at all. A login shell reads `~/.profile` (the Claude token hook) and
  `/etc/profile.d` (mise's shims).
- **The `pixel` UID is looked up** in each box (`id -u pixel`), not assumed.

Tested with herdr 0.8.2, which already honours `HERDR_AGENT`.

### What persists

| Event | What survives |
|-------|---------------|
| you detach, or your connection drops | everything; agents keep running |
| herdr server stops, or the host reboots | worktrees, branches and boxes. The agent processes do not: run `task new <box> <task>` to reopen each one, then `/resume` in claude or `codex resume` |
| `task rm` | the branch |
| `pixels destroy <box>` | nothing that was not pushed |

herdr's own session restore resumes agents through integrations that report
from inside the agent, and those cannot reach the host's herdr socket from a
box. That is why a restart needs the `task new` step.

## Credentials

**Subscriptions only.** `newbox.sh`, `task new` and the installer refuse to
run if `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` is set on the host, or in a
box's login environment. Check what an agent is using with:

```
incus exec px-foo --project agents -- su - pixel -c 'claude auth status; codex login status'
```

`claude auth status` should say `"authMethod": "oauth_token"`, and codex
`Logged in using ChatGPT`.

**Claude uses one long-lived token, not copied logins.** A Claude Code login
(`~/.claude/.credentials.json`) rotates its refresh token on every refresh.
Copy it to three machines, and the first copy to refresh logs the other two
out ("OAuth session expired and could not be refreshed"), usually within
hours. Cloning boxes from a signed-in template has the same effect. Instead:

```
claude setup-token                 # once, in a real terminal: browser sign-in, prints a token
scripts/set-claude-token.sh        # paste it at the hidden prompt
```

`claude setup-token` mints a long-lived token billed to the same
subscription. Claude reads it from `CLAUDE_CODE_OAUTH_TOKEN`, and it never
rotates, so one token serves every box. `set-claude-token.sh` checks that
claude accepts it, saves it at `~/.config/my-ai-org/claude-oauth-token`
(mode 600), and installs it in every running box. Each box keeps it in the
same path, with a hook at the top of `~/.bashrc` and in `~/.profile` that
exports it. Re-run the script with a new token to rotate.

**codex signs in per box.** A ChatGPT login rotates its refresh token too,
and codex has no long-lived token except an API key. So each box gets its own
`codex login --device-auth` through `scripts/codex-login.sh <box>`, and no
box's login can invalidate another's.

**gh** is seeded from `gh auth token` on the host, over stdin (never argv,
which would show in the box's process list), so boxes can clone and push.

Credentials are seeded per box rather than baked into the template, so the
`ready` checkpoint holds none. `scripts/newbox.sh foo --no-auth` makes a box
without them, and `scripts/seed-agent-auth.sh px-foo` adds them later.
**Anything with a shell on a box can read its tokens**, which is what you
want on a box you drive yourself.

## Egress allowlist

Boxes are created with pixels' `agent` egress: an nftables ruleset with a
`policy drop` and an allowlist. `newbox.sh --egress unrestricted` opts out,
and `pixels network set <box> unrestricted|agent` changes it later.

The stock preset covers `api.anthropic.com`, `api.openai.com`, GitHub, the
npm/PyPI/crates/Go registries and the Ubuntu mirrors.
`scripts/pixels-config.toml` adds:

| Domain | Why |
|--------|-----|
| `deb.debian.org`, `security.debian.org` | the preset has only Ubuntu mirrors, and the boxes are Debian |
| `chatgpt.com` | codex signed in with ChatGPT sends its requests here, not to `api.openai.com` |
| `auth.openai.com` | codex's device sign-in and token refresh |

claude, authenticated with the token, needs nothing beyond the preset.
`pixels network allow <box> <domain>` adds one to a single box.

**The allowlist is kept fresh by the base image.** pixels resolves each
domain once, when egress is set. CDN-backed hosts move: `github.com`
answered with a new address within the hour, and every `git fetch` hung.
So every box ships GitHub's published IPv4 ranges
(`/etc/my-ai-org/egress-cidrs`, from `api.github.com/meta` when the template
was built), and a timer (`my-ai-org-egress-refresh.timer`) re-resolves the
domain list every minute, adding new addresses without flushing anything.
It does nothing on a box with unrestricted egress. `pixels network set`
rebuilds the ruleset from scratch, dropping the GitHub ranges until the next
tick, so `newbox.sh` runs the refresh straight after setting egress.

The allowlist is IPv4-only. The chain is `policy drop` on an `inet` table,
so IPv6 is dropped rather than allowed through.

Under `agent` egress, pixels also swaps the blanket `NOPASSWD` sudo for a
restricted list, so an agent cannot switch the firewall off. Package
installs go through `sudo safe-apt …` instead of apt directly.

## Repository layout

```
install.sh                 the installer (phases above)
scripts/
  task                     start, stop and list tasks (linked as ~/.local/bin/task)
  newbox.sh                one box: clone, keys, egress, credentials, repos
  boxes.sh                 every box in a manifest that doesn't exist yet
  list-repos.sh            writes a manifest menu of every repo you can see
  codex-login.sh           codex device sign-in inside one box
  set-claude-token.sh      store the long-lived Claude token, push it to boxes
  seed-agent-auth.sh       Claude token + gh login into one box
  host-setup.sh            agents project, DNS, pixels, SSH config
  base-setup.sh            the template's toolchain (runs inside px-base)
  pixels-config.toml       box size, image and egress allowlist
  lib/box.sh               shared: run as pixel in a box, API-key guard
  bootstrap.sh, firstboot.sh   build a headless host (see the last section)
examples/boxes.manifest    the manifest format, with placeholders
local/                     your real manifest (gitignored)
```

## The `agents` project

Every box lives in a separate Incus project, so nothing done to or inside a
box can reach containers in the `default` project.
`host-setup.sh` creates it with `restricted=true`, which blocks privileged
containers, nesting, disks that are not on a managed pool, `raw.*` keys and
backups. On top of that it adds:

| Key | Value | Why |
|-----|-------|-----|
| `restricted.snapshots` | `allow` | pixels checkpoints are snapshots; restricted blocks them by default |
| `restricted.networks.access` | `incusbr0` | boxes may only join the shared bridge |
| `limits.memory` | `20GiB` | caps the whole fleet; see below |
| `limits.cpu` | `32` | sum of per-box `limits.cpu` |
| `limits.instances` | `10` | |

All of these are env knobs on `host-setup.sh` (`AGENTS_MEMORY=40GiB
./install.sh`).

**Project limits count every instance's cap, running or stopped**, the
template included. At the default 4GiB per box, 20GiB is the template plus
four boxes. When the cap is hit, creation fails with a limits error. Destroy
a box or raise the cap. Box size is `defaults.memory` and `defaults.cpu` in
`pixels-config.toml`.

## Base image

Boxes are clones of one template: the `base` container's `ready`
checkpoint. [pixels](https://github.com/deevus/pixels) drives the lifecycle
through the Incus API: it snapshots, clones, and puts the egress allowlist
around each box.

Tools inside the image are managed by mise, so versions live in one manifest
(`/home/pixel/.config/mise/config.toml`, written by `base-setup.sh`): node,
gh, `claude-code` and `codex`, all tracking `latest`. Only the official agent
CLIs are installed. The agents are declared explicitly because pixels'
`provision.devtools` is off (see **Gotchas**).

The image also marks Claude Code's first-run onboarding as done (see
**Gotchas**), and installs the egress refresh timer.

### Updating the image

`./install.sh` does this whenever `scripts/base-setup.sh` has changed. By
hand: `base-setup.sh` is idempotent, so updating means re-running it on the
template and taking a fresh checkpoint. Existing boxes are unaffected; they
are already-diverged clones. Update an agent CLI in a running box with
`mise upgrade claude-code codex` as `pixel`.

```
pixels start base || true                          # errors if already running
incus file push scripts/base-setup.sh px-base/root/base-setup.sh --project agents
incus exec px-base --project agents -- bash /root/base-setup.sh
incus exec px-base --project agents -- bash -c 'rm -f /root/base-setup.sh /etc/ssh/ssh_host_*'
pixels checkpoint delete base ready
pixels checkpoint create base --label ready
```

There is no re-authentication step: the template holds no credentials, so
a new sign-in never means a new checkpoint. To change the Claude token, run
`scripts/set-claude-token.sh`. To sign codex in again, run
`scripts/codex-login.sh <box>`.

### Why Debian

mise installs prebuilt glibc runtimes (node, python), which rules out Alpine
(musl) and needs `nix-ld` on NixOS. Debian 13 ships a newer git than Ubuntu
24.04. Change `defaults.image` in `pixels-config.toml` to switch.

## Boxes

```
scripts/newbox.sh foo                                  # clone -> keys -> ssh -> egress -> creds
scripts/newbox.sh foo --repo org/repo                  # ...with a repo checked out
scripts/newbox.sh foo --repo org/api --repo org/web    # ...several
scripts/newbox.sh foo --egress unrestricted            # ...without the outbound allowlist
scripts/newbox.sh foo --no-auth                        # ...without seeding credentials

ssh px-foo                                       # pixel@px-foo.incus, a plain shell
pixels list / pixels stop foo / pixels destroy foo
```

### Repo layout

`--repo org/name` is repeatable and checks out to `~/code/<org>/<name>`
inside the box. Keeping the org level matters once a box holds more than one
repo: anything that refers to a sibling by relative path still resolves, and
two repos sharing a name in different orgs do not collide. Each clone with a
`mise.toml` is trusted and its toolchain installed. Task worktrees go
alongside, in `~/worktrees/<name>/<task>`.

A repo's `[env]` in `mise.toml` is applied by mise's activate hook, which
fires in interactive shells only. Agents run in a login shell, not an
interactive one, so use `mise exec --` (or the repo's own task runner through
it) for anything that depends on it.

### SSH

`task` doesn't use SSH, but a plain shell in a box is handy. Boxes live on
the NAT'd `incusbr0` bridge, whose dnsmasq answers for `<name>.incus`;
`host-setup.sh` points systemd-resolved's `~incus` domain at the bridge and
adds a `px-*` block to `~/.ssh/config.d/pixels`. Host keys go in
`~/.ssh/known_hosts.pixels`; every clone regenerates its host key and names
get recycled, so `newbox.sh` clears the stale entry on each create.

Agent forwarding is deliberately off. These containers run AI coding agents,
and a forwarded agent would hand them your keys. Use the seeded `gh` token.

## Gotchas

Each of these was found the hard way and will look like unrelated breakage
if you hit it cold.

**`git fetch` in a box hangs until it times out** (or codex says
"Reconnecting... 5/5") under `agent` egress. The allowlist holds the IPs a
domain resolved to when egress was set, and CDN-backed hosts move. The base
image's refresh timer fixes it (**Egress allowlist**). On a box made from an
older template, run `pixels network set <box> agent` to re-resolve once.

**codex hangs on "Reconnecting..." under `agent` egress even with
`api.openai.com` allowed.** A ChatGPT-signed-in codex talks to `chatgpt.com`
and refreshes at `auth.openai.com`; `api.openai.com` is the API-key path.
Both are in `pixels-config.toml`.

**Claude Code shows a theme picker and then "Select login method" although
the token is set.** Its first interactive start runs onboarding unless
`~/.claude.json` has `hasCompletedOnboarding: true`. `CLAUDE_CODE_OAUTH_TOKEN`
alone does not skip it. `base-setup.sh` sets the flag.

**Every new task opens on a "trust this folder" prompt.** Both agents ask
once per directory, and each worktree is a new one. `task new` pre-marks the
worktree trusted (`~/.claude.json` and `~/.codex/config.toml`). A claude
running in another task can rewrite `~/.claude.json` and drop the flag; the
worst case is that prompt, which herdr shows as blocked.

**herdr shows a pane as a plain terminal, with no agent state.** The agent
runs behind `incus exec`, so herdr can't find it by process. Set
`HERDR_AGENT=<agent>` on the command in the pane (as `task` does). Check with
`herdr agent explain <pane>`.

**A herdr workspace disappears when its last tab closes.** That's herdr;
`task new` recreates it.

**`exit` in a Debian login shell returns 1.** A login shell runs
`~/.bash_logout` on `exit`, and Debian's stock one ends with a test for a
`clear_console` program the container doesn't have. The failed test becomes
the shell's status, so `bash -lc '…; exit 0'` (and `su - user -c`) reports
failure. Scripts here use if/else instead of an early `exit`.

**`incus exec` eats the input of the loop around it.** It reads stdin, so
`while read line; do incus exec …; done < file` processes only the first
line. `lib/box.sh` passes `-T`, and loops read on another descriptor.

**pixels 0.6.2 silently half-provisions.** Leave `provision.devtools =
false`. With it enabled, the Incus backend pushes
`/home/pixel/.config/mise/config.toml` without creating the parent
directory. The Incus file API does not create parents, and the error is
discarded by `_ = err` in `sandbox/incus/backend.go`. Provisioning aborts
*before* `rc.local` runs, so the container comes up with no `pixel` user and
no sshd, while `pixels create` still reports success.

**`pixels exec` with stdin attached allocates a PTY.** Piped input is echoed
back and EOF never arrives, so `… | pixels exec box -- sh -c 'cat > f'`
hangs forever. Pass data as arguments (as `newbox.sh` does for keys), or use
`incus file push`.

**Non-interactive SSH sees no mise activation.** `ssh host cmd` is neither a
login nor an interactive shell, and Debian's `.bashrc` returns early, so
`base-setup.sh` puts the mise shims on PATH via `/etc/environment` (pam_env).

**Copied Claude logins log each other out.** See **Credentials**: use the
long-lived token, and never clone a box from a signed-in template.

**Restricted projects block snapshots by default.** Without
`restricted.snapshots=allow`, `pixels checkpoint create` fails, and so does
every `--from base:ready` clone.

One non-issue worth recording, since it looks alarming: under `agent`
egress, `sudo apt-get update` fails with a password prompt. That's not the
firewall. pixels deliberately replaces blanket `NOPASSWD` sudo with a
restricted list; use `sudo safe-apt` instead.

## Working with Incus directly

Everything above goes through pixels and the scripts. These are the
underlying commands, for digging into what pixels built. Add `--project
agents` for boxes.

```
incus list --all-projects
incus snapshot create px-foo clean --project agents      # before letting an agent loose
incus snapshot restore px-foo clean --project agents
incus exec px-foo --project agents -- su - pixel
incus config set px-foo limits.memory=8GiB --project agents   # counts against the project cap
```

## Remote box layout (optional)

The installer assumes you run it on the host. To build a headless host from
scratch first:

1. Install Debian 13 netinst on the box: no desktop, SSH server ticked, with
   a spare raw partition for the ZFS pool. **Disable Secure Boot**, because
   the ZFS DKMS module won't load with it on.
2. From your laptop: `NO_TAILSCALE=1 scripts/bootstrap.sh <ip> <user>
   /dev/<partition>`. It copies your key, runs `firstboot.sh` as root (ZFS,
   Incus on the ZFS pool, Avahi, Tailscale, key-only sshd, a 4GB ARC cap),
   and reboots the box. It also registers the box as an Incus remote on the
   laptop, which you only need for running `incus` from there.
3. SSH in, clone this repo on the box, and run `./install.sh` there.

From then on, `ssh -t <box>.local herdr` or `mosh <box>.local -- herdr`.

`firstboot.sh` serves the Incus API on `[::]:8443` for that laptop remote.
Unset it (`incus config unset core.https_address`) if you don't use it.
