#!/usr/bin/env bash
# Drive project containers on a SEPARATE Incus box from this laptop. Idempotent.
#
#   BOX_HOST=mybox.local ./laptop-setup.sh
#
# Only for the remote-box layout (a headless machine built with bootstrap.sh /
# firstboot.sh). If Incus runs on the machine you are sitting at, use
# host-setup.sh instead.
#
# Prereqs: the box is an Incus remote on this laptop (bootstrap.sh adds it),
# and host-setup.sh has been run ON the box to create the `agents` project
# (NO_DNS=1 is fine there; it needs no mise for that part).
#
# Installs pixels via mise, points it at the box's Incus daemon + `agents`
# project, and adds the SSH block that makes `ssh px-<name>` reach a container
# on the box's NAT'd bridge.
#
# Knobs (env): BOX_HOST (required), BOX_USER (default: $USER), REMOTE
# (default: box), PROJECT (default: agents), BRIDGE, PIXELS_VERSION.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX_HOST="${BOX_HOST:?Set BOX_HOST to the box hostname, e.g. BOX_HOST=mybox.local}"
BOX_USER="${BOX_USER:-$USER}"
REMOTE="${REMOTE:-box}"
PROJECT="${PROJECT:-agents}"
BRIDGE="${BRIDGE:-incusbr0}"
PIXELS_VERSION="${PIXELS_VERSION:-0.6.2}"

step() { echo; echo "==> $*"; }

command -v mise >/dev/null || { echo "mise is required (tools come from mise, not brew)."; exit 1; }

# ------------------------------------------------------------------- pixels
step "pixels $PIXELS_VERSION via mise"
mise use -g "github:deevus/pixels@$PIXELS_VERSION"

# -------------------------------------------------------------- incus remote
step "Checking the Incus remote '$REMOTE'"
# The CSV name column carries a " (current)" suffix on the default remote,
# so match the bare name rather than the whole field.
if ! incus remote list --format csv 2>/dev/null | cut -d, -f1 | sed 's/ (current)$//' | grep -qx "$REMOTE"; then
  echo "No '$REMOTE' Incus remote yet. Run bootstrap.sh first, or:"
  echo "  incus remote add $REMOTE $BOX_HOST --token <token> --accept-certificate"
  exit 1
fi
incus project show "$REMOTE:$PROJECT" >/dev/null 2>&1 \
  || { echo "No '$PROJECT' project on $REMOTE; run host-setup.sh on the box."; exit 1; }
BRIDGE_IP=$(incus network get "$REMOTE:$BRIDGE" ipv4.address); BRIDGE_IP="${BRIDGE_IP%/*}"
DNS_DOMAIN=$(incus network get "$REMOTE:$BRIDGE" dns.domain); DNS_DOMAIN="${DNS_DOMAIN:-incus}"
echo "Incus remote OK; bridge at $BRIDGE_IP"

# ------------------------------------------------------------- pixels config
# The incus client keeps its certs in os.UserConfigDir()/incus, and pixels
# reads its own config from os.UserConfigDir()/pixels: ~/Library/Application
# Support on macOS, ~/.config on Linux. The real file lives in ~/.config
# either way and is symlinked on macOS so it sits with the other dotfiles.
step "pixels config"
if [[ "$(uname -s)" == "Darwin" ]]; then
  INCUS_DIR="~/Library/Application Support/incus"
else
  INCUS_DIR="~/.config/incus"
fi
mkdir -p "$HOME/.config/pixels"
CFG="$HOME/.config/pixels/config.toml"
[[ -f "$CFG" ]] && cp "$CFG" "$CFG.bak"
{
  echo "# Written by laptop-setup.sh -- the '$REMOTE' Incus remote over HTTPS."
  echo '# Edit pixels-config.toml in the repo for the shared settings and re-run.'
  echo 'backend = "incus"'
  echo
  echo '[incus]'
  # Reached by name so a new DHCP lease on the box does not break the config.
  # TLS is pinned to the cert incus already trusts, so the hostname is not
  # security-relevant here.
  echo "remote      = \"https://$BOX_HOST:8443\""
  echo "client_cert = \"$INCUS_DIR/client.crt\""
  echo "client_key  = \"$INCUS_DIR/client.key\""
  echo "server_cert = \"$INCUS_DIR/servercerts/$REMOTE.crt\""
  echo "project     = \"$PROJECT\""
  echo
  cat "$HERE/pixels-config.toml"
} > "$CFG"
echo "Wrote $CFG"

if [[ "$(uname -s)" == "Darwin" ]]; then
  APP_SUPPORT="$HOME/Library/Application Support/pixels"
  if [[ -e "$APP_SUPPORT" && ! -L "$APP_SUPPORT" ]]; then
    echo "NOTE: $APP_SUPPORT exists and is not a symlink; leaving it alone."
    echo "      pixels will read that copy, not ~/.config/pixels."
  else
    ln -sfn "$HOME/.config/pixels" "$APP_SUPPORT"
  fi
fi

# ----------------------------------------------------------------- ssh block
# Containers sit on the box's NAT'd bridge and are not routable from here, so
# hop through the box. Its own resolver does not know the .incus zone (no
# systemd-resolved on a stock Debian server), so ask the bridge's dnsmasq
# directly; that keeps container IPs dynamic with no per-container config.
# (firstboot.sh installs the nc and dig this needs.)
#
# Host keys go in their own file: every clone regenerates its host key and
# names get recycled. newbox.sh clears the stale entry on create. Do NOT use
# UserKnownHostsFile=/dev/null -- `herdr machine add` fails with "lost
# connection to server" without a real file.
#
# Agent forwarding is off: these containers run AI coding agents, and a
# forwarded agent would hand them your private keys.
step "SSH config for px-* containers"
mkdir -p "$HOME/.ssh/config.d"
cat > "$HOME/.ssh/config.d/pixels" <<EOF
Host px-*
    User pixel
    ProxyCommand ssh $BOX_USER@$BOX_HOST 'nc \$(dig +short %h.$DNS_DOMAIN @$BRIDGE_IP | head -n1) 22'
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts.pixels
    ForwardAgent no
EOF
chmod 0600 "$HOME/.ssh/config.d/pixels"

# The Include has to sit above every Host block or it is never consulted.
if ! grep -qs 'config.d' "$HOME/.ssh/config"; then
  touch "$HOME/.ssh/config"
  cp "$HOME/.ssh/config" "$HOME/.ssh/config.bak.$(date +%Y%m%d%H%M%S)"
  { echo 'Include ~/.ssh/config.d/*'; echo; cat "$HOME/.ssh/config"; } > "$HOME/.ssh/config.new"
  mv "$HOME/.ssh/config.new" "$HOME/.ssh/config"
  chmod 0600 "$HOME/.ssh/config"
  echo "Include added to ~/.ssh/config"
fi

step "Done"
echo "Next: build the base image (see README, 'Dev base image'), using"
echo "  incus ... $REMOTE:px-base --project $PROJECT"
