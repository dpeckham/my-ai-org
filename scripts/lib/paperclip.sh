# Shared Paperclip helpers for the provisioning scripts. Source it; it is not
# meant to run on its own. Expects `info` and `die` to be defined by the caller.
#
# The one non-trivial thing here is ensure_agent, which creates an agent or
# brings an existing one into line, idempotently, so re-running the installer
# after a `git pull` upgrades every agent this repo manages:
#
#   - runtime, role, title, manager, environment and bot credentials are
#     reconciled on every run;
#   - instructions (AGENTS.md) are rewritten from the template only while they
#     are still exactly what this repo last wrote. Each agent's metadata keeps
#     the checksum of that text (metadata.myAiOrg.instructionsSha). If the
#     operator has edited the instructions since, they are left alone and the
#     run says so; RESET_INSTRUCTIONS=1 overwrites them anyway.

PAPERCLIP="${PAPERCLIP:-http://127.0.0.1:3100}"

# Roles that act on GitHub as the bot (gh-bot) rather than as the operator.
BOT_ROLES=" prodmgr lead-engineer ui-designer qa-lead security cto "

# api METHOD PATH [JSON]  -> body on stdout; returns 1 (with the error on
# stderr) on HTTP >= 400. JSON goes over stdin so secrets never reach argv.
api() {
  local out code
  out=$(mktemp)
  if [[ -n "${3:-}" ]]; then
    code=$(printf '%s' "$3" | curl -sS -o "$out" -w '%{http_code}' -X "$1" "$PAPERCLIP/api$2" \
      -H 'Content-Type: application/json' --data @-) || { rm -f "$out"; die "cannot reach Paperclip at $PAPERCLIP"; }
  else
    code=$(curl -sS -o "$out" -w '%{http_code}' -X "$1" "$PAPERCLIP/api$2") \
      || { rm -f "$out"; die "cannot reach Paperclip at $PAPERCLIP"; }
  fi
  if [[ "$code" -ge 400 ]]; then
    echo "    !! $1 $2 -> HTTP $code: $(head -c 500 "$out")" >&2
    rm -f "$out"; return 1
  fi
  cat "$out"; rm -f "$out"
}

# secret_id COMPANY_ID NAME -> id of the company secret with that name, or empty.
secret_id() {
  api GET "/companies/$1/secrets" | jq -r --arg n "$2" \
    '(if type == "array" then . else (.secrets // .items // []) end) | .[] | select(.name == $n) | .id' | head -1
}

# bot_env_json COMPANY_ID -> the env bindings that give an agent the bot
# (empty object until scripts/github-apps.sh has stored its credentials).
bot_env_json() {
  local app key
  app=$(secret_id "$1" github-bot-app-id)
  key=$(secret_id "$1" github-bot-private-key)
  if [[ -n "$app" && -n "$key" ]]; then
    jq -n --arg a "$app" --arg k "$key" '{
      GITHUB_BOT_APP_ID: {type: "secret_ref", secretId: $a},
      GITHUB_BOT_PRIVATE_KEY: {type: "secret_ref", secretId: $k}}'
  else
    echo '{}'
  fi
}

# render TEMPLATE -> stdout, filling {{PROJECT}}, {{REPOS}}, {{INFRA_REPO_DIR}}
# from the variables of the same names (empty if unset).
render() {
  local t; t=$(<"$1")
  t="${t//\{\{PROJECT\}\}/${PROJECT:-}}"
  t="${t//\{\{REPOS\}\}/${REPOS_MD:-}}"
  t="${t//\{\{INFRA_REPO_DIR\}\}/${INFRA_REPO_DIR:-}}"
  printf '%s' "$t"
}

sha() { printf '%s' "$1" | sha256sum | cut -c1-64; }

