#!/usr/bin/env bash
# Copy this machine's Claude token and GitHub login into a box.
#
#   scripts/seed-agent-auth.sh px-foo                 # both, over SSH
#   scripts/seed-agent-auth.sh --only claude px-foo   # just one of claude|gh
#
# claude: the long-lived token from `claude setup-token`, as stored by
# set-claude-token.sh -- not a copy of ~/.claude/.credentials.json, whose
# refresh token rotates and would log the copies out of each other. The token
# is subscription auth: billed to the same plan, never an API key.
# gh: the token from `gh auth token`, handed over stdin.
#
# codex is not seeded. A ChatGPT login rotates its refresh token the same way
# and has no long-lived form (only --with-api-key, which is API billing), so
# each box signs in on its own: scripts/codex-login.sh px-foo.
#
# Seeded per box at create time rather than baked into the template, so the
# template stays credential-free and a box you do not trust with your
# subscriptions can be made with `newbox.sh --no-auth`.
#
# Credentials are streamed over SSH straight into the box; nothing is written
# to a temp file on this machine, and no value is ever printed.

set -euo pipefail

USAGE="Usage: $0 [--only claude|gh] <ssh-alias>"
ONLY=""
if [[ "${1:-}" == "--only" ]]; then ONLY="${2:?$USAGE}"; shift 2; fi
[[ $# -eq 1 ]] || { echo "$USAGE"; exit 1; }
want() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }

BOX="$1"
remote() { ssh -o BatchMode=yes -o ConnectTimeout=15 "$BOX" "$1"; }

step() { echo "==> $*"; }
warn() { echo "    skipped: $*"; }

remote true </dev/null 2>/dev/null || { echo "Cannot reach $BOX."; exit 1; }

# ------------------------------------------------------------------- claude
# The token goes to a file, and a two-line hook exports it as
# CLAUDE_CODE_OAUTH_TOKEN. The hook sits at the top of ~/.bashrc because the
# stock .bashrc returns early for non-interactive shells; ~/.profile covers
# the login shells that herdr panes start (`bash -lc 'exec claude'`).
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
    echo "    seeded (long-lived subscription token)"
  else
    warn "no long-lived token; run 'claude setup-token', then scripts/set-claude-token.sh"
  fi
fi

# ----------------------------------------------------------------------- gh
# The base image ships gh but no credentials, so a fresh box cannot clone a
# private repo. Hand the token over stdin -- never as an argv value, which
# would be visible in the box's process list.
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

step "Done"
echo "codex signs in per box: scripts/codex-login.sh $BOX"
