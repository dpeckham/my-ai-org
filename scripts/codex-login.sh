#!/usr/bin/env bash
# Sign codex in to your ChatGPT subscription inside one box.
#
#   scripts/codex-login.sh <box>          # e.g. foo for px-foo
#
# Each box gets its own login rather than a copy of one: a ChatGPT login
# rotates its refresh token, so copies of one ~/.codex/auth.json log each
# other out, and codex has no long-lived token except an API key, which is
# per-token billing and not allowed here.
#
# Uses the device-code flow: it prints a URL and a code, you open the URL on
# any device and enter the code. Nothing needs a browser in the box. Skipped
# when the box is already signed in with ChatGPT.

set -euo pipefail

NAME="${1:?Usage: $0 <box>}"; NAME="${NAME#px-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/box.sh"

[[ -t 0 ]] || { echo "Run this in an interactive terminal; the sign-in needs you."; exit 1; }

status=$(box_sh "$NAME" 'codex login status 2>&1' </dev/null || true)
if [[ "$status" == *"ChatGPT"* ]]; then
  echo "px-$NAME: $status"
  exit 0
fi
[[ "$status" == *"API key"* ]] && echo "px-$NAME is signed in with an API key; replacing that with ChatGPT."

box_sh_tty "$NAME" 'codex login --device-auth'
box_sh "$NAME" 'codex login status' </dev/null
