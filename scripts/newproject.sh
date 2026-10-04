#!/usr/bin/env bash
# Start a project: its own container, plus a Product Manager agent in Paperclip working on it.
#
#   scripts/newproject.sh <name> <org/repo> [<org/repo>...] [options]
#   scripts/newproject.sh --check          # preflight only; changes nothing
#   scripts/newproject.sh --help
#
# Steps, each skipped when its object already exists (matched by name), so a
# failed run can simply be repeated:
#
#   1. box          px-<name> via newbox.sh: repos at ~/code/<org>/<repo>,
#                   toolchains, keys, agent credentials
#   2. host key     Paperclip learns the box's SSH host key
#   3. checkouts    the repos, cloned in the Paperclip container -- see below
#   4. environment  Paperclip SSH environment "<name>" -> px-<name>
#   5. Product Mgr  "<Name> Product Manager" (Paperclip role "pm"), runs on the box
#   6. project      Paperclip project "<name>", Product Manager as lead, one workspace per repo
#   7. kickoff      first issue for the Product Manager: learn the repo, write the roadmap
#
# Why two checkouts: Paperclip's SSH driver does not run agents in a directory
# that already exists on the box. Each run uploads the project workspace from
# the Paperclip side into <remote path>/.paperclip-runtime/runs/<id>/, runs
# the agent there, and copies the changes back. So the workspace Paperclip
# owns lives in its container, and the box's ~/code checkout is the human's
# (ssh, herdr, T3). They meet through the git remote.
#
# Runs from the host or from inside the paperclip container (the DevOps
# agent); 127.0.0.1:3100 is Paperclip from either side.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"   # repo root: templates/, local/
PAPERCLIP="${PAPERCLIP:-http://127.0.0.1:3100}"
PC_NAME="${PC_NAME:-paperclip}"          # the Paperclip container, from the host side
PC_USER=paperclip
REMOTE_PATH=/home/pixel/paperclip        # where Paperclip stages runs on the box

usage() {
  cat <<'EOF'
Usage: scripts/newproject.sh <name> <org/repo> [<org/repo>...] [options]
       scripts/newproject.sh --check | --capacity | --help

Options:
  --company NAME|ID         Paperclip company (default: the only one)
  --prodmgr-adapter claude|codex      Product Manager runtime (default: claude)
  --prodmgr-model MODEL               adapter model (default: the adapter's own default)
  --prodmgr-instructions FILE         AGENTS.md template (default: templates/product-manager.md)
  --reports-to NAME|ID                Product Manager's manager (default: the company's CEO, if any)
  --budget DOLLARS                    monthly budget for the Product Manager (default: none set)
  --egress agent            passed to newbox.sh
  --no-auth                 passed to newbox.sh
  --no-kickoff              skip the kickoff issue
  --dry-run                 show what exists and what would be created
EOF
}

