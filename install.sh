#!/usr/bin/env bash
# One command from a bare Linux machine to a terminal control plane for coding
# agents: Incus, one box per repo, herdr on this host, and a `task` command
# that opens an agent in its own worktree. Idempotent -- re-run it after any
# failure, or on an existing install to bring it up to date.
#
#   ./install.sh [--boxes FILE] [--no-boxes]
#
#   0. prereqs     installs Incus, mise, gh, jq, git, herdr, mosh (apt /
#                  pacman / dnf), initialises Incus, joins incus-admin, makes
#                  an SSH key
#   1. logins      gh auth login, and a long-lived Claude token
#                  (claude setup-token -> set-claude-token.sh), if missing
#   2. host        host-setup.sh: restricted `agents` project, .incus DNS,
#                  pixels
#   3. base image  the template every box is cloned from
#   4. boxes       boxes.sh FILE (default local/boxes.manifest): a box per
#                  line. With no manifest yet, writes one listing every repo
#                  you can access, all commented out, and stops so you can
#                  choose.
#   5. task        puts scripts/task on your PATH (~/.local/bin/task)
#
# Upgrading is `git pull && ./install.sh`: the template rebuilds when
# base-setup.sh changes, and new manifest lines become boxes. Existing boxes
# are never rebuilt for you.
#
# Interactive by design: it asks for sudo, and for browser sign-ins the first
# time. Run it in a real terminal.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/scripts"
BOXES="$HERE/local/boxes.manifest"; DO_BOXES=1
ARGS=("$@")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --boxes) BOXES="${2:?}"; shift 2 ;;
    --no-boxes) DO_BOXES=0; shift ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)"; exit 1 ;;
  esac
done

phase() { echo; echo "################ $*"; }
info()  { echo "    $*"; }
die()   { echo "!! $*" >&2; exit 1; }

[[ -t 0 ]] || die "run this in an interactive terminal (it asks for sudo and sign-ins)"
[[ $EUID -ne 0 ]] || die "run as your normal user, not root; it uses sudo where needed"
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

# Upgrading is `git pull && ./install.sh`; say so if this checkout is behind.
if git -C "$HERE" fetch -q 2>/dev/null; then
  behind=$(git -C "$HERE" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
  [[ "$behind" -gt 0 ]] && echo "NOTE: this checkout is $behind commit(s) behind its upstream; 'git pull' first for the latest."
fi

# ============================================================== 0. prereqs
phase "0. Prerequisites"
. /etc/os-release
FAMILY=""
case " ${ID:-} ${ID_LIKE:-} " in
  *" debian "*|*" ubuntu "*) FAMILY=debian ;;
  *" arch "*)                FAMILY=arch ;;
  *" fedora "*|*" rhel "*)   FAMILY=fedora ;;
esac
info "distro: ${PRETTY_NAME:-unknown} (${FAMILY:-unsupported})"

need=()
for c in incus mise gh jq git curl ssh mosh; do command -v "$c" >/dev/null || need+=("$c"); done
if [[ ${#need[@]} -gt 0 ]]; then
  info "installing: ${need[*]}"
  case "$FAMILY" in
    debian)
      sudo apt-get update -qq
      sudo apt-get install -y -qq incus jq git curl gh openssh-client ca-certificates gnupg mosh
      if ! command -v mise >/dev/null; then
        # Same GPG-verified apt repo the containers use.
        sudo install -dm 755 /etc/apt/keyrings
        curl -fsSL https://mise.jdx.dev/gpg-key.pub | sudo gpg --dearmor --yes -o /etc/apt/keyrings/mise-archive-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=$(dpkg --print-architecture)] https://mise.jdx.dev/deb stable main" \
          | sudo tee /etc/apt/sources.list.d/mise.list >/dev/null
        sudo apt-get update -qq && sudo apt-get install -y -qq mise
      fi ;;
    arch)
      sudo pacman -S --needed --noconfirm incus mise github-cli jq git curl openssh mosh ;;
    fedora)
      sudo dnf install -y incus gh jq git curl openssh-clients mosh
      command -v mise >/dev/null || { sudo dnf copr enable -y jdxcode/mise && sudo dnf install -y mise; } ;;
    *) die "unsupported distro; install these yourself, then re-run: ${need[*]}" ;;
  esac
fi

# Unprivileged containers map root to a subordinate ID range. Debian's package
# sets one up; Arch's and Fedora's do not, and every launch fails without it.
for f in /etc/subuid /etc/subgid; do
  grep -qs '^root:' "$f" || { echo "root:1000000:1000000000" | sudo tee -a "$f" >/dev/null; info "added root range to $f"; }
done

if ! systemctl is-active --quiet incus.service && ! systemctl is-active --quiet incus.socket; then
  sudo systemctl enable --now incus.socket 2>/dev/null || true
  sudo systemctl enable --now incus.service
fi

