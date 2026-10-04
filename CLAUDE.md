# Working in this repo

This repo installs a complete AI-agent organisation for operators with more
projects than they can track: Paperclip as the control plane, one Incus
container per project, and agents (Chief of Staff, DevOps, a PM per project,
and other roles as needed) working in the background and surfacing what needs
a human. `./install.sh` builds it all from a bare Linux machine, for its owner
and for anyone else. The README is the manual; keep it true.

Layout: `install.sh` and the docs at the top; every other script in
`scripts/`; agent instructions in `templates/`; the manifest format in
`examples/`; machine-local files (real project lists) in the gitignored
`local/`. New scripts go in `scripts/`, and the top level stays this small.

## Rules for changes

- **No secrets.** No tokens, keys, certificates, passwords, or credential file
  contents — not even redacted examples that look real. Credentials are copied
  at run time by `seed-agent-auth.sh`; nothing persists them here.
- **Nothing project-specific.** No project names, repo names, org names,
  hostnames, usernames, IPs, or worked examples tied to a particular project.
  Use placeholders (`px-foo`, `org/repo`, `<box>.local`, `<bridge-ip>`). Turn a
  lesson learned on a real project into a generic one before writing it down.
  Real project lists live in `local/`, which is gitignored.
- **Docs move with code.** Any change to a script's behavior, flags, or
  defaults updates the README in the same commit. A non-obvious failure you
  hit and fixed goes under **Gotchas** with the symptom someone would search
  for.
- Scripts stay idempotent and keep their existing style: `set -euo pipefail`,
  `step` headings, comments that explain *why*.

## If you are Paperclip's DevOps agent

You run inside the `paperclip` container as the `paperclip` user, from this
repo's checkout. `pixels` and `incus` talk to the host's Incus daemon with a
certificate restricted to the `agents` project. You cannot see or change
anything outside it, and you should not try to.

Starting a project (box, Paperclip SSH environment, PM agent, project, and
kickoff issue in one go):

```
scripts/newproject.sh <name> <org/repo> [<org/repo>...]   # --dry-run first if unsure
scripts/provision.sh <manifest>                           # several, from a file
pixels list
```

- Every step is skipped when its object already exists, so re-running after
  a failure is safe. It never deletes anything, and neither should you without
  being asked: `pixels destroy` is for boxes you created yourself.
- The kickoff issue starts the new PM working at once. Pass `--no-kickoff`
  unless the operator asked for the project to get going.
- `newbox.sh` alone makes a box without the Paperclip side; use it for boxes
  that are not projects.
- The `agents` project is capped (memory is the binding limit; every box
  counts, running or not). If creation fails on a limit, report it rather than
  destroying boxes you did not create.
- Never change the base template (`base`) or its `ready` checkpoint unless
  asked; every future box inherits it.
