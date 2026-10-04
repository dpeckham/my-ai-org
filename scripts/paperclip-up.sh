#!/usr/bin/env bash
# Build (or update) the Paperclip control-plane container. Run on the Incus
# host, after host-setup.sh. Idempotent -- re-run it to pick up script changes.
#
#   scripts/paperclip-up.sh [--no-auth]
#
# Result:
#   - a `paperclip` container in the *default* Incus project, running Paperclip
#     as a systemd user service bound to its own loopback;
#   - http://localhost:3100 on this host, via an Incus proxy device, and
#     nowhere else;
#   - an Incus client inside it whose certificate is restricted to the
#     `agents` project, plus pixels configured to use it -- so Paperclip's
#     DevOps agent can create and destroy project boxes and cannot touch this
#     host, the default project, or Paperclip itself;
#   - this repo checked out at ~/code/<org>/<repo>, so the DevOps agent runs
#     the same newbox.sh you do;
#   - SSH keys exchanged so boxes made by either side accept both;
#   - this machine's claude / codex / gh credentials seeded, unless --no-auth.
#
# Knobs (env): NAME, PROJECT, BRIDGE, PORT, PC_CPU, PC_MEMORY,
# PAPERCLIP_TELEMETRY=on.

set -euo pipefail

SEED_AUTH=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-auth) SEED_AUTH=0; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="${NAME:-paperclip}"
PROJECT="${PROJECT:-agents}"
BRIDGE="${BRIDGE:-incusbr0}"
PORT="${PORT:-3100}"
# Agents run on the project boxes, not here; this holds the server, embedded
# Postgres, and whatever the DevOps agent runs locally.
PC_CPU="${PC_CPU:-2}"
PC_MEMORY="${PC_MEMORY:-4GiB}"
PC_USER=paperclip

step() { echo; echo "==> $*"; }
in_pc() { incus exec "$NAME" --project default -- su - "$PC_USER" -c "$1"; }

incus project show "$PROJECT" >/dev/null 2>&1 || { echo "No '$PROJECT' project; run scripts/host-setup.sh first."; exit 1; }
BRIDGE_IP=$(incus network get "$BRIDGE" ipv4.address); BRIDGE_IP="${BRIDGE_IP%/*}"
API="$BRIDGE_IP:8443"
[[ "$(incus config get core.https_address)" == "$API" ]] \
  || echo "WARNING: core.https_address is not $API; the restricted client may not connect."

# ---------------------------------------------------------------- container
step "Container '$NAME'"
if ! incus info "$NAME" --project default >/dev/null 2>&1; then
  incus launch images:debian/13 "$NAME" --project default \
    -c limits.cpu="$PC_CPU" -c limits.memory="$PC_MEMORY"
else
  incus start "$NAME" --project default 2>/dev/null || true
fi
for i in $(seq 1 30); do
  incus exec "$NAME" --project default -- systemctl is-system-running 2>/dev/null \
    | grep -qE 'running|degraded' && break
  [[ $i -eq 30 ]] && { echo "Timed out waiting for $NAME to boot"; exit 1; }
  sleep 2
done

step "Toolchain + Paperclip (paperclip-setup.sh)"
incus file push "$HERE/paperclip-setup.sh" "$NAME/root/paperclip-setup.sh" --project default
incus exec "$NAME" --project default \
  --env PAPERCLIP_TELEMETRY="${PAPERCLIP_TELEMETRY:-off}" -- bash /root/paperclip-setup.sh

# ------------------------------------------------------------ host access
# bind=host: listen on this host's loopback, connect to the container's.
# Paperclip runs local_trusted (no login), so this must stay on 127.0.0.1.
step "localhost:$PORT -> $NAME"
if ! incus config device show "$NAME" --project default | grep -q '^ui:'; then
  incus config device add "$NAME" ui proxy --project default \
    listen="tcp:127.0.0.1:$PORT" connect="tcp:127.0.0.1:3100" bind=host
fi

# ---------------------------------------------------- restricted incus trust
# The token is single-use and goes in over stdin, not argv.
step "Incus client restricted to '$PROJECT'"
if in_pc 'incus remote list --format csv' 2>/dev/null | cut -d, -f1 | sed 's/ (current)$//' | grep -qx host; then
  echo "Already trusted"
else
  # A rebuilt container has a new key, so drop certificates left under this
  # name by earlier builds. `trust remove` takes a fingerprint, not a name.
  incus config trust list --format csv | awk -F, -v n="$NAME" '$1==n {print $4}' \
    | while read -r fp; do incus config trust remove "$fp"; done
  incus config trust add "$NAME" --restricted --projects "$PROJECT" --quiet \
    | in_pc "read -r t; incus remote add host https://$API --token \"\$t\" --accept-certificate >/dev/null"
