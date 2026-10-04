#!/usr/bin/env bash
# Toolchain for the Paperclip control-plane container. Runs INSIDE it, as root.
#
#   incus file push paperclip-setup.sh paperclip/root/paperclip-setup.sh
#   incus exec paperclip -- bash /root/paperclip-setup.sh
#
# paperclip-up.sh does this for you. Installs node + Paperclip for a
# `paperclip` user, plus what its DevOps agent needs to provision project
# containers: pixels, the incus client, gh, and the agent CLIs. Idempotent.
#
# Like base-setup.sh, everything above the system layer goes through mise, so
# versions live in one manifest: /home/paperclip/.config/mise/config.toml.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

PC_USER=paperclip
PC_HOME="/home/$PC_USER"
PIXELS_VERSION="${PIXELS_VERSION:-0.6.2}"

[[ $EUID -eq 0 ]] || { echo "Run as root inside the container."; exit 1; }

step() { echo; echo "==> $*"; }
as_pc() { su - "$PC_USER" -c "$*"; }

# --------------------------------------------------------------- system layer
step "Base packages"
apt-get update -qq
# incus-client is the CLI only; the daemon it talks to is the host's, reached
# over HTTPS with a certificate restricted to the `agents` project.
apt-get install -y -qq \
  git curl ca-certificates gnupg jq unzip sudo \
  openssh-client incus-client

id "$PC_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$PC_USER"

# Paperclip installs itself as a systemd *user* service. Linger starts that
# user manager at boot rather than at first login, which never happens here.
loginctl enable-linger "$PC_USER"

# ------------------------------------------------------------------ mise (apt)
step "mise (apt repo, GPG-verified)"
install -dm 755 /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/mise-archive-keyring.gpg ]]; then
  curl -fsSL https://mise.jdx.dev/gpg-key.pub \
    | gpg --dearmor -o /etc/apt/keyrings/mise-archive-keyring.gpg
fi
ARCH=$(dpkg --print-architecture)
echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=$ARCH] https://mise.jdx.dev/deb stable main" \
  > /etc/apt/sources.list.d/mise.list
apt-get update -qq
apt-get install -y -qq mise

# ------------------------------------------------------------- managed tools
step "mise tool manifest"
# Create .config on its own first; see the note in base-setup.sh about
# `install -d` only chowning the last path component.
install -d -o "$PC_USER" -g "$PC_USER" -m 755 "$PC_HOME/.config"
install -d -o "$PC_USER" -g "$PC_USER" -m 755 "$PC_HOME/.config/mise"
cat > "$PC_HOME/.config/mise/config.toml" <<EOF
[tools]
# Paperclip requires node >= 24.11; Debian 13 ships 20.
node = "24"

gh = "latest"

# How the DevOps agent provisions project containers (see newbox.sh).
"github:deevus/pixels" = "$PIXELS_VERSION"

# Paperclip runs claude/codex on the project containers over SSH, but the
# adapters' "Test environment" probe and codex_local's auth upload both look
# on this side too.
claude-code = "latest"
codex       = "latest"
EOF
chown "$PC_USER:$PC_USER" "$PC_HOME/.config/mise/config.toml"

step "Installing tools via mise"
as_pc 'mise trust --yes ~/.config/mise/config.toml' || true
as_pc 'mise install --yes'
# "latest" entries only move when asked; re-running the installer is that ask.
[[ "${PAPERCLIP_UPDATE:-1}" == 1 ]] && as_pc 'mise upgrade --yes >/dev/null' || true

if ! grep -q 'mise activate bash' "$PC_HOME/.bashrc" 2>/dev/null; then
  cat >> "$PC_HOME/.bashrc" <<'EOF'

# mise
eval "$(mise activate bash)"
EOF
  chown "$PC_USER:$PC_USER" "$PC_HOME/.bashrc"
fi

cat > /etc/profile.d/mise-shims.sh <<'EOF'
# Make mise-managed tools resolvable in login shells.
case ":$PATH:" in
  *":$HOME/.local/share/mise/shims:"*) ;;
  *) [ -d "$HOME/.local/share/mise/shims" ] && PATH="$HOME/.local/share/mise/shims:$PATH" ;;
esac
export PATH
EOF
chmod 0644 /etc/profile.d/mise-shims.sh

# The systemd user service and Paperclip's own child processes are neither
# login nor interactive shells, so put the shims on PATH for the user manager
# itself. environment.d is read by `systemd --user` at startup.
install -d -o "$PC_USER" -g "$PC_USER" -m 755 "$PC_HOME/.config/environment.d"
cat > "$PC_HOME/.config/environment.d/10-mise.conf" <<EOF
PATH=$PC_HOME/.local/share/mise/shims:$PC_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
EOF
# Paperclip phones home usage telemetry by default. Off here; run with
# PAPERCLIP_TELEMETRY=on (paperclip-up.sh passes it through) to keep it.
if [[ "${PAPERCLIP_TELEMETRY:-off}" == "on" ]]; then
  rm -f "$PC_HOME/.config/environment.d/20-telemetry.conf"