# ensure_agent: create or reconcile one agent; prints its id on stdout.
# Inputs come from these variables (set them, then call):
#   A_COMPANY A_NAME A_ROLE_KEY A_ROLE A_TITLE A_TEMPLATE A_MANAGER A_ENV
#   A_ADAPTER (claude_local|codex_local) A_EXTRA (JSON merged into adapterConfig)
#   A_PROJECT (project name, or empty for company-level agents)
#   A_BUDGET (monthly budget in cents, used on creation only; default 0)
ensure_agent() {
  local agents id cur body md new_sha cur_md cur_sha stored env_json adapter_cfg meta
  md=$(render "$A_TEMPLATE")
  new_sha=$(sha "$md")
  env_json='{}'
  [[ "$BOT_ROLES" == *" $A_ROLE_KEY "* ]] && env_json=$(bot_env_json "$A_COMPANY")
  local extra="${A_EXTRA:-}"; [[ -n "$extra" ]] || extra='{}'
  adapter_cfg=$(jq -n --argjson x "$extra" --argjson e "$env_json" \
    '{engine: "cli"} + $x + (if $e == {} then {} else {env: $e} end)')
  meta=$(jq -n --arg r "$A_ROLE_KEY" --arg p "${A_PROJECT:-}" --arg s "$new_sha" \
    '{myAiOrg: ({role: $r, instructionsSha: $s} + (if $p == "" then {} else {project: $p} end))}')

  agents=$(api GET "/companies/$A_COMPANY/agents")
  id=$(jq -r --arg n "$A_NAME" '.[] | select((.name | ascii_downcase) == ($n | ascii_downcase)) | .id' <<<"$agents" | head -1)

  if [[ -z "$id" ]]; then
    body=$(jq -n --arg n "$A_NAME" --arg r "$A_ROLE" --arg t "$A_TITLE" --arg a "${A_ADAPTER:-claude_local}" \
      --arg m "${A_MANAGER:-}" --arg env "${A_ENV:-}" --arg md "$md" --argjson ac "$adapter_cfg" --argjson meta "$meta" \
      --argjson b "${A_BUDGET:-0}" '{
        name: $n, role: $r, title: $t, adapterType: $a, adapterConfig: $ac, metadata: $meta,
        budgetMonthlyCents: $b,
        reportsTo: (if $m == "" then null else $m end),
        defaultEnvironmentId: (if $env == "" then null else $env end),
        instructionsBundle: {entryFile: "AGENTS.md", files: {"AGENTS.md": $md}}}')
    id=$(api POST "/companies/$A_COMPANY/agents" "$body" | jq -r .id)
    info "$A_NAME: hired ($id)" >&2
    echo "$id"; return
  fi

  cur=$(jq -c --arg id "$id" '.[] | select(.id == $id)' <<<"$agents")
  stored=$(jq -r '.metadata.myAiOrg.instructionsSha // empty' <<<"$cur")

  # Agents made by Paperclip's onboarding wizard are bound to an AI connection,
  # and Paperclip will not move them to another provider's runtime (no unbind;
  # a Claude connection trips its broken subscription check). Leave their
  # runtime, and their instructions, which this repo never wrote.
  if jq -e '(.runtimeConfig.aiConnection.provider // "anthropic") != "anthropic" and .adapterType != "claude_local"' <<<"$cur" >/dev/null; then
    api PATCH "/agents/$id" "$(jq -c --arg r "$A_ROLE" --arg t "$A_TITLE" --arg m "${A_MANAGER:-}" --argjson meta "$meta" '
      {role: $r, title: (.title // $t),
       reportsTo: (if $m == "" then .reportsTo else $m end),
       metadata: ((.metadata // {}) + {myAiOrg: ((.metadata.myAiOrg // {}) + ($meta.myAiOrg | del(.instructionsSha)))})}' <<<"$cur")" >/dev/null
    info "$A_NAME: exists ($id); role $A_ROLE. Runtime left as $(jq -r .adapterType <<<"$cur") (bound to a $(jq -r .runtimeConfig.aiConnection.provider <<<"$cur") AI connection Paperclip cannot switch)" >&2
    echo "$id"; return
  fi

  # Runtime, role, manager, environment, env bindings. Switching runtime keeps
  # managed instructions, skills, timeouts and history; only the other
  # adapter's own keys are dropped.
  body=$(jq -c --arg r "$A_ROLE" --arg t "$A_TITLE" --arg m "${A_MANAGER:-}" --arg env "${A_ENV:-}" \
    --arg a "${A_ADAPTER:-claude_local}" --argjson ac "$adapter_cfg" '
    {role: $r, title: (.title // $t),
     reportsTo: (if $m == "" then .reportsTo else $m end),
     defaultEnvironmentId: (if $env == "" then .defaultEnvironmentId else $env end)}
    + (if .adapterType == $a then
         {adapterConfig: ($ac + {env: ((.adapterConfig.env // {}) + ($ac.env // {}))})}
       else
         {adapterType: $a, replaceAdapterConfig: true,
          adapterConfig: ((.adapterConfig // {}) | with_entries(select(.key | test(
            "^(instructions|paperclipSkillSync|graceSec|timeoutSec|cwd)")))
            + $ac + {env: ((.adapterConfig.env // {}) + ($ac.env // {}))})}
       end)' <<<"$cur")
  api PATCH "/agents/$id" "$body" >/dev/null

  # Instructions: upgrade only what is still ours.
  cur_md=$(api GET "/agents/$id/instructions-bundle/file?path=AGENTS.md" | jq -r '.content // ""')
  cur_sha=$(sha "$cur_md")
  local note="instructions current"
  if [[ "$cur_sha" == "$new_sha" ]]; then
    :
  elif [[ "$cur_sha" == "$stored" || "${RESET_INSTRUCTIONS:-}" == 1 ]]; then
    api PUT "/agents/$id/instructions-bundle/file" "$(jq -n --arg c "$md" '{path: "AGENTS.md", content: $c}')" >/dev/null
    note="instructions upgraded from template"
  else
    note="instructions edited since this repo wrote them; left as is (RESET_INSTRUCTIONS=1 overwrites)"
    new_sha="$stored"   # keep tracking what we last wrote
  fi
  api PATCH "/agents/$id" "$(jq -c --argjson meta "$meta" --arg s "$new_sha" '
    {metadata: ((.metadata // {}) + {myAiOrg: ((.metadata.myAiOrg // {}) + $meta.myAiOrg + {instructionsSha: $s})})}' <<<"$cur")" >/dev/null
  info "$A_NAME: exists ($id); $note" >&2
  echo "$id"
}
