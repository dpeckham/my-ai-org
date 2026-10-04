#!/usr/bin/env bash
# Install a long-lived Claude subscription token everywhere agents run.
#
#   claude setup-token                      # once, in a real terminal (browser sign-in)
#   scripts/set-claude-token.sh                   # paste it at the hidden prompt
#   scripts/set-claude-token.sh < token-file      # or pipe it in (paperclip-up.sh does this)
#
# Why: copying ~/.claude/.credentials.json between machines works only until
# the first refresh. Claude rotates the refresh token on every refresh, so
# whichever copy refreshes first silently logs out all the others ("OAuth
# session expired and could not be refreshed"). `claude setup-token` mints a
# long-lived token, billed to the same subscription, that claude reads from
# CLAUDE_CODE_OAUTH_TOKEN and that never rotates -- so one token can be shared.
#
# Puts it in four places, each idempotent:
#   1. ~/.config/my-ai-org/claude-oauth-token on this machine (mode 600) --
#      the copy seed-agent-auth.sh and paperclip-up.sh read;
#   2. the same file in the Paperclip container, for its own claude and for
#      boxes the DevOps agent creates;
#   3. a Paperclip company secret `claude-oauth-token`, bound as
#      CLAUDE_CODE_OAUTH_TOKEN on every SSH and local environment, so every
#      agent run gets it;
#   4. every existing project box, via seed-agent-auth.sh.
#
# The token is never put in argv (process lists), never printed, and never
# written to this repo.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAPERCLIP="${PAPERCLIP:-http://127.0.0.1:3100}"
PC_NAME="${PC_NAME:-paperclip}"
PC_USER=paperclip
SECRET_NAME=claude-oauth-token
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

# ------------------------------------------------------- 2. the container
step "2. Paperclip container"
if [[ -d "$HOME/.paperclip/instances" ]]; then
  info "running inside it; step 1 covered it"
elif incus info "$PC_NAME" --project default >/dev/null 2>&1; then
  # Same as a box: the file plus the profile hook that exports it. (The
  # service's own runs get it from the secret bound on the Local environment.)
  "$HERE/seed-agent-auth.sh" --only claude --incus "$PC_NAME:$PC_USER" >/dev/null \
    && info "saved, with the shell hook" || die "could not install it in $PC_NAME"
else
  info "no '$PC_NAME' container yet; paperclip-up.sh installs it from step 1's file"
fi

# ------------------------------------------------- 3. Paperclip secret + envs
step "3. Paperclip secret '$SECRET_NAME'"
if ! curl -fsS -o /dev/null "$PAPERCLIP/api/health" 2>/dev/null; then
  info "Paperclip not reachable at $PAPERCLIP; skipped (re-run once it is up)"
else
  # Request bodies go over stdin (--data @-), so the value never reaches argv.
  api() {  # api METHOD PATH [-]   ("-" = JSON body on stdin)
    local out code body=()
    out=$(mktemp)
    [[ "${3:-}" == "-" ]] && body=(-H 'Content-Type: application/json' --data @-)
    code=$(curl -sS -o "$out" -w '%{http_code}' -X "$1" "$PAPERCLIP/api$2" "${body[@]}")
    [[ "$code" -lt 400 ]] || { echo "    !! $1 $2 -> HTTP $code: $(head -c 300 "$out")" >&2; rm -f "$out"; return 1; }
    cat "$out"; rm -f "$out"
  }
  companies=$(api GET /companies)
  [[ "$(jq length <<<"$companies")" -eq 1 ]] || die "expected exactly one Paperclip company"
  CID=$(jq -r '.[0].id' <<<"$companies")

  list=$(api GET "/companies/$CID/secrets")
  SID=$(jq -r --arg n "$SECRET_NAME" '(if type == "array" then . else (.secrets // .items // []) end)
    | .[] | select(.name == $n) | .id' <<<"$list" | head -1)
  if [[ -n "$SID" ]]; then
    jq -n --arg v "$TOKEN" '{value: $v}' | api POST "/secrets/$SID/rotate" - >/dev/null
    info "rotated ($SID)"
  else
    SID=$(jq -n --arg n "$SECRET_NAME" --arg v "$TOKEN" '{name: $n, value: $v,
      description: "Long-lived Claude subscription token (claude setup-token). Set by set-claude-token.sh."}' \
      | api POST "/companies/$CID/secrets" - | jq -r .id)
    info "created ($SID)"
  fi

  # Bind it on every SSH and local environment. A secret_ref with no version
  # follows the latest, so a later rotation needs no re-binding. envVars is
  # replaced wholesale by PATCH, so merge into what is there.
  envs=$(api GET "/companies/$CID/environments")
  while IFS= read -r env; do
    [[ -z "$env" ]] && continue
    id=$(jq -r .id <<<"$env")
    jq --arg s "$SID" '{envVars: ((.envVars // {}) + {CLAUDE_CODE_OAUTH_TOKEN: {type: "secret_ref", secretId: $s}})}' <<<"$env" \
      | api PATCH "/environments/$id" - >/dev/null
    info "bound on environment $(jq -r .name <<<"$env") ($(jq -r .driver <<<"$env"))"
  done < <(jq -c '.[] | select(.driver == "ssh" or .driver == "local")' <<<"$envs")
fi

# ------------------------------------------------------------- 4. the boxes
step "4. Project boxes"
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
echo "Rotate later by running this again with a new token; nothing needs re-binding."