# ----------------------------------------------------------------- arguments
MODE=run
NAME=""; REPOS=()
COMPANY=""; PRODMGR_ADAPTER=claude; PRODMGR_MODEL=""; REPORTS_TO=""; BUDGET=""
PRODMGR_TEMPLATE="$ROOT/templates/product-manager.md"
NEWBOX_ARGS=(); KICKOFF=1; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --check) MODE=check; shift ;;
    --capacity) MODE=capacity; shift ;;
    --company) COMPANY="${2:?}"; shift 2 ;;
    --prodmgr-adapter) PRODMGR_ADAPTER="${2:?}"; shift 2 ;;
    --prodmgr-model) PRODMGR_MODEL="${2:?}"; shift 2 ;;
    --prodmgr-instructions) PRODMGR_TEMPLATE="${2:?}"; shift 2 ;;
    --reports-to) REPORTS_TO="${2:?}"; shift 2 ;;
    --budget) BUDGET="${2:?}"; shift 2 ;;
    --egress) NEWBOX_ARGS+=(--egress "${2:?}"); shift 2 ;;
    --no-auth) NEWBOX_ARGS+=(--no-auth); shift ;;
    --no-kickoff) KICKOFF=0; shift ;;
    --dry-run) DRY=1; shift ;;
    -*) echo "Unknown option: $1"; usage; exit 1 ;;
    *)
      if [[ -z "$NAME" ]]; then NAME="$1"
      elif [[ "$1" == */* ]]; then REPOS+=("$1")
      else echo "Expected org/repo, got: $1"; exit 1
      fi
      shift ;;
  esac
done

step() { echo; echo "==> $*"; }
info() { echo "    $*"; }
die()  { echo "    !! $*" >&2; exit 1; }

# Run a shell command as the Paperclip user, in its container. From inside the
# container that is just this shell.
if [[ -d "$HOME/.paperclip/instances" ]]; then
  pc_sh() { bash -lc "$1"; }
else
  pc_sh() { incus exec "$PC_NAME" --project default -- su - "$PC_USER" -c "$1"; }
fi

# api METHOD PATH [JSON] -> response body on stdout; dies on HTTP >= 400.
api() {
  local method="$1" path="$2" body="${3:-}" out code
  out=$(mktemp)
  code=$(curl -sS -o "$out" -w '%{http_code}' -X "$method" "$PAPERCLIP/api$path" \
    -H 'Content-Type: application/json' ${body:+--data "$body"}) \
    || { rm -f "$out"; die "cannot reach Paperclip at $PAPERCLIP"; }
  if [[ "$code" -ge 400 ]]; then
    echo "    !! $method $path -> HTTP $code: $(head -c 600 "$out")" >&2
    rm -f "$out"; return 1
  fi
  cat "$out"; rm -f "$out"
}

to_mib() {  # "20.00GiB" / "512.00MiB" / "UNLIMITED" -> integer MiB (0 = unlimited)
  awk -v v="$1" 'BEGIN {
    if (v ~ /UNLIMITED/) { print 0; exit }
    n = v + 0
    if (v ~ /TiB/) n *= 1048576; else if (v ~ /GiB/) n *= 1024; else if (v ~ /KiB/) n /= 1024
    else if (v ~ /B$/ && v !~ /MiB/) n /= 1048576
    printf "%d\n", n }'
}

# ---------------------------------------------------------------- preflight
COMPANY_ID=""
preflight() {
  curl -fsS -o /dev/null "$PAPERCLIP/api/health" || die "Paperclip is not answering at $PAPERCLIP"
  command -v pixels >/dev/null || die "pixels not found (host-setup.sh / paperclip-up.sh install it)"

  local companies; companies=$(api GET /companies) || exit 1
  if [[ -n "$COMPANY" ]]; then
    COMPANY_ID=$(jq -r --arg c "$COMPANY" \
      '.[] | select(.id == $c or (.name | ascii_downcase) == ($c | ascii_downcase)) | .id' <<<"$companies" | head -1)
    [[ -n "$COMPANY_ID" ]] || die "no company '$COMPANY'"
  else
    local n; n=$(jq length <<<"$companies")
    [[ "$n" -eq 1 ]] || die "$n companies; pick one with --company"
    COMPANY_ID=$(jq -r '.[0].id' <<<"$companies")
  fi
  info "company: $(jq -r --arg id "$COMPANY_ID" '.[] | select(.id == $id) | .name' <<<"$companies")"

  # The server does not enforce this flag -- it only hides environments in the
  # UI -- but provisioning things the operator cannot see is worse than
  # stopping, so it is checked rather than flipped.
  local exp; exp=$(api GET /instance/settings/experimental) || exit 1
  if [[ "$(jq -r '.enableEnvironments // false' <<<"$exp")" == true ]]; then
    info "SSH environments: enabled"
  elif [[ $DRY -eq 1 || "$MODE" == check ]]; then
    info "SSH environments: OFF -- a real run would stop here (Settings -> Instance settings -> Experimental)"
    PREFLIGHT_FAILED=1
  else
    die "SSH environments are off. Enable Settings -> Instance settings -> Experimental -> environments, then re-run."
  fi
}

if [[ "$MODE" == capacity ]]; then
  # used_mib limit_mib per_box_mib, for provision.sh's capacity check.
  project=$(sed -n 's/^project *= *"\(.*\)"/\1/p' "$HOME/.config/pixels/config.toml" | head -1)
  per_box=$(sed -n 's/^memory *= *\([0-9]*\).*/\1/p' "$HOME/.config/pixels/config.toml" | head -1)
  row=$(incus project info "${project:-agents}" --format csv | grep '^MEMORY,')
  echo "$(to_mib "$(cut -d, -f3 <<<"$row")") $(to_mib "$(cut -d, -f2 <<<"$row")") ${per_box:-4096}"
  exit 0
fi

step "Preflight"
PREFLIGHT_FAILED=0
preflight
[[ "$MODE" == check ]] && exit "$PREFLIGHT_FAILED"

# -------------------------------------------------------------- validation
[[ -n "$NAME" ]] || { usage; exit 1; }
[[ "$NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "name must be lowercase letters, digits and dashes"
[[ ${#REPOS[@]} -gt 0 ]] || die "give at least one org/repo"
case "$PRODMGR_ADAPTER" in claude|codex) ;; *) die "--prodmgr-adapter is claude or codex" ;; esac
[[ -f "$PRODMGR_TEMPLATE" ]] || die "no Product Manager template at $PRODMGR_TEMPLATE"
ADAPTER_TYPE="${PRODMGR_ADAPTER}_local"
HOSTALIAS="px-$NAME"
AGENT_NAME="${NAME^} Product Manager"
[[ $DRY -eq 1 ]] && info "dry run: nothing will be changed"

# ------------------------------------------------------------------- 1. box
step "1. Box $HOSTALIAS"
BOX_NEW=0
if pixels list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$NAME"; then
  info "exists (repos are not re-checked; use ssh $HOSTALIAS to add one)"
elif [[ $DRY -eq 1 ]]; then
  info "would create with: newbox.sh $NAME ${REPOS[*]/#/--repo } ${NEWBOX_ARGS[*]:-}"
else
  repo_args=(); for r in "${REPOS[@]}"; do repo_args+=(--repo "$r"); done
  # herdr registration is for the human's sidebar; leave it to newbox.sh's own
  # default when run by hand.
  "$HERE/newbox.sh" "$NAME" "${repo_args[@]}" ${NEWBOX_ARGS[@]+"${NEWBOX_ARGS[@]}"}
  BOX_NEW=1
fi

# -------------------------------------------------------------- 2. host key
# Paperclip connects with StrictHostKeyChecking=yes, which only passes if the
# key is already in the Paperclip user's known_hosts.pixels. newbox.sh records
# it there when it runs inside the container, but not when run from the host.
# A freshly created box has a fresh key, so drop any stale entry first.
step "2. Host key in Paperclip"
if [[ $DRY -eq 1 ]]; then
  info "would record $HOSTALIAS's host key for $PC_USER"
else
  pc_sh "
    [ $BOX_NEW -eq 1 ] && { ssh-keygen -R $HOSTALIAS -f ~/.ssh/known_hosts.pixels; ssh-keygen -R $HOSTALIAS.incus -f ~/.ssh/known_hosts.pixels; } >/dev/null 2>&1
    ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new $HOSTALIAS true" \
    && info "ok" || die "Paperclip cannot ssh to $HOSTALIAS (key not authorized? run paperclip-up.sh, then re-run)"
fi

# ------------------------------------------------------------- 3. checkouts
# gh when the container has a token (private repos), plain HTTPS otherwise.
step "3. Paperclip-side checkouts"
for repo in "${REPOS[@]}"; do
  dir="~/code/$repo"
  if [[ $DRY -eq 1 ]]; then
    pc_sh "[ -d $dir/.git ]" 2>/dev/null && info "$repo: exists" || info "$repo: would clone to $dir"
    continue
  fi
  pc_sh "
    set -e
    if [ -d $dir/.git ]; then echo '    $repo: exists'; exit 0; fi
    mkdir -p \$(dirname $dir)
    if gh auth status >/dev/null 2>&1; then gh repo clone $repo $dir -- --quiet
    else git clone --quiet https://github.com/$repo.git $dir; fi
    echo '    $repo: cloned'" || die "could not clone $repo in $PC_NAME (private? seed a gh token: seed-agent-auth.sh --incus $PC_NAME:$PC_USER)"
done
PC_HOME=$(pc_sh 'echo $HOME')

# ----------------------------------------------------------- 4. environment
step "4. Environment $NAME"
ENV_ID=$(api GET "/companies/$COMPANY_ID/environments" \
  | jq -r --arg n "$NAME" '.[] | select(.name == $n and .driver == "ssh") | .id' | head -1)
# The long-lived Claude token (set-claude-token.sh) is bound on the
# environment, so every agent run on this box gets CLAUDE_CODE_OAUTH_TOKEN.
TOKEN_SECRET_ID=$(api GET "/companies/$COMPANY_ID/secrets" | jq -r '(if type == "array" then . else (.secrets // .items // []) end)
  | .[] | select(.name == "claude-oauth-token") | .id' | head -1)
[[ -n "$TOKEN_SECRET_ID" ]] || info "note: no claude-oauth-token secret; claude agents will fail to authenticate (run scripts/set-claude-token.sh)"
if [[ -n "$ENV_ID" ]]; then
  info "exists ($ENV_ID)"
elif [[ $DRY -eq 1 ]]; then
  info "would create: ssh pixel@$HOSTALIAS, staging in $REMOTE_PATH"
else
  # No key or known_hosts in the config: Paperclip then runs plain `ssh` as
  # its own user, so ~/.ssh/config's px-* block, key and known_hosts.pixels
  # apply.
  body=$(jq -n --arg n "$NAME" --arg h "$HOSTALIAS" --arg p "$REMOTE_PATH" --arg s "$TOKEN_SECRET_ID" '{
    name: $n, driver: "ssh",
    description: "Project container \($h), created by newproject.sh",
    config: {host: $h, port: 22, username: "pixel", remoteWorkspacePath: $p,
             strictHostKeyChecking: true}}
    + (if $s == "" then {} else {envVars: {CLAUDE_CODE_OAUTH_TOKEN: {type: "secret_ref", secretId: $s}}} end)')
  ENV_ID=$(api POST "/companies/$COMPANY_ID/environments" "$body" | jq -r .id)
  info "created ($ENV_ID)"
fi
if [[ -n "$ENV_ID" && -n "$TOKEN_SECRET_ID" && $DRY -eq 0 ]]; then
  env_json=$(api GET "/environments/$ENV_ID")
  if [[ "$(jq -r '.envVars.CLAUDE_CODE_OAUTH_TOKEN.secretId // empty' <<<"$env_json")" != "$TOKEN_SECRET_ID" ]]; then
    api PATCH "/environments/$ENV_ID" "$(jq --arg s "$TOKEN_SECRET_ID" \
      '{envVars: ((.envVars // {}) + {CLAUDE_CODE_OAUTH_TOKEN: {type: "secret_ref", secretId: $s}})}' <<<"$env_json")" >/dev/null
    info "Claude token bound"
  fi
fi
if [[ -n "$ENV_ID" && $DRY -eq 0 ]]; then
  probe=$(api POST "/environments/$ENV_ID/probe" '{}') || die "probe request failed"
  [[ "$(jq -r .ok <<<"$probe")" == true ]] \
    && info "probe: $(jq -r .summary <<<"$probe")" \
    || die "probe failed: $(jq -c '.summary, .details.error' <<<"$probe")"
fi

# ------------------------------------------------------ 5. Product Manager
step "5. Agent \"$AGENT_NAME\""
AGENTS=$(api GET "/companies/$COMPANY_ID/agents")
AGENT_ID=$(jq -r --arg n "$AGENT_NAME" '.[] | select(.name == $n) | .id' <<<"$AGENTS" | head -1)
if [[ -n "$REPORTS_TO" ]]; then
  MANAGER_ID=$(jq -r --arg m "$REPORTS_TO" \
    '.[] | select(.id == $m or (.name | ascii_downcase) == ($m | ascii_downcase)) | .id' <<<"$AGENTS" | head -1)
  [[ -n "$MANAGER_ID" ]] || die "no agent '$REPORTS_TO' to report to"
else
  MANAGER_ID=$(jq -r '[.[] | select(.role == "ceo")][0].id // empty' <<<"$AGENTS")
fi
MANAGER_NAME=$(jq -r --arg id "${MANAGER_ID:-none}" '.[] | select(.id == $id) | .name' <<<"$AGENTS")

if [[ -n "$AGENT_ID" ]]; then
  info "exists ($AGENT_ID)"
  cur_env=$(jq -r --arg id "$AGENT_ID" '.[] | select(.id == $id) | .defaultEnvironmentId // empty' <<<"$AGENTS")
  [[ -z "$ENV_ID" || "$cur_env" == "$ENV_ID" ]] || info "note: its environment is not '$NAME'; left as is"
elif [[ $DRY -eq 1 ]]; then
  info "would hire: Product Manager, $ADAPTER_TYPE, reports to ${MANAGER_NAME:-nobody (no CEO; use --reports-to)}"
else
  # The instructions become the agent's AGENTS.md. They are rendered here, and
  # Paperclip stores them on its side and uploads them with every run.
  repo_list=""
  for r in "${REPOS[@]}"; do repo_list+="- \`$r\` (https://github.com/$r)"$'\n'; done
  instructions=$(<"$PRODMGR_TEMPLATE")
  instructions="${instructions//\{\{PROJECT\}\}/$NAME}"
  instructions="${instructions//\{\{REPOS\}\}/${repo_list%$'\n'}}"
  # engine=cli: the adapters default to their ACP engine, which runs only on
  # sandbox targets and fails on SSH ones with adapter_engine_unavailable.
  adapter_config=$(jq -n --arg m "$PRODMGR_MODEL" '{engine: "cli"} + (if $m == "" then {} else {model: $m} end)')
  budget_cents=0; [[ -n "$BUDGET" ]] && budget_cents=$(awk -v d="$BUDGET" 'BEGIN { printf "%d", d * 100 }')
  # role "pm" is the fixed value Paperclip uses for a product manager.
  body=$(jq -n --arg n "$AGENT_NAME" --arg t "$ADAPTER_TYPE" --arg env "$ENV_ID" \
    --arg mgr "$MANAGER_ID" --arg md "$instructions" --argjson ac "$adapter_config" \
    --argjson b "$budget_cents" --arg p "$NAME" '{
      name: $n, role: "pm", title: "Product Manager, \($p)",
      adapterType: $t, adapterConfig: $ac, defaultEnvironmentId: $env,
      reportsTo: (if $mgr == "" then null else $mgr end),
      budgetMonthlyCents: $b,
      instructionsBundle: {entryFile: "AGENTS.md", files: {"AGENTS.md": $md}}}')
  AGENT_ID=$(api POST "/companies/$COMPANY_ID/agents" "$body" | jq -r .id)
  info "hired ($AGENT_ID), reports to ${MANAGER_NAME:-nobody -- no CEO yet; set it in the UI or use --reports-to}"
fi

# ---------------------------------------------------------------- 6. project
step "6. Project $NAME"
PROJECT_ID=$(api GET "/companies/$COMPANY_ID/projects" \
  | jq -r --arg n "$NAME" '.[] | select(.name == $n) | .id' | head -1)
workspace_json() {  # workspace_json org/repo primary(true|false)
  jq -n --arg r "$1" --arg cwd "$PC_HOME/code/$1" --argjson primary "$2" '{
    name: $r, sourceType: "git_repo", cwd: $cwd,
    repoUrl: "https://github.com/\($r)", isPrimary: $primary}'
}
if [[ -n "$PROJECT_ID" ]]; then
  info "exists ($PROJECT_ID)"
elif [[ $DRY -eq 1 ]]; then
  info "would create: lead $AGENT_NAME, workspaces ${REPOS[*]} (primary ${REPOS[0]})"
else
  body=$(jq -n --arg n "$NAME" --arg lead "$AGENT_ID" --argjson ws "$(workspace_json "${REPOS[0]}" true)" \
    --arg repos "${REPOS[*]}" '{
      name: $n, status: "planned", leadAgentId: $lead, workspace: $ws,
      description: "Repos: \($repos). Container: px-\($n). Created by newproject.sh."}')
  PROJECT_ID=$(api POST "/companies/$COMPANY_ID/projects" "$body" | jq -r .id)
  info "created ($PROJECT_ID), primary workspace ${REPOS[0]}"
  for r in "${REPOS[@]:1}"; do
    api POST "/projects/$PROJECT_ID/workspaces" "$(workspace_json "$r" false)" >/dev/null
    info "workspace $r added"
  done
fi

# ---------------------------------------------------------------- 7. kickoff
# idempotencyKey makes a re-run return the same issue rather than a second one.
# Assigning it with status todo wakes the Product Manager immediately.
step "7. Kickoff issue"
if [[ $KICKOFF -eq 0 ]]; then
  info "skipped (--no-kickoff)"
elif [[ $DRY -eq 1 ]]; then
  info "would assign \"Kickoff: learn $NAME and write its roadmap\" to $AGENT_NAME"
else
  desc="You are the new Product Manager for **$NAME**. Before planning anything:

1. Read the repos (${REPOS[*]}): README, CLAUDE.md / AGENTS.md, docs, recent history, open issues and PRs.
2. Write \`docs/ROADMAP.md\` and \`docs/STATE.md\` as described in your instructions (or update the repo's existing equivalents).
3. Open a pull request with them, and comment here with the PR link plus the three things you think matter most next and any questions for the operator.

Do not start implementation work in this issue."
  body=$(jq -n --arg p "$PROJECT_ID" --arg a "$AGENT_ID" --arg n "$NAME" --arg d "$desc" '{
    title: "Kickoff: learn \($n) and write its roadmap", description: $d,
    projectId: $p, assigneeAgentId: $a, status: "todo", priority: "high",
    idempotencyKey: "newproject:\($n):kickoff"}')
  issue=$(api POST "/companies/$COMPANY_ID/issues" "$body")
  info "$(jq -r '.identifier // .id' <<<"$issue") assigned to $AGENT_NAME"
fi

step "Ready"
echo "  UI:      $PAPERCLIP  (project $NAME, agent \"$AGENT_NAME\")"
echo "  box:     ssh $HOSTALIAS"
[[ "$PRODMGR_ADAPTER" == codex ]] && echo "  note:    codex runs upload the Paperclip container's codex login; it must have one"
true