else
  echo "PAPERCLIP_TELEMETRY_DISABLED=1" > "$PC_HOME/.config/environment.d/20-telemetry.conf"
fi
chown -R "$PC_USER:$PC_USER" "$PC_HOME/.config/environment.d"

# ------------------------------------------------------------------ ssh key
# Paperclip's SSH environments and newbox.sh both connect to project
# containers with this key. newbox.sh authorizes it on each new box.
step "SSH key for reaching project containers"
if [[ ! -f "$PC_HOME/.ssh/id_ed25519" ]]; then
  as_pc 'install -d -m 700 ~/.ssh && ssh-keygen -q -t ed25519 -N "" -C "paperclip@$(hostname)" -f ~/.ssh/id_ed25519'
fi

# Project containers resolve as <name>.incus through the bridge's dnsmasq,
# which is this container's resolver, so no ProxyCommand is needed here. Host
# keys are kept in their own file for the same reason as on the host: every
# clone has a fresh key and names get recycled. newbox.sh clears stale entries.
cat > "$PC_HOME/.ssh/config" <<'EOF'
Host px-*
    HostName %h.incus
    User pixel
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts.pixels
    ForwardAgent no
EOF
chown "$PC_USER:$PC_USER" "$PC_HOME/.ssh/config"
chmod 600 "$PC_HOME/.ssh/config"

# ---------------------------------------------------------------- paperclip
# `paperclipai install` keeps a managed copy under ~/.paperclip with a shim
# on PATH, rather than running from npm's npx cache. The service unit points
# at that shim, and `paperclipai update` swaps the payload behind it.
step "Paperclip"
if ! as_pc 'command -v paperclipai' >/dev/null 2>&1; then
  as_pc 'npx --yes paperclipai@latest install --yes'
elif [[ "${PAPERCLIP_UPDATE:-1}" == 1 ]]; then
  # Moves to the latest stable release (a no-op when current), backing up the
  # database first and keeping the previous payload for `paperclipai update
  # --rollback`. PAPERCLIP_UPDATE=0 pins the installed version.
  as_pc 'paperclipai update' || echo "    (paperclipai update failed; staying on the installed version)"
fi
as_pc 'paperclipai --version'

# Quickstart = local_trusted on 127.0.0.1:3100, embedded Postgres, state in
# ~/.paperclip. Loopback is the point: the host reaches it through an Incus
# proxy device (paperclip-up.sh), and nothing on the bridge or the LAN can.
# The service is a systemd *user* unit, hence XDG_RUNTIME_DIR under su.
step "Paperclip instance + service"
PC_ENV="export XDG_RUNTIME_DIR=/run/user/$(id -u "$PC_USER") PAPERCLIP_NO_BROWSER=1"
if [[ ! -f "$PC_HOME/.paperclip/instances/default/config.json" ]]; then
  as_pc "$PC_ENV; paperclipai onboard --yes --install-service </dev/null"
else
  # Pick up environment.d changes (telemetry, PATH), then make sure it runs.
  as_pc "$PC_ENV; systemctl --user daemon-reload; paperclipai service install </dev/null >/dev/null; systemctl --user restart paperclipai.service"
fi
for i in $(seq 1 30); do
  curl -fsS -o /dev/null http://127.0.0.1:3100/api/health && { echo "Healthy on 127.0.0.1:3100"; break; }
  [[ $i -eq 30 ]] && { echo "Paperclip did not come up; see: paperclipai service logs"; exit 1; }
  sleep 2
done

# Project boxes are reached through Paperclip's SSH environments, which sit
# behind an experimental flag. The server does not enforce it -- it only hides
# environment controls in the UI -- but newproject.sh refuses to create
# environments the operator cannot see, so turn it on here. Loopback requests
# are the implicit local operator in local_trusted mode, so no auth is needed.
step "Paperclip settings"
curl -fsS -X PATCH http://127.0.0.1:3100/api/instance/settings/experimental \
  -H 'Content-Type: application/json' --data '{"enableEnvironments":true}' \
  | jq -e '.enableEnvironments == true' >/dev/null \
  && echo "SSH environments: enabled" \
  || { echo "Could not enable SSH environments; turn them on under Settings -> Instance settings -> Experimental."; exit 1; }

step "Done"
as_pc 'mise ls' || true
