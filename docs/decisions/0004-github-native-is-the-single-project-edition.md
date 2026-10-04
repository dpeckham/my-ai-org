# 0004 — GitHub-native is the single-project edition, reached by extracting a port

- **Date:** 2026-10-04
- **Status:** accepted
- **Supersedes nothing. Builds on:** [0001](0001-product-memory-in-docs.md),
  [0002](0002-dogfood-the-pipeline-on-this-repo.md)
- **Research this rests on:** [briefs/github-native-edition.md](../briefs/github-native-edition.md)

## Context

The operator asked whether the product could run with GitHub alone as the
control plane, for clients who have nowhere good to put the Paperclip half,
assuming every client can run one long-running script and one container (LXC,
or Apple's `container` on macOS). The brief answered that question; this record
fixes what we decided as a result, so the next person does not have to re-read
261 lines of research to know what was settled.

Three findings from the brief carry the decision:

1. **Less depends on Paperclip than it looks.** The nine-handoff pipeline, the
   six roles, `templates/`, `skills/`, the bot App and the two GitHub
   identities, and the `docs/` memory are already GitHub-native. Paperclip
   supplies a coordination layer that reduces to **seven agent verbs** — list
   my work, read a thread, comment, set status, reassign, ask the human, create
   a child issue — plus two the dispatcher needs: claim, and stage a workspace.
   Seven of twelve capabilities map straight onto GitHub; two get better; two
   are real gaps.
2. **The elegant event source is the badly-credentialed one.** GitHub's
   notification inbox has genuine acknowledgement semantics
   (`DELETE /notifications/threads/{id}` would let the bridge's seen-state file
   disappear), but the notifications endpoints accept **only a classic personal
   access token** — not fine-grained PATs, not App installation tokens. The
   dispatcher could therefore not be the bot; it would need a broad, long-lived
   credential on an unattended box, which is a step back from the per-repo
   tokens `gh-bot` mints today.
3. **This is a segmentation finding, not a downgrade.** Paperclip's value is
   concentrated in the cross-project half — one board, one view of spend, one
   agent setting priorities across projects. A client with nowhere to host
   Paperclip is nearly always a client with *one* project, who was never buying
   that half.

The operator then answered the brief's first question, which is what makes this
a decision rather than a shelf: **"clients" is a real and near-term goal —
there is a client in view, plan for it.** The brief's second question
(sequencing) was left unanswered; §Decision item 6 records how we proceed in
its absence.

## Options

1. **Shelve the brief until a client actually needs it.** Cheapest today.
   Rejected because the audience answer removed the premise: a client is in
   view, and the roadmap consequences (below) land whether or not we build the
   edition, so leaving them unrecorded is the expensive option.
2. **Build a second edition as its own product.** Fastest route to something a
   client can install, and the one that looks like progress. Rejected: it
   duplicates the control plane permanently, and every change to the pipeline,
   the roles or the skills would then be paid twice for ever. The brief sized
   this honestly — the dispatcher (event source, claims, run staging, prompt
   assembly, the question loop, the ledger) is the real work, and it is exactly
   what Paperclip gives us free today.
3. **Extract the control-plane port, then write a second adapter behind it.**
   The seven verbs become one thin interface that `templates/` and `skills/`
   call instead of Paperclip's API directly; Paperclip and GitHub are two
   adapters behind it.

## Decision

**Option 3.** Specifically:

1. **GitHub-native is the single-project edition of the same product, not a
   fork.** Paperclip earns its place at project three. A client starts
   GitHub-native with a near-zero install — one container, one service, no
   control plane to host, no loopback UI to explain — and graduates to
   Paperclip when they have enough projects to need a board. If the shared core
   stays shared, graduating is a migration of the queue, not a rebuild.
2. **The seven agent verbs become an explicit port.** Skills and templates stop
   calling Paperclip's API directly. This is worth doing on its own merits: it
   is also how we stop being exposed to Paperclip's experimental surface.
3. **The event source is the App's own webhook delivery log**
   (`GET /app/hook/deliveries`, authenticated with a JWT as the App), with
   **per-repo polling — what `scripts/github-bridge.mjs` already does — as the
   fallback**, behind one swappable function. Point the App's webhook at
   something unreachable and read the delivery log: full event stream with
   payloads, no public URL, no inbound network access, and no credential beyond
   the App key the bot already holds. **The notification inbox is rejected** on
   credentials (finding 2), notwithstanding that it is the nicer API.
4. **The human loop is an issue comment plus a `needs:operator` label, with an
   @mention as the signal and `is:unread reason:mention` as the operator's
   filter.** Reply-by-email is treated as a feature of this edition rather than
   a consolation: a client answers their agents from a phone with nothing
   installed, which Paperclip's loopback-only UI cannot do. Approvals get
   cruder — numbered options resolved by a reply or a 👍, with no typed answers,
   no expiry and no wake-only-on-accept — and that is accepted for this edition.
5. **The spend ledger and the kill switch belong in the box, not in either
   control plane.** Both editions need them, the work is the same, so it is
   done once. This is not a gap specific to going Paperclip-less: we
   established that `budgetMonthlyCents: 0` enforces nothing on any agent in
   this company, so today's ceiling is unenforced in either edition.
6. **Sequencing: M1 still comes first.** The brief's recommendation stands
   unchanged in the absence of an answer — building a second control plane
   under a pipeline we have never seen run end to end would leave us unable to
   tell which half is broken when it stalls. This is the one item here the
   operator has not confirmed, and the one word that would reverse it is
   cheapest to say now, before the port is extracted.

## Consequences

- **The roadmap's audience question is closed.** "Audience, and when" was open
  in `STATE.md`; the answer is clients, near-term. M4 (someone else's machine)
  pulls forward hard, and the first-run experience stops being a nicety.
- **macOS support ([#3](https://github.com/dpeckham/my-ai-org/issues/3))
  becomes load-bearing rather than optional.** A Mac-only client has no LXC, so
  Apple's `container` is the only box backend for them. It is currently blocked
  on access to a Mac with macOS 26 on Apple silicon — which makes that hardware
  an escalation for the operator, not a background wish. Step 1 (the backend
  verb layer) is a Linux-only refactor and can start regardless.
- **The org chart moves into the repo.** Each role's instructions, the skills
  and the routing table have to live under something like `.my-ai-org/` in the
  client's repo for a dispatcher to read them. That is promise 5 ("git is the
  durable memory") taken to its conclusion, and it makes a client's org
  reviewable, diffable and forkable — but it reshapes `templates/` and
  `skills/` from Paperclip-shaped inputs into repo-committed configuration.
- **We take on a recurring bill.** Two adapters means every control-plane
  change is considered twice. The port staying thin is the only thing that
  keeps that bill small, so "does this belong behind the port?" becomes a
  standing question on control-plane work.
- **This edition sheds real liabilities.** No Paperclip means no dependency on
  an experimental SSH driver, and the three upstream rough edges the README
  documents — runs that ignore cancel, blocked MCP tools, run directories that
  are never cleaned up — do not exist in it. The `engine: cli` gotcha goes too.
- **Run history gets thinner.** Paperclip's run log is how we debug an agent
  that went strange; the replacement is logs in the box plus a one-line run
  summary posted to the issue. Accepted, with the summary treated as required
  rather than nice to have.
- **It does not cross the "no hosted or multi-tenant service" line.** This
  still installs on a machine the client controls. Nothing here is designed for
  untrusted tenants, and the out-of-scope entry stands.
- **Three spikes are owed before any of this is load-bearing**, and are
  deliberately not filed yet (the operator asked for this record and a stop):
  delivery-log retention, prompt assembly versus a Paperclip wake payload, and
  the question loop end to end including an email-only answer. The first can
  kill §Decision item 3; the second can kill the whole edition.
- **Reversibility.** Cheap now and for as long as this is three documents.
  Once the port lands and skills call it instead of Paperclip, reversing means
  unpicking the interface from every skill — so the decision to extract is the
  commitment point, not this record.
