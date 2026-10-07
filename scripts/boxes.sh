#!/usr/bin/env bash
# Create every box listed in a manifest that does not exist yet.
#
#   scripts/boxes.sh [manifest] [--dry-run]      # default: local/boxes.manifest
#
# Format: examples/boxes.manifest. Each line is `<name> <org/repo>...
# [newbox.sh options]`.
#
# A box that already exists is left alone, apart from making sure it is
# running: it is your work in progress, and rebuilding one is a decision for
# you (pixels destroy <name>, then run this again). Boxes in the project that
# the manifest does not list are reported, never removed.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
MANIFEST="$ROOT/local/boxes.manifest"; DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) MANIFEST="$a" ;;
  esac
done
[[ -f "$MANIFEST" ]] || { echo "No manifest at $MANIFEST (scripts/list-repos.sh writes one)."; exit 1; }

existing=$(pixels list 2>/dev/null | awk 'NR>1 {print $1 " " $2}')
listed=()

# fd 3: newbox.sh and pixels read stdin, which would eat the rest of the file.
while IFS= read -r line <&3; do
  line="${line%%#*}"
  [[ -z "${line//[[:space:]]/}" ]] && continue
  eval "words=($line)"
  name="${words[0]}"; args=()
  for w in "${words[@]:1}"; do
    if [[ "$w" == */* && "$w" != -* ]]; then args+=(--repo "$w"); else args+=("$w"); fi
  done
  listed+=("$name")

  state=$(awk -v n="$name" '$1 == n {print $2}' <<<"$existing")
  if [[ -n "$state" ]]; then
    if [[ "$state" == RUNNING ]]; then
      echo "px-$name: exists"
    else
      echo "px-$name: exists ($state); starting it"
      [[ $DRY -eq 1 ]] || pixels start "$name" >/dev/null
    fi
    continue
  fi
  echo "px-$name: creating"
  if [[ $DRY -eq 1 ]]; then
    echo "    scripts/newbox.sh $name ${args[*]}"
  else
    "$HERE/newbox.sh" "$name" "${args[@]}"
  fi
done 3< "$MANIFEST"

for b in $(awk '$1 != "base" {print $1}' <<<"$existing"); do
  [[ " ${listed[*]} " == *" $b "* ]] || echo "px-$b: not in the manifest (left alone)"
done
