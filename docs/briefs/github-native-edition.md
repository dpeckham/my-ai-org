# Brief: a GitHub-native edition (no Paperclip)

**Status:** answered and promoted. Written for the operator, 2026-10-04; the
decisions it led to are recorded in
[decisions/0004](../decisions/0004-github-native-is-the-single-project-edition.md),
which is the authoritative version. This brief is kept as the research behind
it, not as live direction.
**Continued in:** [briefs/agent-runtime.md](agent-runtime.md), which takes the
runtime apart — triggers, the wake, and the four kinds of context an agent
points at — and works out what it looks like on macOS and on Linux.
**Question asked:** could the product run with GitHub alone as the control
plane, for clients who have nowhere good to put the Paperclip half? Assume
every client can run one long-running script and one container (LXC, or
Apple's `container` on macOS) holding their project.

**Short answer:** yes, and for a *single-project* client it is arguably the
better shape. The pipeline, the six roles, the skills and the two GitHub
identities are already GitHub-native; Paperclip supplies the queue, the wake
and the human's inbox. GitHub can supply all three, but the obvious route —
GitHub's notification inbox — is gated behind the one credential type GitHub
is steering people away from. There is a better route that nobody uses: an
App's own webhook delivery log. The real cost is not the build, it is owning
two editions of the control plane for ever.

## 1. What is actually being replaced

It helps to be exact about how much of the product depends on Paperclip,
because it is less than it looks. Of the shipped system, Paperclip touches
only the coordination layer:

| Already GitHub-native, unaffected | Depends on Paperclip |
|---|---|
| The nine-handoff pipeline and the six roles | The work queue and its claims |
| `templates/` — every agent's instructions | Waking an agent with context |
| `skills/` and `sources.manifest` | Per-run workspace staging |
| The bot App, `gh-bot`, the two identities | Asking the human a question |
| Issues, PRs, labels, reviews, CI | Status (`in_progress` / `blocked` / …) |
| `docs/ROADMAP.md`, `STATE.md`, `decisions/` | Schedules (the CTO's weekly review) |
| The box, the base image, the trust boundary | Budgets, pause and cancel |
| | The cross-project board |

The IP is in the left column. Paperclip and GitHub are interchangeable
*transports* for the right column. That is the finding that makes this
tractable, and it is the argument for the recommendation in §8.

The port surface is genuinely small. Everything the agents do through
Paperclip reduces to seven verbs: **list my work, read a thread, comment,
set status, reassign, ask the human, create a child issue.** Plus two the
dispatcher needs: **claim** and **stage a workspace**.

## 2. How GitHub covers each verb

| Verb | GitHub replacement | Verdict |
|---|---|---|
| List my work | issues filtered by assignee + label | **good** |
| Read a thread | issue comments | **good** |
| Comment | issue comment, role header as today | **good** |
| Set status | a Project board Status field, or `state:*` labels | **good** |
| Reassign | change the assignee | **good** |
| Child issues | native sub-issues | **good** |
| Claim | assignee + `agent:running` label, single dispatcher | **adequate** — no atomicity, but one dispatcher means no race |
| Stage a workspace | `git worktree` or a fresh clone per run | **better than today** — GitHub is already the source of truth, so there is no copy-back step and nothing to leak |
| Ask the human | comment + `needs:operator`, answered in the thread or by email reply | **weaker** — see §4 |
| Schedules | a systemd timer in the box | **good** |
| Budgets, pause, cancel | nothing native | **gap** — see §6 |
| Cross-project board | an org-level Project across repos | **fine, and mostly moot** — see §7 |

Seven of twelve are straight swaps. Two are improvements. Two are gaps, and
one of those is a gap we already have.

## 3. The event source: how the dispatcher learns anything

This is the one real design decision. Three options, and the credential rules
decide it.

**(a) Poll each repo** — what `scripts/github-bridge.mjs` already does.
Works with a GitHub App installation token, which the bot already holds.
Costs one or two calls per repo per poll against a 5,000/hour budget. Needs a
local seen-state file, which the bridge already maintains. Proven in this
repo.

**(b) Poll the notification inbox** (`GET /notifications`) — the operator's
instinct, and on the merits the most elegant of the three. It is a work queue
with acknowledgement built in: `DELETE /notifications/threads/{id}` marks a
thread done and removes it from the inbox, so GitHub holds the cursor and the
local seen-state file disappears. It supports `Last-Modified` with `304 Not
Modified` on an unchanged inbox, so idle polling is close to free.

It has one disqualifying problem. The notifications endpoints **only support
a classic personal access token** — not fine-grained PATs, not GitHub App
user tokens, not App installation tokens
([docs](https://docs.github.com/en/rest/activity/notifications)). So the
dispatcher cannot be the bot. It would have to hold either the operator's
classic PAT (a broad, long-lived, barely-scopable credential on a box running
unattended agents — a clear step back from the per-repo-scoped tokens
`gh-bot` mints today) or a dedicated machine user's. Notifications are also
one of the handful of APIs with no fine-grained equivalent yet, and GitHub's
stated direction is fine-grained everywhere. Building the control plane's
event bus on it means building on the credential type GitHub is walking away
from.

**(c) Poll the App's own webhook delivery log** — `GET /app/hook/deliveries`,
`GET /app/hook/deliveries/{id}` for the payload, authenticated with a **JWT as
the App** ([docs](https://docs.github.com/en/rest/apps/webhooks)). Point the
App's webhook URL at something unreachable and read the delivery log instead.
This gives the full webhook event stream — every event type, with payloads —
with no inbound network access, no public URL, no classic PAT, no machine
user, and no extra credential beyond the App key the bot already has. It is
strictly richer than (a) and strictly better-credentialed than (b).

**Recommendation: (c), with (a) as the fallback.** Delivery-log retention is
not documented, so (c) needs a spike (§9) before it is load-bearing; if
retention turns out to be short, a dispatcher that is down for a weekend
misses events, and (a) degrades more gracefully. Build the dispatcher so the
event source is one swappable function either way.

## 4. The human in the loop

Paperclip gives the operator a UI with typed questions, approval gates and a
pause button. GitHub gives a notification inbox and email. The trade:

- **The inbox works, filtered.** `is:unread reason:mention` is the whole
  trick: the bot posts constantly, @mentions the human only when it needs
  them. Unfiltered, agent chatter buries the operator — this is the single
  most likely way a GitHub-native install fails in practice, and it is a
  configuration problem, not an architectural one.
- **Reply-by-email is a genuine win, not a consolation.** GitHub posts your
  emailed reply back into the thread
  ([since 2011](https://blog.github.com/2011-03-10-reply-to-comments-from-email/)).
  A client can answer their agents from a phone, with no app, no VPN, no
  localhost tunnel, nothing installed. Paperclip's UI cannot do that: it is
  reachable only from the host's loopback by design. For a client who travels
  or who is not the technical one, this edition is *more* reachable than the
  Paperclip one.
- **Approvals get cruder.** No typed answers, no expiry, no "wake only on
  accept". The workable substitute: the agent posts numbered options and
  waits on a `needs:operator` label; a reply or a 👍 reaction resolves it. Good
  enough for "which of these three?", poor for anything structured.
- **Nothing stops a run.** Covered in §6.

## 5. What the edition looks like

```
 the client's machine
 ┌─────────────────────────────────────────────────────────────┐
 │  one container (LXC, or Apple `container`)                   │
 │    the project's repos + toolchain + claude/codex            │
 │    a long-running dispatcher (systemd service + timer)       │
 │      ├─ reads events  ─────────────────────► GitHub         │
 │      ├─ claims an issue (assignee + label)                   │
 │      ├─ stages a git worktree per run                        │
 │      ├─ runs the role's agent there                          │
 │      └─ agent posts, reassigns, pushes a branch              │
 │    agent definitions + skills, committed in the repo         │
 └─────────────────────────────────────────────────────────────┘
      the operator/client: GitHub inbox, or email replies
```

Everything the dispatcher needs that Paperclip holds today — the org chart,
each role's instructions, the skills, the routing table — moves into the repo,
under something like `.my-ai-org/`. That is not a workaround; it is promise 5
("git is the durable memory") taken to its conclusion. A client's org becomes
reviewable, diffable and forkable, and `install.sh` shrinks to: make a box,
clone the repo, seed credentials, start one service.

It also sheds real liabilities. No Paperclip means no dependency on an
experimental SSH driver, and the three upstream rough edges the README
documents — runs that don't stop on cancel, blocked MCP tools, run
directories that never get cleaned up — simply do not exist in this edition.
The `engine: cli` gotcha goes too.

## 6. The gaps, stated honestly

- **No budget ceiling and no kill switch.** This is the one I would not wave
  through. Note though that we are replacing an unenforced ceiling with no
  ceiling: we established that every agent in this company carries
  `budgetMonthlyCents: 0`, none is paused, and `0` enforces nothing. So this
  edition needs a local spend ledger and a `touch STOP`-style kill switch —
  and so does the Paperclip edition. The work is shared, which is an argument
  for doing it once, in the box, rather than in either control plane.
- **No run history anybody can look at.** Paperclip's run log is how we debug
  an agent that went strange. Replacement: logs in the box, and the dispatcher
  posting a one-line run summary to the issue. Thinner.
- **The standing agents lose their home.** Chief of Staff, CTO and DevOps run
  in the Paperclip container today. For a single-project client: the CTO's
  weekly review becomes a timer in the box that posts an issue; DevOps
  collapses into the install script; and the Chief of Staff disappears,
  because with one project the client *is* the Chief of Staff.
- **Multi-project oversight is genuinely gone.** Which leads to §7.

## 7. The segmentation this actually reveals

Paperclip's value is concentrated almost entirely in the right-hand column of
§1, and most of that column's weight is *cross-project*: one board, one place
to see spend, one agent setting priorities across projects. A client who has
"nowhere good to put the Paperclip part" is, nearly always, a client with one
project — and a client with one project was never buying the cross-project
half.

So this is not a degraded edition. It is a different segment:

> **GitHub-native is the single-project edition. Paperclip earns its place at
> project three.**

That framing has a commercial consequence worth naming: it is a land-and-expand
on-ramp. A client starts GitHub-native with a near-zero install (one container,
one service, no control plane to host, no localhost UI to explain, no trust
story to sell) and graduates to Paperclip when they have enough projects to
need a board. If the shared core in §1 stays shared, graduating is a migration
of the queue, not a rebuild.

One boundary check: this does **not** cross the roadmap's "no hosted or
multi-tenant service" line. It still installs on a machine the client
controls. But it does put weight on an open question the roadmap already has —
*audience, and when* — because "clients" is a different answer from "the
operator's own machine", and it pulls M4 (someone else's machine) forward hard.

## 8. Recommendation

**Do not build a second product. Extract the port, then write a second
adapter behind it.**

Concretely, and in this order:

1. **Prove the pipeline once on Paperclip (M1, unchanged).** We have never
   seen the nine handoffs run end to end. Building a second control plane
   under an unproven pipeline would leave us unable to tell which half is
   broken. This is a sequencing argument, not a reason to drop the idea.
2. **Extract the control-plane port.** The seven agent verbs in §1 become one
   thin interface the skills and `templates/` call instead of Paperclip's API
   directly. This is worth doing on its own merits — it is also how we stop
   being exposed to Paperclip's experimental surface.
3. **Spike the dispatcher** (§9) against this repo, GitHub-native, with the
   same agents and skills. Dogfooding applies here too.
4. **Then decide** whether it ships as a second edition, on evidence.

Rough sizing, for ordering not for commitment: the port is the small half; the
dispatcher — event source, claims, run staging, prompt assembly, the
question/answer loop, the ledger and kill switch — is the real work, and it
is the part Paperclip currently gives us for free. That is the honest cost of
this idea, and it recurs every time either control plane changes.

## 9. Spikes that would settle it

Each is small and each can kill or reshape the design:

1. **Delivery-log retention.** How long does GitHub keep
   `/app/hook/deliveries`, and is it paginated far enough to recover from a
   weekend of downtime? Decides §3(c) versus §3(a). *Undocumented; must be
   measured.*
2. **Prompt assembly.** Can a dispatcher-built prompt wake a role as
   effectively as a Paperclip wake payload? Test: hand one role one issue, both
   ways, compare the runs. If this fails, nothing else matters.
3. **The question loop.** Comment + label + reply/reaction, end to end,
   including an operator answering only by email from a phone.
4. **Apple `container` as a box.** Already blocked on hardware for the
   macOS work; this edition makes it load-bearing rather than optional, since
   a Mac-only client has no LXC.

## 10. What I need from the operator — answered 2026-10-04

1. **Audience.** Is "clients" now a real near-term goal, or is this
   contingency planning?
   → **Real and near-term: there is a client in view, plan for it.** So M4
   pulls forward, and the blocked Apple-silicon work (§9.4) becomes
   load-bearing rather than optional.
2. **Sequencing.** Confirm M1 first (§8.1), or say explicitly that this
   outranks it.
   → **Not answered.** §8.1 stands as the default: M1 first. One word reverses
   it, and it is cheapest to say before the port is extracted.
3. **Spike or shelve.** Shall I write up spikes 1–3 as issues now, or hold
   this brief until a client actually needs it?
   → **Neither yet: promote this brief to a decision record and stop.** Done —
   [decisions/0004](../decisions/0004-github-native-is-the-single-project-edition.md).
   Spikes 1–3 are owed and deliberately unfiled.
