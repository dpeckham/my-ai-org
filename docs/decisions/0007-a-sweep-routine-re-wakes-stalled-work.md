# 0007 — A sweep routine re-wakes stalled work, not a per-agent heartbeat

- **Date:** 2026-10-05
- **Status:** accepted
- **Keeps:** promise 1 and promise 2 in [ROADMAP.md](../ROADMAP.md)
- **Filed as:** https://github.com/dpeckham/my-ai-org/issues/18

## Context

The pipeline moves on wake events. A role finishes its step, reassigns the
Paperclip issue, and that assignment wakes the next role. Nothing re-checks an
agent's queue on a schedule, so a wake that does not arrive is not retried: the
work stops, permanently, and the only thing that moves it again is a human
noticing.

That is not hypothetical. On the day this was written, 19 of the 25 open issues
in the company had not been touched for 22 hours or more, nine of them sitting
in `todo` with an agent assignee that then never ran. Two features parked
mid-handoff were the two highest-leverage items from the previous engineering
review, and the visible consequence was that neither repo had a CI workflow on
any branch.

The nearest thing to a recovery path we had was a Product Manager briefing
routine, which did report the stall, correctly, and the stall continued.
Observing a stall is not clearing it.

Two mechanisms were on the table: a heartbeat per agent, set by `ensure_agent`
so every install reconciles it; or one scheduled routine that sweeps for work
that has not moved. The engineering review's default was the heartbeat, on the
grounds that agents are already written for it — their instructions already
describe the heartbeat procedure, so there would be nothing new to write on the
agent side.

## Decision

**One sweep routine, created by `scripts/paperclip-org.sh` and owned by the
DevOps agent.** It lists company issues in `todo`, `in_progress` and `in_review`
that have an agent assignee and no user assignee, keeps the ones older than a
stall threshold, nudges each assignee, and after a few fruitless nudges on the
same issue raises it to the Chief of Staff instead of nudging again.

Defaults: hourly, a four-hour stall threshold, at most ten nudges per sweep,
escalation after three. All overridable by environment variable in the style of
`REVIEW_CRON`.

**The per-agent heartbeat is rejected, on the API surface.** The control plane's
own OpenAPI document gives `runtimeConfig` exactly two properties on both the
agent create and patch bodies: `aiConnection` and `debug`. There is no
`heartbeat` property, and no cadence field anywhere in the spec. Agents in the
company do carry a stored `runtimeConfig.heartbeat` object, so the field is real
somewhere — but nothing documented writes it, and nothing documents what
interval `enabled: true` would use. Reconciling an undocumented field on every
install is exactly the exposure to the control plane's experimental surface that
[0004](0004-github-native-is-the-single-project-edition.md) exists to reduce.

**A heartbeat would also have been aimed at the wrong thing.** Several agents
had never executed a run, which looked like the same defect; three of them had
never had a single issue assigned. An agent with an empty inbox exits
immediately by design, so waking it on a timer buys nothing. The defect is
stalled *work*, not idle agents, so the sweep is attached to issues.

**This is sequenced ahead of the two defects M1 was going to carry.** M1's bar
is that the operator did not have to intervene to move a feature between roles.
While a missed wake is unrecoverable, no feature can meet that bar, so the
recovery path goes through the pipeline first. It does not displace
[0002](0002-dogfood-the-pipeline-on-this-repo.md): the first run is still
dogfooded on this repo, and M1 still comes before M2. Only the order inside M1
changes.

## Consequences

- **The pipeline becomes self-healing at the granularity of an hour**, which is
  what makes promise 1 ("work happens while the operator is elsewhere") true
  rather than aspirational. Every other fix in the queue stops being subject to
  the same stalling.
- **Nudging is mechanical; judgement is escalated.** The sweep never decides
  what a stall means. It counts hours, nudges, and after the third nudge hands
  the issue to a role whose job is coordination. That boundary is what keeps a
  recovery mechanism from becoming a second scheduler with opinions.
- **A scheduled routine is a standing cost.** Hourly is 24 runs a day for one
  agent, most of them ending immediately with nothing stale, and
  `budgetMonthlyCents: 0` enforces no ceiling today. The cadence is the cheapest
  thing to lower if that is the wrong trade, and the spend ledger M6 already
  owes is what makes the cost visible either way.
- **The activity gate is a trap worth writing down.** A routine can be gated on
  external activity having happened since its last run. A stalled org is a quiet
  org, so that gate suppresses the sweep exactly when it is needed. The sweep
  fires unconditionally.
- **This is a recovery path, not a fix for the holes themselves.** Individual
  missed wakes in the bridge are separate issues and still worth closing; the
  sweep only means that missing one costs an hour instead of a day.
- **Per-issue monitors stay available and unused for now.** The control plane
  can re-wake the assignee of one issue on a schedule, set by the agent holding
  it. That is a change to agent practice in `templates/` rather than to the
  installer, and the sweep covers the same statuses from one place; it is the
  fallback if an hourly sweep proves too coarse.
