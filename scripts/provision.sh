#!/usr/bin/env bash
# Provision a list of projects in one go.
#
#   scripts/provision.sh <manifest> [--dry-run]
#
# Each project line in the manifest is a newproject.sh command line minus the
# script name (see examples/projects.manifest). This script only adds the
# batch behaviour around it:
#
#   - a preflight that fails fast, before anything is created: manifest syntax,
#     Paperclip reachable with exactly one company, SSH environments enabled,
#     and enough memory left in the Incus project for the boxes to be added;
#   - one project failing does not stop the rest;
#   - a summary at the end. Re-running resumes: newproject.sh skips every step
#     whose object already exists.
#
# It never deletes anything. Removing a line from the manifest does not tear
# that project down.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${1:?Usage: $0 <manifest> [--dry-run]}"; shift
DRY=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=(--dry-run); shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done
[[ -f "$MANIFEST" ]] || { echo "No such manifest: $MANIFEST"; exit 1; }

step() { echo; echo "==> $*"; }

# ------------------------------------------------------------- parse manifest
# Lines go through bash's own word splitting (eval of a `set --`), so quoting
# behaves as it would on a command line. Comments are stripped by the same
# parser, which is why `#` inside quotes survives.
DEFAULTS=()
PROJECTS=()     # each entry: the raw line, re-parsed when run
lineno=0
while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$((lineno + 1))
  eval "set -- $line" 2>/dev/null || { echo "$MANIFEST:$lineno: cannot parse: $line"; exit 1; }
  [[ $# -eq 0 ]] && continue
  if [[ "$1" == "defaults" ]]; then
    shift; DEFAULTS+=("$@")
  else
    [[ $# -ge 2 && "$2" == */* ]] \
      || { echo "$MANIFEST:$lineno: want '<name> <org/repo> ...', got: $line"; exit 1; }
    PROJECTS+=("$line")
  fi
done < "$MANIFEST"
[[ ${#PROJECTS[@]} -gt 0 ]] || { echo "No projects in $MANIFEST."; exit 1; }

# ------------------------------------------------------------------ preflight
step "Preflight (${#PROJECTS[@]} projects)"
# newproject.sh --check runs the same reachability/company/flag checks it does
# before a real run, without touching anything.
"$HERE/newproject.sh" --check || [[ ${#DRY[@]} -gt 0 ]] || exit 1

# Capacity: newboxes needed x per-box memory must fit the project's remaining
# limits.memory. Boxes that already exist cost nothing new.
need=0
for line in "${PROJECTS[@]}"; do
  eval "set -- $line"
  pixels list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$1" || need=$((need + 1))
done
read -r used_mib limit_mib per_box_mib < <("$HERE/newproject.sh" --capacity)
if [[ "$limit_mib" -gt 0 ]]; then
  want=$((need * per_box_mib))
  left=$((limit_mib - used_mib))
  printf '    memory: %d new box(es) x %dMiB = %dMiB, %dMiB of %dMiB free\n' \
    "$need" "$per_box_mib" "$want" "$left" "$limit_mib"
  if [[ "$want" -gt "$left" ]]; then
    echo "    Not enough room. Raise it (AGENTS_MEMORY=... scripts/host-setup.sh) or destroy boxes."
    [[ ${#DRY[@]} -eq 0 ]] && exit 1
  fi
fi

# ----------------------------------------------------------------------- run
ok=(); failed=()
i=0
for line in "${PROJECTS[@]}"; do
  i=$((i + 1))
  eval "set -- $line"
  name="$1"; shift
  # Split the line into repos (leading org/repo words) and options, so
  # defaults can go between them and per-line options still come last.
  repos=()
  while [[ $# -gt 0 && "$1" == */* && "$1" != -* ]]; do repos+=("$1"); shift; done
  step "[$i/${#PROJECTS[@]}] $name"
  if "$HERE/newproject.sh" "$name" "${repos[@]}" ${DEFAULTS[@]+"${DEFAULTS[@]}"} "$@" ${DRY[@]+"${DRY[@]}"}; then
    ok+=("$name")
  else
    failed+=("$name")
    echo "    !! $name failed; continuing"
  fi
done

step "Summary"
echo "  ok:     ${#ok[@]}${ok[*]:+  (${ok[*]})}"
echo "  failed: ${#failed[@]}${failed[*]:+  (${failed[*]})}"
[[ ${#failed[@]} -eq 0 ]] || { echo "Re-run the same command to resume; finished steps are skipped."; exit 1; }
