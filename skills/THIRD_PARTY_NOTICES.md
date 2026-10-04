# Third-party notices

## dbaggott/claude-plugins

Source: https://github.com/dbaggott/claude-plugins, commit
`9a4c0b72c83ac8307d66338808f32077a923136c`.
Copyright 2026 Dan Baggott. Licensed under the Apache License, Version 2.0; a copy
of the license is in [`LICENSE-dbaggott-claude-plugins`](LICENSE-dbaggott-claude-plugins).

The skills below are derivative works of files from that repository. **They
have been modified** from the originals, as each `SKILL.md` also states in its
opening attribution block.

| Skill in this repo | Adapted from (paths in the source repo) |
|---|---|
| `issue-writing/` | `dnbg-workflow/skills/issue-workflow/SKILL.md`, `dnbg-workflow/skills/issue-workflow/references/creating.md`, `dnbg-workflow/always-on-rules.md` |
| `spec-review/` | `dnbg-workflow/skills/issue-reviewer/SKILL.md`, `dnbg-workflow/skills/issue-reviewer/references/rounds.md`, `dnbg-workflow/skills/issue-workflow/references/spec-review-rounds.md` |
| `pull-requests/` | `dnbg-workflow/skills/issue-workflow/references/resolving.md`, `dnbg-workflow/skills/git-workflow/SKILL.md`, `dnbg-workflow/skills/git-workflow/references/review-rounds.md`, `dnbg-workflow/skills/git-workflow/references/merge.md`, `dnbg-workflow/always-on-rules.md` |
| `code-review/` | `dnbg-workflow/skills/reviewer/SKILL.md`, `dnbg-workflow/skills/reviewer/references/re-review.md`, `dnbg-workflow/always-on-rules.md` |

### Modifications, in general terms

- Restructured and condensed into four skills with different names and
  boundaries, written as plain Agent Skills usable by any agent harness.
- Removed the source plugin's process plumbing: enforcement hooks and settings,
  worktree configuration, issue claim labels, background watchers and polling
  scripts, the reviewer GitHub App setup and token minting, interactive operator
  prompts, version stamps, merge-command composition, and references to the
  source plugin's scripts and skill names.
- Adapted to an unattended, multi-agent setting: each run ends with a handoff by
  reassigning a Paperclip issue; reviewing roles post through a shared bot
  (`gh-bot`) and identify themselves with a role header; review rounds are
  reconstructed from GitHub state rather than session memory.
- Added role-specific review emphasis (Lead Engineer, UI Designer, QA Lead,
  Security) and references to this repo's own skills (`team-workflow`,
  `github-bot`).

### Used by reference, not copied

`coding-practices` (`dnbg-practices/skills/coding-practices/` in the same source
repository) is used unmodified, by reference to a pinned commit. It is not
copied into this directory; the skills above refer to it by name.
