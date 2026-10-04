---
name: github-bot
description: How the reviewing roles (Product Manager, Lead Engineer, UI Designer, QA Lead, Security, CTO) act on GitHub as the company's bot instead of the operator — the `gh-bot` command. Load before posting any GitHub issue, comment or review when your role is not the Coder.
---

# GitHub bot

The company has one GitHub App, the **bot**. Every role except the Coder acts
on GitHub as the bot, so reviews and approvals come from an identity separate
from the operator's — GitHub never lets a PR's author approve it, and the Coder
authors as the operator.

## Use `gh-bot` wherever you would use `gh`

`gh-bot` takes exactly the same arguments as `gh`:

```
gh-bot issue create --title "…" --body-file issue.md
gh-bot issue comment https://github.com/<owner>/<repo>/issues/12 --body-file c.md
gh-bot pr review https://github.com/<owner>/<repo>/pull/34 --approve --body-file review.md
gh-bot pr review https://github.com/<owner>/<repo>/pull/34 --request-changes --body-file review.md
```

It is installed at `~/.local/bin/gh-bot`; if `gh-bot` alone is not found, call
it by that path. Each call mints a short-lived token limited to the one
repository it targets (from `--repo`, a full GitHub URL in the arguments, or
the current directory's `origin`), so it cannot act on other repositories.

Rules:

- **Start every body with your role in bold on its own line** —
  `**Lead Engineer review**`, `**UI Designer review**`, `**QA Lead review**`,
  `**Security review**`, `**Product Manager**`, `**CTO review**`. All reviewing roles share the bot,
  and the header is how humans tell you apart.
- **Prefer `--body-file`** over `--body` for anything longer than a line;
  quoting multi-line markdown through a shell argument goes wrong.
- **Never use plain `gh` for something the bot should sign.** Plain `gh` acts
  as the operator.
- **Never print, echo or log** `GITHUB_BOT_PRIVATE_KEY` or any token `gh-bot`
  mints.

## When it fails

- `not installed on <owner>/<repo>`: the bot's GitHub App is not installed on
  that repository's account. You cannot fix that; say so on the Paperclip issue
  and assign it to the operator. Do not fall back to plain `gh`.
- `GITHUB_BOT_APP_ID … not set`: your agent has not been given the bot's
  credentials. Report it the same way.
