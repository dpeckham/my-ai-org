#!/usr/bin/env bash
# Prepare the machine that runs Incus for project containers + Paperclip.
# Run it ON that machine, as your normal user (in incus-admin; sudo is asked
# for once, for the DNS unit). Idempotent.
#
#   scripts/host-setup.sh
#
# Does four things:
#   1. Creates the `agents` Incus project, restricted and capped. Every project
#      container lives there; Paperclip's DevOps agent gets a certificate that
#      can touch nothing else.
#   2. Binds the Incus API to the bridge address only, so containers (i.e.
#      Paperclip) can reach it with a client certificate and the LAN cannot.
#   3. Teaches systemd-resolved the bridge's `.incus` zone, so `px-foo.incus`
#      resolves from this host the same way it does from inside a container.
#   4. Installs pixels and points it at the local socket + `agents` project,
#      and adds the `px-*` SSH block.
#
# For driving a *separate* Incus box from a laptop instead, see
# laptop-setup.sh (bootstrap.sh/firstboot.sh build such a box).
#
# Knobs (env): BRIDGE, PROJECT, AGENTS_CPU, AGENTS_MEMORY, AGENTS_INSTANCES,
# PIXELS_VERSION, NO_DNS=1 (skip step 3, the only one that needs sudo).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE="${BRIDGE:-incusbr0}"
PROJECT="${PROJECT:-agents}"
# Project limits sum the per-instance *caps* of every instance in the project,
# running or stopped (the base template included). Memory is the one that
# bites: at 4GiB per box, 20GiB is the template plus four boxes.
AGENTS_CPU="${AGENTS_CPU:-32}"
AGENTS_MEMORY="${AGENTS_MEMORY:-20GiB}"
AGENTS_INSTANCES="${AGENTS_INSTANCES:-10}"
PIXELS_VERSION="${PIXELS_VERSION:-0.6.2}"

step() { echo; echo "==> $*"; }

command -v incus >/dev/null || { echo "incus is not installed."; exit 1; }
incus info >/dev/null 2>&1  || { echo "Cannot talk to the local Incus daemon (are you in incus-admin?)."; exit 1; }

BRIDGE_CIDR=$(incus network get "$BRIDGE" ipv4.address)
BRIDGE_IP="${BRIDGE_CIDR%/*}"
[[ -n "$BRIDGE_IP" && "$BRIDGE_IP" != "none" ]] || { echo "$BRIDGE has no IPv4 address."; exit 1; }
DNS_DOMAIN=$(incus network get "$BRIDGE" dns.domain); DNS_DOMAIN="${DNS_DOMAIN:-incus}"
echo "Bridge $BRIDGE at $BRIDGE_IP, DNS zone .$DNS_DOMAIN"

# ------------------------------------------------------------ agents project
step "Incus project '$PROJECT'"
if ! incus project show "$PROJECT" >/dev/null 2>&1; then
  # Own images and profiles so the agent cannot edit the default project's;
  # shared networks so boxes sit on the same bridge as everything else.
  incus project create "$PROJECT" \
    -c features.images=true -c features.profiles=true \
    -c features.storage.volumes=true -c features.networks=false
fi
# restricted=true turns on the restricted.* defaults: unprivileged containers
# only, no nesting, disks only from managed pools, no raw.* keys, no backups.
# Snapshots are restricted by default too, and pixels checkpoints need them.
incus project set "$PROJECT" \
  restricted=true \
  restricted.snapshots=allow \
  restricted.networks.access="$BRIDGE" \
  limits.cpu="$AGENTS_CPU" \
  limits.memory="$AGENTS_MEMORY" \
  limits.instances="$AGENTS_INSTANCES"

# A new project's default profile is empty; pixels relies on it for the root
# disk and sets eth0 itself, but a hand-launched box wants both.
POOL=$(incus profile device get default root pool --project default)
incus profile device show default --project "$PROJECT" | grep -q '^root:' \
  || incus profile device add default root disk path=/ pool="$POOL" --project "$PROJECT"
incus profile device show default --project "$PROJECT" | grep -q '^eth0:' \
  || incus profile device add default eth0 nic network="$BRIDGE" name=eth0 --project "$PROJECT"
incus project show "$PROJECT" | sed -n '/^config:/,/^description/p' | sed '$d'

# ----------------------------------------------------------- API on bridge
step "Incus API on $BRIDGE_IP:8443"
CURRENT=$(incus config get core.https_address)
if [[ -z "$CURRENT" ]]; then
  incus config set core.https_address="$BRIDGE_IP:8443"
  echo "Listening on $BRIDGE_IP:8443 (bridge only)"
elif [[ "$CURRENT" == "$BRIDGE_IP:8443" ]]; then
  echo "Already set"
