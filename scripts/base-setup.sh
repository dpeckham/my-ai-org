#!/usr/bin/env bash
# Toolchain for the dev base image. Runs INSIDE a pixels container, as root.
#
#   incus file push base-setup.sh px-base/root/base-setup.sh
#   incus exec px-base -- bash /root/base-setup.sh
#
# Installs git + gh + mise and the two agent CLIs, Claude Code and Codex, for
# the `pixel` user. Only the official CLIs: they run on the operator's
# subscriptions, and nothing here may set an API key. Idempotent.
#
# herdr is not installed here. It runs on the host, and panes reach into boxes
# with `incus exec` (see scripts/task).
#
# Everything above the system layer goes through mise so there is exactly one
# place to bump a version: /home/pixel/.config/mise/config.toml, which this
# script writes. mise itself comes from its Debian repo rather than
# `curl https://mise.run | sh` so the install is apt- and GPG-verified.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

PIXEL_USER=pixel
PIXEL_HOME="/home/$PIXEL_USER"

[[ $EUID -eq 0 ]] || { echo "Run as root inside the container."; exit 1; }
id "$PIXEL_USER" >/dev/null 2>&1 || {
  echo "User $PIXEL_USER does not exist — did pixels provisioning run?"; exit 1; }

step() { echo; echo "==> $*"; }

# --------------------------------------------------------------- system layer
step "Base packages"
apt-get update -qq
# nftables is here rather than pulled on demand because `pixels network set
# <box> agent` shells out to apt to install it, which fails on a container that
# has no package lists -- exactly the state a freshly cloned template is in.
apt-get install -y -qq \
  git curl ca-certificates gnupg build-essential \
  jq unzip openssh-server sudo nftables

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
# node is explicit because both agent CLIs want a runtime.
step "mise tool manifest"
# Create .config explicitly: `install -d` only applies -o/-g to the final
# component, so creating .config/mise in one shot leaves .config owned by root
# and every later tool that wants ~/.config/<name> (gh's hosts file, the
# Claude token) fails with EACCES.
install -d -o "$PIXEL_USER" -g "$PIXEL_USER" -m 755 "$PIXEL_HOME/.config"
install -d -o "$PIXEL_USER" -g "$PIXEL_USER" -m 755 "$PIXEL_HOME/.config/mise"
cat > "$PIXEL_HOME/.config/mise/config.toml" <<EOF
[tools]
node = "lts"

# Source control
gh = "latest"

# The agents. Official CLIs only: pixels' own devtools step would have
# installed these, and it is disabled (see pixels-config.toml), so they are
# declared here.
claude-code = "latest"
codex       = "latest"
EOF
chown "$PIXEL_USER:$PIXEL_USER" "$PIXEL_HOME/.config/mise/config.toml"

step "Installing tools via mise (this pulls node first)"
su - "$PIXEL_USER" -c 'mise trust --yes ~/.config/mise/config.toml' || true
su - "$PIXEL_USER" -c 'mise install --yes'
# A rebuild over an older template leaves tools the manifest no longer lists
# (earlier versions shipped opencode, t3 and herdr); drop them and their shims.
su - "$PIXEL_USER" -c 'mise prune --yes >/dev/null 2>&1; mise reshim' || true

# mise activation for interactive shells; the shims dir keeps non-interactive
# `ssh box cmd` working too.
if ! grep -q 'mise activate bash' "$PIXEL_HOME/.bashrc" 2>/dev/null; then
  cat >> "$PIXEL_HOME/.bashrc" <<'EOF'

# mise
eval "$(mise activate bash)"
EOF
  chown "$PIXEL_USER:$PIXEL_USER" "$PIXEL_HOME/.bashrc"
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

# profile.d only covers login shells. `ssh host <cmd>` is neither login nor
# interactive, and the stock Debian/Ubuntu .bashrc returns early when it is
# not interactive —
# so neither file runs. Scripts drive boxes exactly that way, so the shims
# have to be on PATH before any shell starts. sshd runs PAM, and pam_env reads /etc/environment, which
# applies to non-interactive sessions too.
SHIMS="$PIXEL_HOME/.local/share/mise/shims"
if [[ -f /etc/environment ]] && grep -q '^PATH=' /etc/environment; then
  if ! grep -q "$SHIMS" /etc/environment; then
    sed -i -E "s|^PATH=\"?([^\"]*)\"?$|PATH=\"$SHIMS:\1\"|" /etc/environment
  fi
else
  echo "PATH=\"$SHIMS:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"" >> /etc/environment
fi

