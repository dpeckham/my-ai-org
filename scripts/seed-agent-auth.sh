#!/usr/bin/env bash
# Copy this machine's agent + GitHub credentials into a container.
#
#   scripts/seed-agent-auth.sh px-foo                   # a project box, over SSH
#   scripts/seed-agent-auth.sh --incus paperclip:paperclip   # instance:user, via incus exec
#
# The --incus form is for the Paperclip container, which runs no sshd.
#
#   scripts/seed-agent-auth.sh --only claude px-foo     # just one of claude|codex|gh
#
# claude: the long-lived token from `claude setup-token`, as stored by
# set-claude-token.sh -- not a copy of ~/.claude/.credentials.json, whose
# refresh token rotates and would log the copies out of each other.
# codex: ~/.codex/auth.json is copied, because codex has no headless token for
# ChatGPT sign-in (only --with-api-key, a different billing path). It has the
# same rotation exposure; see the README.
# gh: the token from `gh auth token`, handed over stdin.
# gh-bot: not a credential, the wrapper the reviewing roles use to act as the
# company's GitHub App (scripts/gh-bot), installed at ~/.local/bin/gh-bot.
#
# They are seeded per container at create time rather than baked into the
# `ready` checkpoint, so the template stays credential-free and a throwaway or
# --egress agent box can simply be created with --no-auth.
#
# Credentials are streamed over SSH straight into the container; nothing is
# written to a temp file on this machine, and no value is ever printed.

set -euo pipefail

USAGE="Usage: $0 [--only claude|codex|gh|gh-bot] <ssh-alias> | --incus <instance>:<user>"
ONLY=""
if [[ "${1:-}" == "--only" ]]; then ONLY="${2:?$USAGE}"; shift 2; fi
[[ $# -ge 1 ]] || { echo "$USAGE"; exit 1; }
want() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }

# `remote CMD` runs a shell command string as the target user, with this
# script's stdin. Both transports take the command as one string, so every
# call site below is the same either way.
if [[ "$1" == "--incus" ]]; then
  TARGET="${2:?$USAGE}"
  INST="${TARGET%%:*}"; RUSER="${TARGET#*:}"
  [[ "$INST" != "$TARGET" && -n "$RUSER" ]] || { echo "$USAGE"; exit 1; }
  BOX="$INST ($RUSER)"
  remote() { incus exec "$INST" -- su - "$RUSER" -c "$1"; }
else
  BOX="$1"
  remote() { ssh -o BatchMode=yes -o ConnectTimeout=15 "$BOX" "$1"; }
fi

step() { echo "==> $*"; }
warn() { echo "    skipped: $*"; }

remote true </dev/null 2>/dev/null || { echo "Cannot reach $BOX."; exit 1; }

# ------------------------------------------------------------------- claude
# Not the ~/.claude/.credentials.json login: Claude rotates its refresh token
# on every refresh, so copies of one login log each other out within hours.
# set-claude-token.sh stores a long-lived `claude setup-token` token instead;
# it goes to the same path on the target, and a two-line hook exports it as
# CLAUDE_CODE_OAUTH_TOKEN. The hook sits at the top of ~/.bashrc because the
# stock .bashrc returns early for non-interactive shells, which is exactly how
# `ssh box cmd` (herdr, T3, Paperclip) runs things; ~/.profile covers login
# shells.
CLAUDE_TOKEN_FILE="$HOME/.config/my-ai-org/claude-oauth-token"
if want claude; then
  step "claude-code"
  if [[ -s "$CLAUDE_TOKEN_FILE" ]]; then
    remote '
      install -d -m 700 ~/.config/my-ai-org
      umask 077; cat > ~/.config/my-ai-org/claude-oauth-token
      hook="[ -r ~/.config/my-ai-org/claude-oauth-token ] && export CLAUDE_CODE_OAUTH_TOKEN=\"\$(cat ~/.config/my-ai-org/claude-oauth-token)\""
      for f in ~/.bashrc ~/.profile; do
        touch "$f"
        grep -qF "my-ai-org/claude-oauth-token" "$f" && continue
        if [ "$f" = ~/.bashrc ]; then
          { echo "# Long-lived Claude token (my-ai-org set-claude-token.sh)."; echo "$hook"; echo; cat "$f"; } > "$f.new" && mv "$f.new" "$f"
        else
          { echo; echo "# Long-lived Claude token (my-ai-org set-claude-token.sh)."; echo "$hook"; } >> "$f"
        fi
      done' < "$CLAUDE_TOKEN_FILE"
    echo "    seeded (long-lived token)"
  else
    warn "no long-lived token; run 'claude setup-token', then scripts/set-claude-token.sh"
  fi
fi

# -------------------------------------------------------------------- codex
if want codex; then
step "codex"
if [[ -f "$HOME/.codex/auth.json" ]]; then
  remote 'install -d -m 700 ~/.codex && umask 077 && cat > ~/.codex/auth.json' < "$HOME/.codex/auth.json"
  echo "    seeded ($(jq -r '.auth_mode // "unknown"' "$HOME/.codex/auth.json") mode)"
else
  warn "no ~/.codex/auth.json; run 'codex login' on this machine first"
fi
fi

# ----------------------------------------------------------------------- gh
# The base image ships gh but no credentials, so a fresh box cannot clone a
# private repo. macOS keeps its token in the macOS keyring, so pull it
# out with `gh auth token` and hand it to the container over stdin -- never as
# an argv value, which would be visible in the container's process list.
if want gh; then
step "gh"
if command -v gh >/dev/null && gh_token=$(gh auth token 2>/dev/null) && [[ -n "$gh_token" ]]; then
  printf '%s' "$gh_token" | remote \
    'gh auth login --hostname github.com --with-token >/dev/null 2>&1 && gh auth setup-git >/dev/null 2>&1'
  echo "    seeded ($(remote 'gh auth status 2>&1 | grep -oE "account [^ ]+" | head -1' </dev/null 2>/dev/null))"
else
  warn "no gh token on this machine; run 'gh auth login' here first"
fi
fi

# ------------------------------------------------------------------- gh-bot
# Refreshed on every seed, so re-running the installer ships fixes to it.
if want gh-bot; then
  step "gh-bot"
  remote 'install -d ~/.local/bin && cat > ~/.local/bin/gh-bot.new && chmod 755 ~/.local/bin/gh-bot.new && mv ~/.local/bin/gh-bot.new ~/.local/bin/gh-bot' \
    < "$(dirname "${BASH_SOURCE[0]}")/gh-bot"
  echo "    installed at ~/.local/bin/gh-bot"
fi

step "Done"
echo "Verify on $BOX with:  codex login status; gh auth status"
