# Shared helpers for running things inside a box as its `pixel` user.
# Sourced, not executed.
#
# Everything goes through `incus exec` rather than SSH: it needs no keys, no
# DNS and no sshd, and it is the same command herdr panes run, so a helper
# that works here works in a pane.

PROJECT="${PROJECT:-agents}"
PIXEL_HOME=/home/pixel

# The pixel user's UID inside the box. pixels creates it as the first user
# (1000 on Debian), but look it up rather than assume, and cache per box.
declare -A _BOX_UID=()
box_uid() {
  local name="$1"
  if [[ -z "${_BOX_UID[$name]:-}" ]]; then
    _BOX_UID[$name]=$(incus exec "px-$name" --project "$PROJECT" -T -- id -u pixel </dev/null) \
      || { echo "px-$name: no pixel user (is the box running? pixels start $name)" >&2; return 1; }
  fi
  echo "${_BOX_UID[$name]}"
}

# The argv that runs a login shell as pixel in the box, in directory $2.
# A login shell, because that is what reads ~/.profile (the Claude token
# hook) and /etc/profile.d (mise's shims); `incus exec --user` alone starts
# the program with neither.
box_argv() {  # box_argv <name> <cwd> -> fills BOX_ARGV
  local name="$1" cwd="$2" uid
  uid=$(box_uid "$name") || return 1
  BOX_ARGV=(incus exec "px-$name" --project "$PROJECT" --user "$uid" --group "$uid"
            --env "HOME=$PIXEL_HOME" --cwd "$cwd")
}

# Run a shell snippet as pixel, without a terminal. -T matters: incus exec
# otherwise reads the caller's stdin, which swallows the input of any loop
# around it.
box_sh() {  # box_sh <name> <snippet>
  box_argv "$1" "$PIXEL_HOME" || return 1
  "${BOX_ARGV[@]}" -T -- bash -lc "$2"
}

# The same, attached to this terminal, for interactive sign-ins.
box_sh_tty() {
  box_argv "$1" "$PIXEL_HOME" || return 1
  "${BOX_ARGV[@]}" -t -- bash -lc "$2"
}

# Subscriptions only: refuse to go on if an API key is in the environment
# here or in the box's login environment. Either would quietly switch an
# agent to per-token billing.
no_api_keys() {  # no_api_keys [box]
  local found=""
  [[ -n "${ANTHROPIC_API_KEY:-}" ]] && found+=" ANTHROPIC_API_KEY(host)"
  [[ -n "${OPENAI_API_KEY:-}" ]] && found+=" OPENAI_API_KEY(host)"
  if [[ -n "${1:-}" ]]; then
    found+=$(box_sh "$1" 'for v in ANTHROPIC_API_KEY OPENAI_API_KEY; do
      [ -n "$(printenv $v)" ] && printf " %s(px-'"$1"')" "$v"; done; true' </dev/null)
  fi
  if [[ -n "$found" ]]; then
    echo "API key(s) set:$found. Agents here run on subscriptions only; remove them and retry." >&2
    return 1
  fi
}