fi
in_pc "incus remote switch host && incus project switch $PROJECT" >/dev/null

step "pixels config for $PC_USER"
{
  echo '# Written by paperclip-up.sh -- HTTPS with a client certificate restricted'
  echo "# to the $PROJECT project. Edit pixels-config.toml in the repo and re-run."
  echo 'backend = "incus"'
  echo
  echo '[incus]'
  echo "remote      = \"https://$API\""
  echo 'client_cert = "~/.config/incus/client.crt"'
  echo 'client_key  = "~/.config/incus/client.key"'
  echo 'server_cert = "~/.config/incus/servercerts/host.crt"'
  echo "project     = \"$PROJECT\""
  echo
  cat "$HERE/pixels-config.toml"
} | in_pc 'install -d ~/.config/pixels && cat > ~/.config/pixels/config.toml'
in_pc 'pixels list' >/dev/null && echo "pixels reaches the $PROJECT project"

# ------------------------------------------------------------ key exchange
# newbox.sh authorizes its caller's key plus ~/.config/pixels/authorized_keys
# on every new box. Cross-list the two keys so either side can reach a box the
# other made.
step "Exchanging SSH keys"
PC_PUB=$(in_pc 'cat ~/.ssh/id_ed25519.pub')
HOST_PUB=$(cat "$HOME/.ssh/id_ed25519.pub")
mkdir -p "$HOME/.config/pixels"; touch "$HOME/.config/pixels/authorized_keys"
grep -qxF "$PC_PUB" "$HOME/.config/pixels/authorized_keys" \
  || echo "$PC_PUB" >> "$HOME/.config/pixels/authorized_keys"
printf '%s\n' "$HOST_PUB" | in_pc '
  touch ~/.config/pixels/authorized_keys; read -r k
  grep -qxF "$k" ~/.config/pixels/authorized_keys || printf "%s\n" "$k" >> ~/.config/pixels/authorized_keys'
echo "Done (new boxes only; run newbox.sh's key step by hand for existing ones)"

# --------------------------------------------------------------- the repo
# HTTPS, so cloning a public repo needs no credentials. For a private one the
# gh token seeded below is what makes it work, so seed first.
# The long-lived Claude token, if this machine has one: into the container,
# into Paperclip's secret store, and bound on its environments. Without it,
# claude agents cannot authenticate (copied logins rotate each other out).
TOKEN_FILE="$HOME/.config/my-ai-org/claude-oauth-token"
if [[ $SEED_AUTH -eq 1 && -s "$TOKEN_FILE" ]]; then
  step "Claude token"
  "$HERE/set-claude-token.sh" --no-verify --no-boxes < "$TOKEN_FILE" | sed 's/^/  /'
elif [[ $SEED_AUTH -eq 1 ]]; then
  echo; echo "NOTE: no $TOKEN_FILE; run 'claude setup-token' then scripts/set-claude-token.sh"
fi

if [[ $SEED_AUTH -eq 1 ]]; then
  step "Seeding agent credentials"
  "$HERE/seed-agent-auth.sh" --incus "$NAME:$PC_USER" \
    || echo "    (seeding failed; run seed-agent-auth.sh --incus $NAME:$PC_USER by hand)"
fi

ORIGIN=$(git -C "$HERE" remote get-url origin 2>/dev/null || true)
if [[ "$ORIGIN" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  ORG="${BASH_REMATCH[1]}"; REPO="${BASH_REMATCH[2]}"
  step "Checking out $ORG/$REPO in $NAME"
  in_pc "
    set -e
    mkdir -p ~/code/$ORG
    if [ -d ~/code/$ORG/$REPO/.git ]; then
      git -C ~/code/$ORG/$REPO pull --ff-only --quiet && echo '    updated'
    else
      git clone --quiet https://github.com/$ORG/$REPO.git ~/code/$ORG/$REPO && echo '    cloned'
    fi"
else
  echo "No GitHub origin for this repo; push it somewhere and clone it into $NAME by hand."
fi

step "Ready"
echo "  UI:       http://localhost:$PORT"
echo "  shell:    incus exec $NAME -- su - $PC_USER"
echo "  logs:     incus exec $NAME -- su - $PC_USER -c 'XDG_RUNTIME_DIR=/run/user/\$(id -u) paperclipai service logs -f'"
[[ -n "${ORG:-}" ]] && echo "  repo:     ~/code/$ORG/$REPO (the DevOps agent's newbox.sh)"
