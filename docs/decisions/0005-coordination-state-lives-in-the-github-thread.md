# 0005 — Coordination state lives in the GitHub thread, not in the box

- **Date:** 2026-10-04
- **Status:** accepted
- **Builds on:** [0004](0004-github-native-is-the-single-project-edition.md)
- **Research this rests on:** [briefs/agent-runtime.md](../briefs/agent-runtime.md) §3, §10–§13

## Context

[0004](0004-github-native-is-the-single-project-edition.md) settled *that* the
GitHub-native edition is a second adapter behind one port. It did not settle
where that adapter keeps its state: which comment each agent has read, which
role currently holds a feature, what the dispatcher has already acted on, what
question is outstanding. The first brief assumed a seen-state file in the box,
because that is what `scripts/github-bridge.mjs` keeps today and it works.

The second brief proposed the alternative: **one comment per issue, posted by
the bot and edited in place**, carrying that state in a machine-readable HTML
comment. The repo already uses the trick in miniature — liaison projects mark
authorship with `<!-- agent: Coder -->`, which GitHub does not render and the
bridge reads.

The operator chose the thread, in their words, "take the portability".

## Decision

**All durable coordination state for the GitHub-native edition lives in the
GitHub thread.** The box holds nothing that cannot be rebuilt from the repo and
the thread.

1. **One state comment per issue**, authored by the bot, edited in place, never
   reposted. It carries a rendered summary a human can read and a
   `<!-- my-ai-org: {…} -->` block a machine can parse. Schema and field
   ownership are specified in [briefs/agent-runtime.md](../briefs/agent-runtime.md) §11.
2. **Quiet and loud become different mechanisms, by construction.** Editing a
   comment notifies nobody, so role-to-role handoffs are silent; a question for
   the human is a *new* comment with an `@mention`, which notifies and is
   repliable by email. The first brief treated agent chatter burying the
   operator as a filter-configuration problem for the client to solve. It is
   now an architectural property we ship.
3. **The box is disposable and a run is resumable on any machine.** Destroying
   a box loses a workspace and a log, never a position in the pipeline. This is
   a property the Paperclip edition does not have, where the queue is in
   Paperclip's Postgres and a box is an execution site.
4. **The state comment is the audit trail.** The pipeline's position is legible
   in the thread, in order, to a human with no tools, on a phone.
5. **Recovery is re-derivation, not backup.** If the state comment is deleted
   or corrupted, the dispatcher re-derives: comment ids are monotonic, so the
   cursor is recoverable by re-reading the thread, and the holder is recoverable
   from the GitHub assignee. The cost of a lost comment is at worst one repeated
   handoff, not a lost feature. No separate backup is built.
6. **Single-writer, enforced by the dispatcher.** One dispatcher per repo holds
   a per-issue lock while it reads-modifies-writes the state comment. Agents
   never write the block themselves; they emit their handoff as a normal
   comment and the dispatcher folds it in. This keeps the race surface at one
   process and keeps the agent prompt free of state-management instructions.

## Options considered

- **A seen-state file in the box** (what the bridge does today). Simplest, no
  new failure mode, no bot comment living in a client's repo for ever. Rejected
  because it pins a feature to a machine: rebuild the box and the pipeline
  forgets where it was, which is precisely the fragility a single-project client
  on one unattended machine is most exposed to.
- **A state branch or a committed file in the repo.** Durable and diffable, but
  it puts pipeline bookkeeping into the client's git history, conflicts with
  the work the agents are doing in the same repo, and is invisible in the thread
  where the human is already reading.
- **GitHub's own primitives alone** (assignee, labels, projects). Used where
  they fit — the assignee *is* the holder, and `needs:operator` *is* the
  question flag — but they cannot carry a cursor or a handoff log, so they are a
  complement, not a substitute.

## Consequences

- **The macOS backend question demotes from a product decision to an install
  choice.** If no durable state lives in the box, nothing about the pipeline
  depends on which box technology a given machine uses; the backend becomes a
  per-install configuration behind the verb layer. See
  [briefs/agent-runtime.md](../briefs/agent-runtime.md) §10 — this is the main
  thing the answer bought beyond portability itself, and it is why the tier 1 /
  tier 2 question does not have to be answered before building.
- **The backend verb layer ([#3](https://github.com/dpeckham/my-ai-org/issues/3)
  step 1) becomes the load-bearing refactor** for M4 and M6 alike, because it is
  the seam that choice sits behind.
- **The bot now writes to a client's repo on an ongoing basis**, not just when
  it reviews. That is a visible, permanent artifact in someone else's issue
  tracker and belongs in whatever we tell a client the bot does.
- **An extra API write per handoff**, and one more thing that can fail
  mid-sequence. Mitigated by making the state comment advisory rather than
  authoritative: it is a cache of things re-derivable from the thread (5).
- **It constrains the Paperclip edition not at all**, which keeps the port
  honest: Paperclip's adapter continues to keep state in Paperclip, and the
  interface is where the two meet.
- **"Two installs sharing one repo" stays out of scope for a structural reason
  now**, not a Paperclip-specific one: two dispatchers would read the same
  holder field and both act.
- **Reversibility.** Cheap. The state block is additive to a comment; falling
  back to a file in the box means ignoring it. The commitment point is when
  skills start reading the block, not now.