else
  echo "core.https_address is already '$CURRENT'; leaving it. Paperclip needs"
  echo "to reach it from the bridge, so check it covers $BRIDGE_IP."
fi

# -------------------------------------------------------------- .incus DNS
# The unit is the one from the Incus docs ("Integrate with systemd-resolved").
# Without it, `ssh px-foo` from this host cannot resolve px-foo.incus.
step ".$DNS_DOMAIN DNS via systemd-resolved"
if [[ -n "${NO_DNS:-}" ]]; then
  echo "NO_DNS set; skipping."
elif systemctl is-active --quiet systemd-resolved; then
  UNIT="/etc/systemd/system/incus-dns-$BRIDGE.service"
  WANT=$(cat <<EOF
[Unit]
Description=Incus per-link DNS configuration for $BRIDGE
BindsTo=sys-subsystem-net-devices-$BRIDGE.device
After=sys-subsystem-net-devices-$BRIDGE.device

[Service]
Type=oneshot
ExecStart=/usr/bin/resolvectl dns $BRIDGE $BRIDGE_IP
ExecStart=/usr/bin/resolvectl domain $BRIDGE ~$DNS_DOMAIN
ExecStart=/usr/bin/resolvectl dnssec $BRIDGE off
ExecStart=/usr/bin/resolvectl dnsovertls $BRIDGE off
ExecStopPost=/usr/bin/resolvectl revert $BRIDGE
RemainAfterExit=yes

[Install]
WantedBy=sys-subsystem-net-devices-$BRIDGE.device
EOF
)
  if [[ "$(cat "$UNIT" 2>/dev/null)" != "$WANT" ]]; then
    printf '%s\n' "$WANT" | sudo tee "$UNIT" >/dev/null
    sudo systemctl daemon-reload
  fi
  sudo systemctl enable --now "incus-dns-$BRIDGE.service" >/dev/null 2>&1
  sudo systemctl restart "incus-dns-$BRIDGE.service"
  resolvectl status "$BRIDGE" | grep -E 'DNS Servers|DNS Domain' || true
else
  echo "systemd-resolved is not running; skipping. Point your resolver's"
  echo ".$DNS_DOMAIN zone at $BRIDGE_IP yourself, or ssh px-* will not resolve."
fi

# On a headless box driven from a laptop (laptop-setup.sh), steps 1-2 are all
# that is needed here, and such a box has no mise. Stop before step 4.
if ! command -v mise >/dev/null; then
  echo; echo "mise not found; skipping pixels + SSH setup (fine on a remote box)."
  exit 0
fi

# ------------------------------------------------------------------- pixels
step "pixels $PIXELS_VERSION via mise"
mise use -g "github:deevus/pixels@$PIXELS_VERSION"

step "pixels config"
mkdir -p "$HOME/.config/pixels"
CFG="$HOME/.config/pixels/config.toml"
[[ -f "$CFG" ]] && cp "$CFG" "$CFG.bak"
{
  echo '# Written by host-setup.sh -- local Incus socket. Edit pixels-config.toml'
  echo '# in the repo for the shared settings and re-run.'
  echo 'backend = "incus"'
  echo
  echo '[incus]'
  echo 'socket  = "/var/lib/incus/unix.socket"'
  echo "project = \"$PROJECT\""
  echo
  cat "$HERE/pixels-config.toml"
} > "$CFG"
echo "Wrote $CFG"

# ---------------------------------------------------------------- ssh block
# This host is on the bridge, so no hop is needed: the name resolves through
# the DNS unit above and the IP is directly routable.
#
# Host keys go in their own file: every clone regenerates its host key and
# names get recycled, so entries go stale constantly. newbox.sh clears the
# stale one on create. Do NOT use UserKnownHostsFile=/dev/null -- `herdr
# machine add` fails with "lost connection to server" without a real file.
#
# Agent forwarding is off: these containers run AI coding agents, and a
# forwarded agent would hand them your private keys.
step "SSH config for px-* containers"
mkdir -p "$HOME/.ssh/config.d"
cat > "$HOME/.ssh/config.d/pixels" <<EOF
Host px-*
    HostName %h.$DNS_DOMAIN
    User pixel
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
cat <<EOF
Next, build the dev base image (once):
  pixels create base
  incus file push base-setup.sh px-base/root/base-setup.sh --project $PROJECT
  incus exec px-base --project $PROJECT -- bash /root/base-setup.sh
  incus exec px-base --project $PROJECT -- bash -c 'rm -f /root/base-setup.sh /etc/ssh/ssh_host_*'
  pixels checkpoint create base --label ready
Then the control plane:
  scripts/paperclip-up.sh
EOF