# Group membership only applies to new logins; re-exec under it rather than
# asking for a logout halfway through.
if ! id -nG | tr ' ' '\n' | grep -qx incus-admin; then
  if ! getent group incus-admin | grep -qw "$USER"; then
    sudo usermod -aG incus-admin "$USER"; info "added $USER to incus-admin"
  fi
  info "continuing with incus-admin membership"
  exec sg incus-admin -c "$(printf '%q ' "$0" ${ARGS[@]+"${ARGS[@]}"})"
fi

if [[ -z "$(incus storage list --format csv 2>/dev/null)" ]]; then
  info "initialising Incus (default storage pool + incusbr0 bridge)"
  incus admin init --minimal
fi
incus network show incusbr0 >/dev/null 2>&1 || die "Incus has no incusbr0 bridge; create one: incus network create incusbr0"

# herdr is the one control plane, and it runs here, not in the boxes. A
# distro or system package wins if there is one; otherwise mise's.
if ! command -v herdr >/dev/null; then
  info "installing herdr (mise)"
  mise use -g herdr@latest >/dev/null
fi
info "herdr $(herdr --version 2>/dev/null | awk '{print $2}')"

[[ -f "$HOME/.ssh/id_ed25519" ]] || { ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"; info "created ~/.ssh/id_ed25519"; }
info "ok"

# =============================================================== 1. logins
phase "1. Sign-ins"
if gh auth status >/dev/null 2>&1; then
  info "gh: signed in"
else
  info "gh: signing in (needed to clone private repos into boxes)"
  gh auth login
fi

TOKEN_FILE="$HOME/.config/my-ai-org/claude-oauth-token"
if [[ -s "$TOKEN_FILE" ]]; then
  info "claude: long-lived token present"
else
  command -v claude >/dev/null || { info "installing claude-code (to mint the token)"; mise use -g claude-code@latest >/dev/null; }
  echo
  echo "    Claude needs a long-lived subscription token (not an API key). 'claude setup-token'"
  echo "    opens a browser sign-in and prints the token; copy it, then paste it at the next prompt."
  read -r -p "    Press Enter to start... " _
  claude setup-token
  "$S/set-claude-token.sh" --no-boxes
fi

# ================================================================= 2. host
phase "2. Host"
"$S/host-setup.sh"

# =========================================================== 3. base image
# Rebuilt whenever base-setup.sh has changed since the template was built (its
# checksum is kept inside the template), so a `git pull` that changes the
# toolchain reaches every box created afterwards. Existing boxes are clones
# and keep the toolchain they were made with.
phase "3. Base image"
want_sha=$(sha256sum "$S/base-setup.sh" | cut -c1-64)
have_ready=0
pixels checkpoint list base 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx ready && have_ready=1
pixels list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx base || pixels create base
pixels start base >/dev/null 2>&1 || true
have_sha=$(incus exec px-base --project agents -- cat /etc/my-ai-org/base-setup.sha256 2>/dev/null || true)
if [[ $have_ready -eq 1 && "$have_sha" == "$want_sha" ]]; then
  info "base:ready is current"
else
  [[ $have_ready -eq 1 ]] && info "base-setup.sh changed; rebuilding the template" || info "building the template"
  incus file push "$S/base-setup.sh" px-base/root/base-setup.sh --project agents
  incus exec px-base --project agents -- bash /root/base-setup.sh
  incus exec px-base --project agents -- bash -c "rm -f /root/base-setup.sh /etc/ssh/ssh_host_* && install -d /etc/my-ai-org && echo $want_sha > /etc/my-ai-org/base-setup.sha256"
  [[ $have_ready -eq 1 ]] && pixels checkpoint delete base ready
  pixels checkpoint create base --label ready
  [[ $have_ready -eq 1 ]] && info "new boxes get the new toolchain; existing ones keep theirs (rebuild a box to upgrade it)"
fi

# ================================================================ 4. boxes
phase "4. Boxes"
if [[ $DO_BOXES -eq 0 ]]; then
  info "skipped (--no-boxes)"
elif [[ -f "$BOXES" ]]; then
  "$S/boxes.sh" "$BOXES"
else
  "$S/list-repos.sh" "$BOXES"
  echo
  echo "    No box list yet, so one was written with every repo you can access,"
  echo "    all commented out. Uncomment the ones you want, then re-run ./install.sh"
  echo "    (or just scripts/boxes.sh $BOXES)."
fi

# ================================================================= 5. task
# A symlink, so `git pull` updates the command too.
phase "5. task command"
install -d "$HOME/.local/bin"
ln -sfn "$S/task" "$HOME/.local/bin/task"
info "~/.local/bin/task -> scripts/task"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) info "add ~/.local/bin to your PATH to run it as plain 'task'" ;;
esac

phase "Done"
echo "  Attach:     herdr                 (from your phone: mosh <this-host> -- herdr)"
echo "  A task:     task new <box> <task> [claude|codex]"
echo "  codex:      scripts/codex-login.sh <box>   (once per box)"
echo "  Upgrade:    git pull && ./install.sh"