# ------------------------------------------------------- ssh host key hygiene
# Every clone of this template would otherwise ship the template's SSH host
# keys, so all containers would present one identity and none could be told
# apart -- a compromised one could impersonate any other. The keys are removed
# just before checkpointing (see README); this unit regenerates them on first
# boot of each clone. Debian 13 and Ubuntu 24.04 both socket-activate sshd, so
# order against ssh.socket as well as ssh.service.
step "SSH host key regeneration on first boot"
cat > /etc/systemd/system/regenerate-ssh-host-keys.service <<'EOF'
[Unit]
Description=Regenerate SSH host keys when absent (fresh identity per clone)
Before=ssh.service ssh.socket

# No ConditionPathExistsGlob here: the negated-glob form evaluated false even
# with /etc/ssh empty, so the unit was skipped on boot. `ssh-keygen -A` only
# creates key types that are missing, so it is already idempotent and needs no
# guard.

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable regenerate-ssh-host-keys.service >/dev/null 2>&1 || true

# ------------------------------------------------------- egress refresh
# `pixels network set <box> agent` resolves each allowed domain once, when it
# is set, and puts those IPs in an nftables set. CDN-backed hosts move:
# github.com answered with a different address within the hour, and every
# `git fetch` then hung until it timed out. Two fixes, both additive (the set
# only grows; nothing is flushed, so running agents are not disturbed):
#   - GitHub's published IPv4 ranges (api.github.com/meta), fetched now;
#   - a timer that re-resolves pixels' own domain list every minute.
# It does nothing on a box whose egress is unrestricted (no pixels table).
step "Egress allowlist refresh"
install -d -m 755 /etc/my-ai-org
{
  echo "# GitHub's IPv4 ranges from api.github.com/meta, fetched by base-setup.sh $(date +%F)."
  curl -fsSL https://api.github.com/meta \
    | jq -r '[(.web + .api + .git)[] | select(contains(":") | not)] | unique | .[]'
} > /etc/my-ai-org/egress-cidrs
cat > /usr/local/sbin/my-ai-org-egress-refresh <<'EOF'
#!/bin/bash
# Re-resolve the pixels egress allowlist and add any new addresses.
set -uo pipefail
nft list table inet pixels_egress >/dev/null 2>&1 || exit 0
add() { nft add element inet pixels_egress allowed_v4 "{ $1 }" 2>/dev/null || true; }
grep -hv '^#' /etc/my-ai-org/egress-cidrs 2>/dev/null | while read -r c; do [ -n "$c" ] && add "$c"; done
grep -hv '^#' /etc/pixels-egress-domains 2>/dev/null | while read -r d; do
  [ -n "$d" ] || continue
  for ip in $(getent ahostsv4 "$d" | awk '{print $1}' | sort -u); do add "$ip"; done
done
EOF
chmod 755 /usr/local/sbin/my-ai-org-egress-refresh
cat > /etc/systemd/system/my-ai-org-egress-refresh.service <<'EOF'
[Unit]
Description=Re-resolve the pixels egress allowlist (CDN addresses move)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/my-ai-org-egress-refresh
EOF
cat > /etc/systemd/system/my-ai-org-egress-refresh.timer <<'EOF'
[Unit]
Description=Re-resolve the pixels egress allowlist every minute

[Timer]
OnBootSec=20s
OnUnitActiveSec=1min
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF
systemctl enable my-ai-org-egress-refresh.timer >/dev/null 2>&1 || true

# ------------------------------------------------------- agent first-run
# Claude Code's first interactive start runs onboarding (theme picker, then a
# login-method menu) unless ~/.claude.json says it is done -- even with
# CLAUDE_CODE_OAUTH_TOKEN set. In a herdr pane that looks like a login
# prompt, so mark it done here. Credentials are not part of this: they are
# seeded per box (seed-agent-auth.sh), never baked into the template.
step "Claude Code first-run state"
su - "$PIXEL_USER" -c '
  f=~/.claude.json
  [ -s "$f" ] || echo "{}" > "$f"
  jq ".hasCompletedOnboarding = true" "$f" > "$f.new" && mv "$f.new" "$f"'

# ------------------------------------------------------------------------ git
step "git defaults"
su - "$PIXEL_USER" -c 'git config --global init.defaultBranch main'
# Scoped to the shared volume rather than "*": a blanket safe.directory turns
# off git's ownership check everywhere, which matters more than usual in a box
# an agent has a shell on. Harmless when /repos is not mounted.
su - "$PIXEL_USER" -c 'git config --global --add safe.directory "/repos/*"'

step "Done"
su - "$PIXEL_USER" -c 'mise ls' || true
