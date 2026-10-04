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
#   5. org         paperclip-org.sh: root company, Chief of Staff, CTO, DevOps
#   6. GitHub bot  github-apps.sh: the App the reviewing roles act as
#   7. projects    provision.sh FILE (default local/projects.manifest): a box
#                  and a six-agent team per project. With no manifest yet,
#                  writes one listing every repo you can access, all commented
#                  out, and stops so you can choose.
#   8. skills      skills-sync.sh: skills/sources.manifest into Paperclip
#   9. boxes       refresh tools this repo ships onto existing boxes
#
# Upgrading is `git pull && ./install.sh`: every phase reconciles rather than
# skipping what exists (the template rebuilds when base-setup.sh changes,
# Paperclip updates itself, agents' instructions upgrade unless you edited
# them).
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

# ============================================================ 4. paperclip
# paperclip-setup.sh also upgrades Paperclip and the container's tools on
# every run (PAPERCLIP_UPDATE=0 to skip).
phase "4. Paperclip"
"$S/paperclip-up.sh"

# ================================================================== 5. org
phase "5. Organisation"
"$S/paperclip-org.sh" ${COMPANY:+--company "$COMPANY"}

# ============================================================ 6. GitHub bot
# One GitHub App for every reviewing role. Created and installed once (two
# browser clicks); after that this only checks it and refreshes Paperclip's
# copy of its credentials. paperclip-org.sh runs again so the company-level
# agents pick the credentials up on the first install.
phase "6. GitHub bot"
"$S/github-apps.sh"
"$S/paperclip-org.sh" ${COMPANY:+--company "$COMPANY"} >/dev/null

# ============================================================= 7. projects
# newproject.sh is idempotent per project: it adds missing team members and
# upgrades existing agents' instructions from templates/, so re-running this
# after a pull brings every project's team up to date.
phase "7. Projects"
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

# =============================================================== 8. skills
phase "8. Skills"
"$S/skills-sync.sh"

# ========================================================= 9. box refresh
# Tools shipped from this repo onto boxes that already exist.
phase "9. Existing boxes"
for b in $(pixels list 2>/dev/null | awk 'NR>1 && $1 != "base" && $2 == "RUNNING" {print $1}'); do
  "$S/seed-agent-auth.sh" --only gh-bot "px-$b" >/dev/null 2>&1 && info "px-$b: gh-bot refreshed" \
    || info "px-$b: unreachable; skipped"
done

phase "Done"
echo "  Paperclip:  http://localhost:3100"
echo "  Boxes:      pixels list   /   ssh px-<name>"
echo "  Upgrade:    git pull && ./install.sh   (only changes what is out of date)"
