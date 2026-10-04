#!/usr/bin/env bash
# One command from a bare Linux machine to a working AI org: Incus, project
# containers, Paperclip with a Chief of Staff and DevOps agent, and your
# projects provisioned. Idempotent -- re-run it after any failure, or on an
# existing install to bring it up to date; finished steps are skipped.
#
#   ./install.sh [--company "Name"] [--projects FILE] [--no-projects]
#
#   0. prereqs     installs Incus, mise, gh, jq, git (apt / pacman / dnf),
#                  initialises Incus, joins incus-admin, makes an SSH key
#   1. logins      gh auth login, and a long-lived Claude token
#                  (claude setup-token -> set-claude-token.sh), if missing
#   2. host        host-setup.sh: restricted `agents` project, API on the
#                  bridge, .incus DNS, pixels
#   3. base image  the template every project box is cloned from
#   4. paperclip   paperclip-up.sh: the control-plane container
#   5. org         paperclip-org.sh: root company, Chief of Staff, DevOps
#   6. projects    provision.sh FILE (default local/projects.manifest). With no
#                  manifest yet, writes one listing every repo you can access,
#                  all commented out, and stops so you can choose.
#
# Interactive by design: it asks for sudo, and for browser sign-ins the first
# time. Run it in a real terminal.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/scripts"
COMPANY=""; PROJECTS="$HERE/local/projects.manifest"; DO_PROJECTS=1
ARGS=("$@")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --company) COMPANY="${2:?}"; shift 2 ;;
    --projects) PROJECTS="${2:?}"; shift 2 ;;
    --no-projects) DO_PROJECTS=0; shift ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)"; exit 1 ;;
  esac
done

phase() { echo; echo "################ $*"; }
info()  { echo "    $*"; }
die()   { echo "!! $*" >&2; exit 1; }

[[ -t 0 ]] || die "run this in an interactive terminal (it asks for sudo and sign-ins)"
[[ $EUID -ne 0 ]] || die "run as your normal user, not root; it uses sudo where needed"
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

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
for c in incus mise gh jq git curl ssh; do command -v "$c" >/dev/null || need+=("$c"); done
if [[ ${#need[@]} -gt 0 ]]; then
  info "installing: ${need[*]}"
  case "$FAMILY" in
    debian)
      sudo apt-get update -qq
      sudo apt-get install -y -qq incus jq git curl gh openssh-client ca-certificates gnupg
      if ! command -v mise >/dev/null; then
        # Same GPG-verified apt repo the containers use.
        sudo install -dm 755 /etc/apt/keyrings
        curl -fsSL https://mise.jdx.dev/gpg-key.pub | sudo gpg --dearmor --yes -o /etc/apt/keyrings/mise-archive-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=$(dpkg --print-architecture)] https://mise.jdx.dev/deb stable main" \
          | sudo tee /etc/apt/sources.list.d/mise.list >/dev/null
        sudo apt-get update -qq && sudo apt-get install -y -qq mise
      fi ;;
    arch)
      sudo pacman -S --needed --noconfirm incus mise github-cli jq git curl openssh ;;
    fedora)
      sudo dnf install -y incus gh jq git curl openssh-clients
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

[[ -f "$HOME/.ssh/id_ed25519" ]] || { ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"; info "created ~/.ssh/id_ed25519"; }
info "ok"

# =============================================================== 1. logins
phase "1. Sign-ins"
if gh auth status >/dev/null 2>&1; then
  info "gh: signed in"
else
  info "gh: signing in (needed to clone private repos)"
  gh auth login
fi

TOKEN_FILE="$HOME/.config/my-ai-org/claude-oauth-token"
if [[ -s "$TOKEN_FILE" ]]; then
  info "claude: long-lived token present"
else
  command -v claude >/dev/null || { info "installing claude-code (to mint the token)"; mise use -g claude-code@latest >/dev/null; }
  echo
  echo "    Claude needs a long-lived subscription token. 'claude setup-token' opens a"
  echo "    browser sign-in and prints the token; copy it, then paste it at the next prompt."
  read -r -p "    Press Enter to start... " _
  claude setup-token
  "$S/set-claude-token.sh" --no-boxes
fi

# ================================================================= 2. host
phase "2. Host"
"$S/host-setup.sh"

# =========================================================== 3. base image
phase "3. Base image"
if pixels checkpoint list base 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx ready; then
  info "base:ready exists (see README 'Updating the image' to refresh it)"
else
  pixels list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx base || pixels create base
  pixels start base >/dev/null 2>&1 || true
  incus file push "$S/base-setup.sh" px-base/root/base-setup.sh --project agents
  incus exec px-base --project agents -- bash /root/base-setup.sh
  incus exec px-base --project agents -- bash -c 'rm -f /root/base-setup.sh /etc/ssh/ssh_host_*'
  pixels checkpoint create base --label ready
fi

# ============================================================ 4. paperclip
phase "4. Paperclip"
"$S/paperclip-up.sh"

# ================================================================== 5. org
phase "5. Organisation"
"$S/paperclip-org.sh" ${COMPANY:+--company "$COMPANY"}

# ============================================================= 6. projects
phase "6. Projects"
if [[ $DO_PROJECTS -eq 0 ]]; then
  info "skipped (--no-projects)"
elif [[ -f "$PROJECTS" ]]; then
  "$S/provision.sh" "$PROJECTS"
else
  "$S/list-repos.sh" "$PROJECTS"
  echo
  echo "    No project list yet, so one was written with every repo you can access,"
  echo "    all commented out. Uncomment the ones you want, then re-run ./install.sh"
  echo "    (or just scripts/provision.sh $PROJECTS)."
fi

phase "Done"
echo "  Paperclip:  http://localhost:3100"
echo "  Boxes:      pixels list   /   ssh px-<name>"
echo "  Re-run ./install.sh any time; it only does what is missing."
