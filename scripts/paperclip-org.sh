#!/usr/bin/env bash
# The opinionated Paperclip organisation: the operator's root company with a
# Chief of Staff at the top and a DevOps agent beside it. Idempotent.
#
#   scripts/paperclip-org.sh [--company "Name"]
#
#   company          the single root company. Created if there is none (asks
#                    for a name, defaulting to "<git user.name>'s company");
#                    adopted if there is exactly one.
#   Chief of Staff   role ceo, so Product Managers report to it by default; claude.
#   DevOps           role devops, reports to the Chief of Staff; claude, run
#                    locally in the Paperclip container from its checkout of
#                    this repo, where pixels/newproject.sh are set up for it.
#
# Existing agents are matched by name and brought into line (runtime, role,
# manager) without touching their instructions or history. Instructions are
# only written when an agent is created, from templates/.
#
# Both run with engine=cli. claude's default ACP engine is the wrong choice on
# SSH targets (see README, Gotchas); cli is used everywhere for one behaviour.

set -euo pipefail
shopt -s inherit_errexit   # failures inside $(...) must stop the script too

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"   # repo root: templates/, local/
PAPERCLIP="${PAPERCLIP:-http://127.0.0.1:3100}"
COMPANY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --company) COMPANY="${2:?}"; shift 2 ;;
    *) echo "Usage: $0 [--company \"Name\"]"; exit 1 ;;
  esac
done

step() { echo; echo "==> $*"; }
info() { echo "    $*"; }
die()  { echo "    !! $*" >&2; exit 1; }
api() {  # api METHOD PATH [JSON]
  local out code
  out=$(mktemp)
  code=$(curl -sS -o "$out" -w '%{http_code}' -X "$1" "$PAPERCLIP/api$2" \
    -H 'Content-Type: application/json' ${3:+--data "$3"}) || { rm -f "$out"; die "cannot reach Paperclip at $PAPERCLIP"; }
  [[ "$code" -lt 400 ]] || { echo "    !! $1 $2 -> HTTP $code: $(head -c 400 "$out")" >&2; rm -f "$out"; return 1; }
  cat "$out"; rm -f "$out"
}
render() {  # render template-file -> stdout, with {{INFRA_REPO_DIR}} filled
  local t; t=$(<"$1")
  printf '%s' "${t//\{\{INFRA_REPO_DIR\}\}/$INFRA_DIR}"
}

curl -fsS -o /dev/null "$PAPERCLIP/api/health" || die "Paperclip is not answering at $PAPERCLIP (run paperclip-up.sh)"

