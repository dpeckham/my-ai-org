#!/usr/bin/env bash
# Spin up a repo box from the dev base image.
#
#   scripts/newbox.sh <name> [--repo org/repo]... [--egress agent|unrestricted] [--no-auth]
#
# Clones px-base's `ready` checkpoint (a copy-on-write snapshot, so this is
# ~1s), authorizes the caller's SSH key, clears the stale host key for a
# recycled name, waits for sshd, seeds the Claude token and gh login, locks
# egress down to the agent allowlist, and clones the repos.
#
# Egress defaults to `agent`: the allowlist in pixels-config.toml, enough for
# the agents, GitHub and package registries. --egress unrestricted opts out.
#
# --no-auth skips the credential seeding, for a box you do not trust with
# your subscription tokens. Either way codex signs in per box afterwards:
# scripts/codex-login.sh <name>.

set -euo pipefail

NAME="${1:?Usage: $0 <name> [--repo org/repo]... [--egress agent|unrestricted] [--no-auth]}"; shift || true
EGRESS=agent
SEED_AUTH=1
REPOS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --egress) EGRESS="${2:?--egress needs a mode}"; shift 2 ;;
    --no-auth) SEED_AUTH=0; shift ;;
    --repo) REPOS+=("${2:?--repo needs org/repo}"); shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="${BASE:-base}"
HOSTALIAS="px-$NAME"
KNOWN="$HOME/.ssh/known_hosts.pixels"

command -v pixels >/dev/null || { echo "pixels not found; run ./install.sh (or scripts/host-setup.sh)"; exit 1; }
. "$HERE/lib/box.sh"
no_api_keys

step() { echo; echo "==> $*"; }

step "Cloning $BASE:ready -> $NAME"
pixels create "$NAME" --from "$BASE:ready"

# A clone carries the template's authorized_keys, i.e. whoever built the
# template. Add this caller's key, plus any listed in
# ~/.config/pixels/authorized_keys (keys of other machines you drive boxes
# from). This goes over the Incus API, since SSH cannot work until it is done.
step "Authorizing SSH keys"
# Keys go in as arguments, not stdin: `pixels exec` allocates a PTY whenever
# stdin is attached, which echoes the input back and never delivers EOF.
KEYS=("$(cat "$HOME/.ssh/id_ed25519.pub")")
if [[ -f "$HOME/.config/pixels/authorized_keys" ]]; then
  while IFS= read -r k; do
    [[ -z "$k" || "$k" == \#* ]] || KEYS+=("$k")
  done < "$HOME/.config/pixels/authorized_keys"
fi
pixels exec "$NAME" -- sh -c '
  umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys
  for k in "$@"; do
    grep -qxF "$k" ~/.ssh/authorized_keys || printf "%s\n" "$k" >> ~/.ssh/authorized_keys
  done
  echo "    $(wc -l < ~/.ssh/authorized_keys) key(s) authorized"' sh "${KEYS[@]}" </dev/null

# Each clone regenerates its host key, and names get reused, so an old entry
# here would hard-fail the next connection. ssh records the HostName, which is
# px-foo.incus when resolved directly and px-foo behind a ProxyCommand.
ssh-keygen -R "$HOSTALIAS" -f "$KNOWN" >/dev/null 2>&1 || true
ssh-keygen -R "$HOSTALIAS.incus" -f "$KNOWN" >/dev/null 2>&1 || true

step "Waiting for sshd"
for i in $(seq 1 30); do
  if ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOSTALIAS" true 2>/dev/null; then
    echo "Reachable as $HOSTALIAS"
    break
  fi
  [[ $i -eq 30 ]] && { echo "Timed out waiting for $HOSTALIAS"; exit 1; }
  sleep 3
done

# Set explicitly even for `unrestricted`, so re-running newbox.sh on an
# existing name cannot leave an old policy in place.
step "Egress: $EGRESS"
pixels network set "$NAME" "$EGRESS"
# `network set` reloads the ruleset from scratch, which drops the GitHub
# ranges the base image's refresh timer adds; the timer would put them back
# within a minute, but the repo clone below starts now.
incus exec "$HOSTALIAS" --project "$PROJECT" -T -- /usr/local/sbin/my-ai-org-egress-refresh 2>/dev/null || true

if [[ $SEED_AUTH -eq 1 && -x "$HERE/seed-agent-auth.sh" ]]; then
  step "Seeding agent credentials"
  "$HERE/seed-agent-auth.sh" "$HOSTALIAS" || echo "    (seeding failed; run seed-agent-auth.sh $HOSTALIAS by hand)"
fi

# Repos land at ~/code/<org>/<repo>, mirroring the laptop. Keeping the org
# level means paths match muscle memory, anything in a repo that refers to a
# sibling by path still resolves, and two repos sharing a name across orgs do
# not collide in a multi-repo box.
for repo in ${REPOS+"${REPOS[@]}"}; do
  org="${repo%%/*}"; name="${repo##*/}"
  if [[ "$org" == "$repo" || -z "$name" ]]; then
    echo "    --repo wants org/repo, got: $repo"; exit 1
  fi
  step "Cloning $repo -> ~/code/$org/$name"
  ssh -o BatchMode=yes "$HOSTALIAS" "
    set -e
    mkdir -p ~/code/$org
    if [ -d ~/code/$org/$name/.git ]; then
      echo '    already present'
    else
      gh repo clone $repo ~/code/$org/$name -- --quiet
    fi
    cd ~/code/$org/$name
    if [ -f mise.toml ] || [ -f .mise.toml ]; then
      mise trust --yes . >/dev/null 2>&1 || true
      echo '    installing toolchain...'
      mise install --yes 2>&1 | tail -3
    fi
  "
done

step "Ready"
echo "  start a task:  scripts/task new $NAME <task> [claude|codex]"
echo "  a shell:       ssh $HOSTALIAS"
[[ $SEED_AUTH -eq 1 ]] && echo "  claude and gh: signed in from this machine"
echo "  codex:         scripts/codex-login.sh $NAME   (once per box)"
for repo in ${REPOS+"${REPOS[@]}"}; do
  echo "  repo:          ~/code/${repo%%/*}/${repo##*/}"
done
