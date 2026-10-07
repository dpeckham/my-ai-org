# Working in this repo

This repo installs a terminal control plane for running many coding agents
at once: one Incus box per repo (via pixels), one git worktree per task, and
herdr on the host showing every agent in one sidebar. `./install.sh` builds
it all from a bare Linux machine, for its owner and for anyone else. The
README is the manual; keep it true.

Layout: `install.sh` and the docs at the top; every other script in
`scripts/` (shared helpers in `scripts/lib/`); the manifest format in
`examples/`; machine-local files (real repo lists) in the gitignored
`local/`. New scripts go in `scripts/`, and the top level stays this small.

## Rules for changes

- **No secrets.** No tokens, keys, certificates, passwords, or credential file
  contents — not even redacted examples that look real. Credentials are copied
  at run time by `seed-agent-auth.sh` and `codex-login.sh`; nothing persists
  them here, and the base template never holds any.
- **Subscriptions only.** Agents are the official `claude` and `codex` CLIs
  on the operator's subscriptions. Never set or suggest `ANTHROPIC_API_KEY`
  or `OPENAI_API_KEY`, and don't add third-party agent harnesses.
- **Nothing project-specific.** No project names, repo names, org names,
  hostnames, usernames, IPs, or worked examples tied to a particular project.
  Use placeholders (`px-foo`, `org/repo`, `<box>.local`, `<bridge-ip>`). Turn a
  lesson learned on a real project into a generic one before writing it down.
  Real repo lists live in `local/`, which is gitignored.
- **Docs move with code.** Any change to a script's behavior, flags, or
  defaults updates the README in the same commit. A non-obvious failure you
  hit and fixed goes under **Gotchas** with the symptom someone would search
  for.
- **Check herdr and pixels flags against the installed binaries**
  (`herdr <group> <cmd> --help`, `pixels <cmd> --help`) rather than docs for
  a newer release.
- **Re-running must upgrade, not just skip.** `git pull && ./install.sh` is the
  upgrade path, so anything a script creates must be reconciled on later runs.
  The exception is boxes: they hold work in progress, so nothing rebuilds or
  destroys one without the operator asking.
- Scripts stay idempotent and keep their existing style: `set -euo pipefail`,
  `step` headings, comments that explain *why*.

## If you are an agent running in a box

You are in a git worktree (`~/worktrees/<repo>/<task>`) inside an Incus
container, started by `scripts/task` in a herdr pane on the host. You cannot
reach the host, herdr or other boxes, and should not try. Work on your
task's branch; the worktree's directory name is the branch name.