# Where paperclip-up.sh checked this repo out inside the container.
ORIGIN=$(git -C "$HERE" remote get-url origin 2>/dev/null || true)
if [[ "$ORIGIN" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  INFRA_DIR="/home/paperclip/code/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
else
  INFRA_DIR="/home/paperclip/code/my-ai-org"
fi

# ------------------------------------------------------------------ company
step "Company"
companies=$(api GET /companies)
n=$(jq length <<<"$companies")
if [[ "$n" -gt 1 ]]; then
  [[ -n "$COMPANY" ]] || die "$n companies exist; say which is the root one with --company"
  CID=$(jq -r --arg c "$COMPANY" '.[] | select(.name == $c or .id == $c) | .id' <<<"$companies" | head -1)
  [[ -n "$CID" ]] || die "no company '$COMPANY'"
elif [[ "$n" -eq 1 ]]; then
  CID=$(jq -r '.[0].id' <<<"$companies")
  [[ -z "$COMPANY" || "$COMPANY" == "$(jq -r '.[0].name' <<<"$companies")" ]] \
    || info "note: keeping the existing company; --company '$COMPANY' ignored"
else
  if [[ -z "$COMPANY" ]]; then
    def="$(git config user.name 2>/dev/null || echo "$USER")'s company"
    if [[ -t 0 ]]; then read -r -p "    Name for your company [$def]: " COMPANY; fi
    COMPANY="${COMPANY:-$def}"
  fi
  CID=$(api POST /companies "$(jq -n --arg n "$COMPANY" '{name: $n,
    description: "The operator'"'"'s root company. Every project lives here."}')" | jq -r .id)
fi
info "$(api GET "/companies/$CID" | jq -r .name) ($CID)"

AGENTS=$(api GET "/companies/$CID/agents")
LOCAL_ENV=$(api GET "/companies/$CID/environments" | jq -r '[.[] | select(.driver == "local")][0].id // empty')

# ensure_agent NAME ROLE TITLE TEMPLATE MANAGER_ID EXTRA_ADAPTER_JSON -> prints id
ensure_agent() {
  local name="$1" role="$2" title="$3" template="$4" manager="$5" extra="$6" id cur body
  id=$(jq -r --arg n "$name" '.[] | select((.name | ascii_downcase) == ($n | ascii_downcase)) | .id' <<<"$AGENTS" | head -1)
  if [[ -z "$id" ]]; then
    body=$(jq -n --arg n "$name" --arg r "$role" --arg t "$title" --arg m "$manager" \
      --arg env "$LOCAL_ENV" --arg md "$(render "$template")" --argjson x "$extra" '{
        name: $n, role: $r, title: $t, adapterType: "claude_local",
        adapterConfig: ({engine: "cli"} + $x),
        reportsTo: (if $m == "" then null else $m end),
        defaultEnvironmentId: (if $env == "" then null else $env end),
        instructionsBundle: {entryFile: "AGENTS.md", files: {"AGENTS.md": $md}}}')
    id=$(api POST "/companies/$CID/agents" "$body" | jq -r .id)
    info "$name: hired ($id)" >&2
  else
    cur=$(jq -c --arg id "$id" '.[] | select(.id == $id)' <<<"$AGENTS")
    # An agent made by the onboarding wizard is bound to an AI connection, and
    # Paperclip will not move it to another provider's harness: there is no
    # way to unbind, and binding a Claude subscription connection trips its
    # broken usage check (README, Gotchas). Leave its runtime alone.
    if jq -e '(.runtimeConfig.aiConnection.provider // "anthropic") != "anthropic" and .adapterType != "claude_local"' <<<"$cur" >/dev/null; then
      api PATCH "/agents/$id" "$(jq -c --arg r "$role" --arg t "$title" --arg m "$manager" \
        '{role: $r, title: (.title // $t), reportsTo: (if $m == "" then .reportsTo else $m end)}' <<<"$cur")" >/dev/null
      info "$name: exists ($id); role $role. Runtime left as $(jq -r .adapterType <<<"$cur"): bound to a $(jq -r .runtimeConfig.aiConnection.provider <<<"$cur") AI connection, which Paperclip cannot switch" >&2
      echo "$id"; return
    fi
    # Switching runtime keeps the managed instructions, skills, timeouts and
    # history; only the other adapter's own keys are dropped.
    body=$(jq -c --arg r "$role" --arg t "$title" --arg m "$manager" --argjson x "$extra" '
      {role: $r, title: (.title // $t), reportsTo: (if $m == "" then .reportsTo else $m end)}
      + (if .adapterType == "claude_local" and .adapterConfig.engine == "cli" then {}
         else {adapterType: "claude_local", replaceAdapterConfig: true,
               adapterConfig: ((.adapterConfig // {}) | with_entries(select(.key | test(
                 "^(instructions|paperclipSkillSync|graceSec|timeoutSec|cwd|env)"))) + {engine: "cli"} + $x)}
         end)' <<<"$cur")
    api PATCH "/agents/$id" "$body" >/dev/null
    info "$name: exists ($id); runtime claude/cli, role $role" >&2
  fi
  echo "$id"
}

# ------------------------------------------------------------------- agents
step "Agents"
COS_ID=$(ensure_agent "Chief of Staff" ceo "Chief of Staff" "$ROOT/templates/chief-of-staff.md" "" '{}')
ensure_agent "DevOps" devops "DevOps" "$ROOT/templates/devops-agent.md" "$COS_ID" \
  "$(jq -n --arg d "$INFRA_DIR" '{cwd: $d}')" >/dev/null

step "Done"
echo "  UI: $PAPERCLIP"
