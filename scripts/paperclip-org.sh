#!/usr/bin/env bash
# The opinionated Paperclip organisation: the operator's root company and its
# company-level agents. Idempotent; re-running it upgrades them.
#
#   scripts/paperclip-org.sh [--company "Name"]
#
#   company          the single root company. Created if there is none (asks
#                    for a name, defaulting to "<git user.name>'s company");
#                    adopted if there is exactly one.
#   Chief of Staff   role ceo, so Product Managers report to it by default.
#   CTO              role cto, reports to the Chief of Staff; runs a weekly
#                    cross-project review (a Paperclip routine) for security,
#                    engineering practice and compliance.
#   DevOps           role devops, reports to the Chief of Staff; runs from its
#                    checkout of this repo, where pixels and newproject.sh are
#                    set up for it.
#
# All three run claude, locally in the Paperclip container. Each project's own
# team is created by scripts/newproject.sh. Agents are created or brought into
# line by ensure_agent (scripts/lib/paperclip.sh), which also upgrades their
# instructions from templates/ while they are still the ones this repo wrote.

set -euo pipefail
shopt -s inherit_errexit   # failures inside $(...) must stop the script too

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"   # repo root: templates/, local/
COMPANY=""
REVIEW_CRON="${REVIEW_CRON:-0 9 * * 1}"     # CTO review: Mondays 09:00
REVIEW_TZ="${REVIEW_TZ:-$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --company) COMPANY="${2:?}"; shift 2 ;;
    *) echo "Usage: $0 [--company \"Name\"]"; exit 1 ;;
  esac
done

step() { echo; echo "==> $*"; }
info() { echo "    $*"; }
die()  { echo "    !! $*" >&2; exit 1; }
. "$HERE/lib/paperclip.sh"

curl -fsS -o /dev/null "$PAPERCLIP/api/health" || die "Paperclip is not answering at $PAPERCLIP (run paperclip-up.sh)"

# Where paperclip-up.sh checked this repo out inside the container.
ORIGIN=$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)
if [[ "$ORIGIN" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  INFRA_REPO_DIR="/home/paperclip/code/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
else
  INFRA_REPO_DIR="/home/paperclip/code/my-ai-org"
fi
export INFRA_REPO_DIR

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
LOCAL_ENV=$(api GET "/companies/$CID/environments" | jq -r '[.[] | select(.driver == "local")][0].id // empty')

# ------------------------------------------------------------------- agents
step "Agents"
agent() {  # agent KEY NAME ROLE TEMPLATE MANAGER EXTRA_JSON -> id
  A_COMPANY="$CID" A_NAME="$2" A_ROLE_KEY="$1" A_ROLE="$3" A_TITLE="$2" \
  A_TEMPLATE="$ROOT/templates/$4" A_MANAGER="$5" A_ENV="$LOCAL_ENV" \
  A_ADAPTER=claude_local A_EXTRA="$6" A_PROJECT="" A_BUDGET=0 ensure_agent
}
COS_ID=$(agent chief-of-staff "Chief of Staff" ceo chief-of-staff.md "" '{}')
CTO_ID=$(agent cto "CTO" cto cto.md "$COS_ID" '{}')
agent devops "DevOps" devops devops-agent.md "$COS_ID" "$(jq -n --arg d "$INFRA_REPO_DIR" '{cwd: $d}')" >/dev/null

# --------------------------------------------------------- CTO review routine
# A Paperclip routine opens an issue for the CTO on a schedule. Matched by
# title, so re-runs update the schedule rather than adding a second routine.
step "CTO review routine"
ROUTINE_TITLE="Weekly engineering review"
RID=$(api GET "/companies/$CID/routines" | jq -r --arg t "$ROUTINE_TITLE" \
  '(if type == "array" then . else (.routines // .items // []) end) | .[] | select(.title == $t) | .id' | head -1)
if [[ -z "$RID" ]]; then
  RID=$(api POST "/companies/$CID/routines" "$(jq -n --arg t "$ROUTINE_TITLE" --arg a "$CTO_ID" '{
    title: $t, assigneeAgentId: $a, priority: "medium",
    description: "Review every project for security, engineering practice and compliance since the last review, as described in your instructions. File what you find in the affected repos, and summarise here for the Chief of Staff."}')" | jq -r .id)
  api POST "/routines/$RID/triggers" "$(jq -n --arg c "$REVIEW_CRON" --arg z "$REVIEW_TZ" \
    '{kind: "schedule", cronExpression: $c, timezone: $z}')" >/dev/null
  info "created: \"$ROUTINE_TITLE\", $REVIEW_CRON ($REVIEW_TZ)"
else
  info "exists ($RID)"
fi

step "Done"
echo "  UI: $PAPERCLIP"
