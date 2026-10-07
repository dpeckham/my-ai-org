#!/usr/bin/env bash
# Install a long-lived Claude subscription token everywhere agents run.
#
#   claude setup-token                      # once, in a real terminal (browser sign-in)
#   scripts/set-claude-token.sh                   # paste it at the hidden prompt
#   scripts/set-claude-token.sh < token-file      # or pipe it in
#
# Why: copying ~/.claude/.credentials.json between machines works only until
# the first refresh. Claude rotates the refresh token on every refresh, so
# whichever copy refreshes first silently logs out all the others ("OAuth
# session expired and could not be refreshed"). `claude setup-token` mints a
# long-lived token, billed to the same subscription, that claude reads from
# CLAUDE_CODE_OAUTH_TOKEN and that never rotates -- so one token can be shared.
# It is subscription auth, not an API key.
#
# Puts it in two places, each idempotent:
#   1. ~/.config/my-ai-org/claude-oauth-token on this machine (mode 600) --
#      the copy seed-agent-auth.sh reads for every new box;
#   2. every running box, via seed-agent-auth.sh.
#
# The token is never put in argv (process lists), never printed, and never
# written to this repo.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN_FILE="$HOME/.config/my-ai-org/claude-oauth-token"
VERIFY=1; SEED_BOXES=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-verify) VERIFY=0; shift ;;
    --no-boxes) SEED_BOXES=0; shift ;;
    *) echo "Usage: $0 [--no-verify] [--no-boxes] [< token-file]"; exit 1 ;;
  esac
done

step() { echo; echo "==> $*"; }
info() { echo "    $*"; }
die()  { echo "    !! $*" >&2; exit 1; }

# --------------------------------------------------------------- read token
if [[ -t 0 ]]; then
  read -r -s -p "Paste the token from 'claude setup-token' (input hidden): " TOKEN; echo
else
  IFS= read -r TOKEN || true
fi
TOKEN="${TOKEN//[[:space:]]/}"
[[ -n "$TOKEN" ]] || die "no token given"
[[ "$TOKEN" == sk-ant-oat* ]] || info "warning: setup-token tokens start with sk-ant-oat; this one does not"

# A wrong token would otherwise only surface as failed agent runs later.
if [[ $VERIFY -eq 1 ]]; then
  step "Verifying with claude"
  command -v claude >/dev/null || die "claude not installed here; re-run with --no-verify"
  out=$(CLAUDE_CODE_OAUTH_TOKEN="$TOKEN" timeout 90 claude -p 'Reply with exactly: ok' 2>&1 | tail -1) || true
  [[ "$out" == *ok* ]] || die "claude did not accept the token: ${out:0:200}"
  info "accepted"
fi

# ------------------------------------------------------------- 1. this host
step "1. $TOKEN_FILE"
install -d -m 700 "$(dirname "$TOKEN_FILE")"
( umask 077; printf '%s\n' "$TOKEN" > "$TOKEN_FILE" )
info "saved (mode 600)"

# ------------------------------------------------------------- 2. the boxes
step "2. Boxes"
if [[ $SEED_BOXES -eq 0 ]]; then
  info "skipped (--no-boxes)"
elif ! command -v pixels >/dev/null; then
  info "pixels not found; skipped"
else
  boxes=$(pixels list 2>/dev/null | awk 'NR>1 && $1 != "base" && $2 == "RUNNING" {print $1}')
  [[ -n "$boxes" ]] || info "none running"
  for b in $boxes; do
    if "$HERE/seed-agent-auth.sh" --only claude "px-$b" >/dev/null 2>&1; then info "px-$b: done"
    else info "px-$b: failed (try: scripts/seed-agent-auth.sh --only claude px-$b)"; fi
  done
fi

step "Done"
echo "Rotate later by running this again with a new token."
