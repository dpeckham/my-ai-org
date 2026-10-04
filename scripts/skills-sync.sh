#!/usr/bin/env bash
# Load the skills in skills/sources.manifest into Paperclip's company skill
# library and attach each one to the agents whose role lists it. Idempotent:
# re-run it (install.sh does) after a `git pull` to pick up new and changed
# skills.
#
#   scripts/skills-sync.sh [--manifest FILE]
#
# Why Paperclip's library rather than installing skills into each runtime: it
# delivers the same skills to claude and codex agents alike, on whichever box
# they run, and a skill attached to a role reaches every agent with that role.
#
# Roles come from each agent's metadata.myAiOrg.role, which paperclip-org.sh
# and newproject.sh set. Agents without it (made by hand) are left alone.
#
# Runs on the host or inside the Paperclip container.

set -euo pipefail
shopt -s inherit_errexit

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
MANIFEST="$ROOT/skills/sources.manifest"
PC_NAME="${PC_NAME:-paperclip}"
PC_USER=paperclip
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="${2:?}"; shift 2 ;;
    *) echo "Usage: $0 [--manifest FILE]"; exit 1 ;;
  esac
done

step() { echo; echo "==> $*"; }
info() { echo "    $*"; }
die()  { echo "    !! $*" >&2; exit 1; }
. "$HERE/lib/paperclip.sh"

if [[ -d "$HOME/.paperclip/instances" ]]; then
  IN_PC=1; pc_sh() { bash -lc "$1"; }
else
  IN_PC=0; pc_sh() { incus exec "$PC_NAME" --project default -- su - "$PC_USER" -c "$1"; }
fi

curl -fsS -o /dev/null "$PAPERCLIP/api/health" || die "Paperclip is not answering at $PAPERCLIP"
companies=$(api GET /companies)
[[ "$(jq length <<<"$companies")" -eq 1 ]] || die "expected exactly one Paperclip company"
CID=$(jq -r '.[0].id' <<<"$companies")

# Paperclip only imports local skills from approved roots; the company's
# managed-skill directory is one, so local skills are copied there first.
MANAGED="/home/$PC_USER/.paperclip/instances/default/skills/$CID"

# ------------------------------------------------------------------- import
step "Importing skills from ${MANIFEST#$ROOT/}"
declare -A KEY=()           # skill name -> Paperclip skill key
declare -A ROLES=()         # skill name -> " role role ... "
pc_sh "install -d -m 700 '$MANAGED'"
# fd 3, not stdin: incus exec reads stdin and would swallow the manifest.
while IFS= read -r line <&3 || [[ -n "$line" ]]; do
  line="${line%%#*}"; read -r -a f <<<"$line"
  [[ ${#f[@]} -eq 0 ]] && continue
  [[ ${#f[@]} -ge 3 ]] || die "bad line (want: name source role...): $line"
  name="${f[0]}"; src="${f[1]}"; ROLES[$name]=" ${f[*]:2} "
  case "$src" in
    github:*@*)
      spec="${src#github:}"; ref="${spec##*@}"; path="${spec%@*}"
      owner_repo="$(cut -d/ -f1-2 <<<"$path")"; sub="$(cut -d/ -f3- <<<"$path")"
      source="https://github.com/$owner_repo/tree/$ref/$sub" ;;
    local:*)
      dir="$ROOT/${src#local:}"
      [[ -f "$dir/SKILL.md" ]] || die "$name: no SKILL.md in ${src#local:}"
      slug="$(basename "$dir")"
      if [[ $IN_PC -eq 1 ]]; then
        rm -rf "$MANAGED/$slug" && cp -r "$dir" "$MANAGED/$slug"
      else
        incus exec "$PC_NAME" --project default -- rm -rf "$MANAGED/$slug"
        incus file push -r -q "$dir" "$PC_NAME$MANAGED/" --project default
        incus exec "$PC_NAME" --project default -- chown -R "$PC_USER:$PC_USER" "$MANAGED/$slug"
      fi
      source="$MANAGED/$slug" ;;
    *) die "$name: unknown source '$src' (github:owner/repo/path@commit or local:dir)" ;;
  esac
  key=$(pc_sh "paperclipai skills import '$source' --company-id '$CID' --json" | jq -r '.imported[0].key // empty') \
    || die "$name: import failed"
  [[ -n "$key" ]] || die "$name: import returned no skill"
  KEY[$name]="$key"
  info "$name -> $key"
done 3< "$MANIFEST"

# ------------------------------------------------------------------- attach
step "Attaching skills to agents by role"
agents=$(api GET "/companies/$CID/agents")
while IFS=$'\t' read -r id aname role <&3; do
  [[ -z "$role" ]] && continue
  args=(); names=()
  for name in "${!KEY[@]}"; do
    [[ "${ROLES[$name]}" == *" $role "* ]] && { args+=(--skill "${KEY[$name]}"); names+=("$name"); }
  done
  [[ ${#args[@]} -eq 0 ]] && { info "$aname ($role): none"; continue; }
  pc_sh "paperclipai skills agent sync '$id' ${args[*]} --mode add --company-id '$CID' --json" >/dev/null \
    || die "could not attach skills to $aname"
  info "$aname ($role): $(printf '%s\n' "${names[@]}" | sort | tr '\n' ' ')"
done 3< <(jq -r '.[] | [.id, .name, (.metadata.myAiOrg.role // "")] | @tsv' <<<"$agents")

step "Done"
