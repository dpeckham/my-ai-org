# Brief: the agent runtime decomposed, on macOS and on Linux

**Status:** partly answered, 2026-10-04. §3 — coordination state in the GitHub
thread — was put to the operator and accepted ("take the portability"), and is
now [decisions/0005](../decisions/0005-coordination-state-lives-in-the-github-thread.md).
§10–§13 were written after that answer and are the consequences of it: what it
settles, what it dissolves, and what the thing actually looks like built. The
two macOS questions were left unanswered and §14 records the standing defaults
they fall back to. It extends
[briefs/github-native-edition.md](github-native-edition.md) and
[decisions/0004](../decisions/0004-github-native-is-the-single-project-edition.md);
where it disagrees with 0004, §8 says so and 0004 still stands until the
operator moves it.

**The operator's framing, which this brief takes as its starting point:**

> Paperclip is really a combination of some event system/triggers/routines to
> initiate action, plus some agents that perform actions and communicate with
> each other and the operator. Each agent is a portable Claude/Codex
> invocation with a pointer to some context.

That is right, and it is more useful than the capability table in the earlier
brief, because it splits the problem along the line where the platforms differ.
This brief makes it exact, then builds the two platform pictures from it.

**The short version.** The decomposition holds, with one correction: an agent
is a portable invocation with a pointer to *four* kinds of context, which have
four different lifetimes and four different owners. Get those four right and
the invocation really is portable — same bash on both platforms, with one
sandbox wrapper swapped underneath. Two findings matter more than the rest.
First, 0004's "port" has two halves and only named one: the seven outbound
verbs, yes, but also one inbound artifact — the wake — which is the part
Paperclip actually earns its keep on. Second, if the control plane's state
lives **in the GitHub thread** rather than in the box, the box becomes
disposable and a run can resume on any machine; that is a stronger property
than we have today.

## 1. The four kinds of context

"A pointer to some context" bundles four things that want to be separate:

| Layer | What it is | Where it belongs | Lifetime |
|---|---|---|---|
| **Role** | the instructions, skills, engine and model that make this agent a Lead Engineer rather than a Coder | the repo, on the default branch | changes by pull request |
| **Work** | the issue, its thread, the answers the human has given, how far the agent has read | GitHub | the life of the feature |
| **Workspace** | a checkout at a commit, on a branch | a `git worktree` | one run |
| **Machine** | box, toolchain, credentials, PATH | the box | the life of the install |

The design rule that falls out: **an agent invocation should be a pure function
of (role ref, work ref, workspace ref), run on any machine that can resolve
those three.** Everything the invocation needs is then addressable, and nothing
is implicit in the machine it ran on. That is what "portable" has to mean to be
worth anything — it is not that the binary runs on two operating systems, it is
that *the same run* could have happened on either.

Today it is not pure, and the impurity is worth naming precisely, because it is
the whole cost of this idea.

## 2. What a wake actually contains

The wake payload Paperclip hands an agent — this very run received one — is not
a pointer. It is an assembled document: the trigger and its reason; the
objective; the full comment thread in order; the human's verified answers to
earlier structured questions, each scoped to the question it answers; a
coverage cursor saying which comment the history is complete through, and a
flag for whether the agent needs to fetch more; the issue's status, mode and
priority; a continuation summary of what previous runs did; and an execution
contract about how the run must end.

That document is the real port surface. 0004 described the port as seven
outbound verbs — list my work, read a thread, comment, set status, reassign,
ask the human, create a child issue — and that half is right, but the inbound
half is bigger and it is what we would be rebuilding. So state the port as one
artifact plus those verbs, and let each control plane produce the artifact its
own way:

```json
{
  "trigger":   { "reason": "handoff", "sourceEventId": "…", "originCommentIds": ["…"] },
  "role":      { "name": "lead-engineer", "instructions": ".my-ai-org/roles/lead-engineer.md",
                 "skills": ["team-workflow", "spec-review"], "engine": "claude",
                 "orgRef": "<default-branch sha the org config was read at>" },
  "work":      { "url": "https://github.com/org/repo/issues/41", "status": "in_progress",
                 "thread": [ … ], "cursor": { "throughCommentId": 123 },
                 "answers": [ … ], "handoffNote": "what the previous role did" },
  "workspace": { "path": "/w/runs/<id>", "branch": "feat/…", "baseSha": "…" },
  "contract":  { "mustEndWith": ["comment", "reassign"], "stopFile": "/w/STOP",
                 "spendRemainingCents": 1234 }
}
```

Every field maps onto something GitHub already has, with two exceptions:

- **The objective.** Paperclip synthesises one; GitHub's equivalent is the
  issue body, which is better, because `issue-writing` already requires that
  body to be resolvable cold.
- **The continuation summary.** Paperclip generates this from its run history.
  GitHub has no run history — but the pipeline already requires every role to
  end its step with a handoff comment written for someone arriving cold. **The
  handoff comment is the continuation summary**, produced by the agent that
  did the work rather than inferred afterwards. That is a better artifact from
  a worse mechanism, and it is the strongest evidence I have that spike 2
  (prompt assembly) will come out fine.

## 3. Put the control plane's state in the thread

The brief assumed a seen-state file in the box, as the bridge keeps today.
There is a better option, and it is the hinge of this whole design.

Every piece of durable coordination state — the cursor, the claim, the run
ledger, which role holds the work, what the current question is waiting on —
fits in **one comment per issue, posted by the bot and edited in place**, with
a machine-readable block in it:

```markdown
**Pipeline** — Lead Engineer, spec review · [run log](…)
<!-- my-ai-org: {"holder":"lead-engineer","cursor":123,"runs":[…],"claim":"…"} -->
<details><summary>Handoffs</summary>… the log, newest first …</details>
```

The repo already uses exactly this trick: liaison projects mark authorship with
`<!-- agent: Coder -->` because GitHub does not render it and the bridge can
read it. Extending it to the pipeline's own state buys four things:

1. **The box holds no durable state.** Rebuild it, move it to another machine,
   or run the dispatcher from a laptop for an afternoon — the pipeline is
   wherever the repo is. This is the property Paperclip does not have: today
   the queue is in Paperclip's Postgres and a box is an execution site.
2. **Handoffs stop being noise.** Editing a comment does not notify anyone, so
   role-to-role chatter is silent, while a question for the human is a *new*
   comment with an `@mention`. The earlier brief worried that agent chatter
   would bury the operator and called it a filter-configuration problem; this
   makes it an architectural one. Loud and quiet become different mechanisms.
3. **It is auditable by a human with no tools.** The state of the pipeline is
   legible in the thread, in order, on a phone.
4. **It keeps the "two installs sharing one repo" line honest.** Two
   dispatchers would both read the same holder field and both act. The
   roadmap already rules that out; now it is ruled out for a structural
   reason rather than a Paperclip-specific one.

The cost: an edit race if ever two things write at once (one dispatcher, so
no), and a lost comment loses the cursor (recoverable — comment ids are
ordered, so the fallback is "re-read the thread and re-derive").

## 4. The dispatcher, and where it runs

Five things start a run, and that list is the same on both platforms:

| Trigger | Linux today | GitHub-native |
|---|---|---|
| External event (issue, comment, PR, CI, Dependabot) | the bridge polls, creates Paperclip work | the dispatcher reads the App's own delivery log |
| Handoff from another role | reassign in Paperclip | reassign on GitHub, holder field updated |
| Schedule / routine (the CTO's weekly review) | a Paperclip routine | an OS timer |
| The human answering | a typed interaction in the UI | a comment, an email reply, or a 👍 |
| Continuation of unfinished work | Paperclip re-wakes the agent | the dispatcher re-enqueues on a non-final exit |

Where the dispatcher process sits is the one decision that changes the
credential story, so it is worth separating from the box question:

- **In the project box** (the earlier brief's drawing). Simplest to install.
  But the App private key — which can mint tokens for every repo the App is
  installed on — then sits inside the blast radius of the code the agents are
  building and of any dependency they install.
- **On the host, next to the boxes** (my preference). The dispatcher holds the
  App key, mints a **one-hour installation token per run**, and passes only
  that into the box. The box's GitHub credential now expires; today boxes hold
  a long-lived `gh` token seeded by `seed-agent-auth.sh`. That is a security
  improvement over the current edition, not a concession, and it mirrors
  today's split — supervisor outside, execution inside — without needing
  Paperclip to be the supervisor.

What the host side actually does per run: resolve the role from the org config
**at the default branch** (never at the branch under review — see §7), create a
worktree, assemble the wake JSON of §2, exec the agent inside the box, stream
output to a log, and interpret the exit. One worker at a time for a
single-project client, with a per-issue lock so parallelism is a config change
rather than a rewrite.

The invocation itself is the least interesting part, which is the point: `cwd`
is the worktree, the credential is an env var or a file, the prompt is the wake
document on stdin, and both `claude` and `codex` already run headless that way.
One script, both engines, both platforms. Only the wrapper differs:
`incus exec` / `ssh` on Linux, `container exec` on a Mac, nothing at all in the
degenerate case.

## 5. Linux

Nothing here is new work beyond the dispatcher, which is the honest summary of
the Linux story:

- **Supervisor:** a systemd **user** service for the dispatcher plus a timer
  for its poll, which is what `github-bridge.mjs` already is. `loginctl
  enable-linger` is what makes a user service survive logout, and the install
  already depends on that for Paperclip.
- **Box:** unchanged — an Incus system container cloned from `base:ready` in
  about a second, with pixels' nftables egress allowlist and a TLS client
  certificate restricted to the `agents` project.
- **Isolation:** shared kernel, per-project filesystem, process and credential
  separation, plus a real network allowlist. This is the stronger of the two
  platforms on network containment and the weaker on kernel containment.
- **Routines:** systemd timers. One timer that posts the CTO's review issue is
  the whole of the CTO's scheduling.

## 6. macOS

Issue [#3](https://github.com/dpeckham/my-ai-org/issues/3) already did the
research against `apple/container` 1.5.0, so this section only adds what the
GitHub-native shape changes. Two of those changes are large.

**The broker becomes unnecessary.** #3 needs a host broker (step 3) for one
reason: Apple's runtime has no remote API — the CLI talks over local XPC to a
per-user launch agent — so the Paperclip container cannot create or drive
boxes, and the DevOps agent's provisioning power has to be brokered in. In the
GitHub-native edition there is no Paperclip container, and the only process
that needs that power is the dispatcher, which is already on the host as a
launchd agent. The broker's whole purpose disappears. #3 step 3 becomes
optional, and the Mac install gets materially smaller.

**Logout is the platform's real problem, and it has a Linux twin.** Apple's
runtime runs only while the user is logged in, and launchd makes this worse
than it sounds: a LaunchDaemon starts at boot but has no access to the user's
XPC session, so it cannot drive `container`; the dispatcher must be a
LaunchAgent, which means a logged-in session, which means auto-login on a
machine holding the client's subscription credentials. The honest framing is
that this is the same requirement as `loginctl enable-linger` on Linux, one
notch worse: Linux lets a user service outlive the login, macOS does not.
Mitigation is a dedicated always-logged-in user with FileVault unlocked at
boot, and that is a client-facing install instruction, not a script.

**Three tiers, because `container` needs macOS 26 on Apple silicon** and
clients will arrive with Intel Macs and older macOS:

| Tier | Shape | Isolation | Honest verdict |
|---|---|---|---|
| **0** | no container: worktrees in a directory, launchd agent, nothing else | none — the agent has the user's `$HOME`, keychain and SSH agent | the one most likely to actually get installed, and the one whose blast radius we would have to state plainly in the README. Offer it only with that warning. |
| **1** | `apple/container`: one lightweight VM per project, `.test` DNS, vmnet | **better than Linux on kernel isolation**; no egress allowlist and no fleet cap, so worse on network | the intended shape, blocked on #3's six unknowns and on hardware |
| **2** | a Linux VM (Lima-class) with the existing Incus install inside | identical to Linux, because it *is* Linux | one backend instead of two, works on Intel and older macOS, costs a VM and a second layer to explain |

Tier 2 deserves more weight than #3 gives it. It is the only option that keeps
one code path, and it turns "macOS support" from a backend port into an install
instruction. The reason not to prefer it outright is that it fails the thing a
client actually judges — a Mac user who is told to install a Linux VM to run a
Mac product has learned something about the product — and that it doubles
resident memory. Worth a decision rather than an assumption; it is question 2
below.

What is unchanged on both platforms, and nice to be able to say: credentials
are plain files (`claude setup-token`'s long-lived token, `~/.codex/auth.json`),
so `seed-agent-auth.sh` ports with no macOS-specific keychain work. On a
client's machine those are the *client's* subscriptions, which is cleaner than
anything we run today.

## 7. The one new risk this shape creates

If the dispatcher reads its org config, role instructions and skills from the
repo, then **a pull request can rewrite the agents that review it.** An outside
contributor's PR touching `.my-ai-org/` is a privilege-escalation attempt
against a runner that holds credentials, and the pipeline's own rule — treat an
outside PR as untrusted code and read it before running it — is advice to an
agent whose instructions the PR may have just edited.

The rule has to be structural: **role context resolves at the default branch
only**, pinned to a commit the operator merged, never at the ref under review.
Worth recording now, because it is cheap at design time and would be expensive
to retrofit — and it applies to the Paperclip edition too, as soon as M5 starts
syncing skills from the repo.

## 8. What this would change, if the operator agrees

Changes to 0004 — all additive, none reversing it:

1. The port is **one inbound artifact plus seven outbound verbs**, not seven
   verbs (§2).
2. Coordination state lives **in the GitHub thread**, not in the box (§3);
   handoffs are quiet edits and human questions are loud comments.
3. The dispatcher sits **on the host**, not in the box, minting a one-hour
   token per run (§4).
4. Role context resolves **at the default branch only** (§7).

Changes to the roadmap:

5. **#3 step 1 — the backend verb layer — is on M6's critical path**, not just
   M4's. It is the seam the dispatcher needs on either platform, it is a
   Linux-only refactor, and it needs no Mac. It is the single most useful thing
   anyone can do on either milestone today.
6. **#3 step 3 (the broker) drops out of the GitHub-native edition** (§6).
7. A **tier-0 and tier-2 macOS story** belongs in M4 whether or not tier 1
   lands, because clients with Intel Macs exist and the answer "wait for
   hardware" is not one.

And one spike reshaped: spike 2 (prompt assembly) should test the §2 wake
document against a real Paperclip wake on the same issue, with the handoff
comment standing in for the continuation summary. That is now a concrete,
cheap experiment rather than a vague comparison.

## 9. What I needed from the operator — and what came back

1. **ANSWERED: yes, state in the thread** — "take the portability". Recorded as
   [0005](../decisions/0005-coordination-state-lives-in-the-github-thread.md);
   §10–§13 below are what follows from it.
2. **Unanswered: macOS tier 1 or tier 2.** §10 argues the answer no longer
   gates anything, and §14 gives the standing default.
3. **Unanswered: ship a no-container tier 0.** §14 gives the standing default.

The questions as originally put:

1. **Does the state-in-the-thread model appeal, or does it feel too clever?**
   It is the load-bearing idea here: it is what makes a box disposable and a
   run resumable anywhere, and it is also a bot editing a comment in a client's
   repo forever. If that reads as fragile to you, the alternative is a
   seen-state file in the box and a less portable run, which is what the
   bridge does today and it works.
2. **macOS tier 1 or tier 2?** Apple's runtime (two backends, one blocked on
   hardware, better kernel isolation, a Mac-native install) or a Linux VM (one
   backend, available today on any Mac, a worse first impression).
3. **Is tier 0 — no container at all — something we are willing to ship with a
   warning?** It is what a client with an Intel Mac and no patience will do
   anyway. Documenting it is harm reduction; shipping it is an endorsement.

---

*Everything below was written after the operator accepted §3.*

## 10. What the answer settles — and the one question it dissolves

Putting the state in the thread was argued for on portability. It buys that,
and it buys one more thing that is worth more:

**If nothing durable lives in the box, nothing about the pipeline depends on
what the box *is*.** The box stops being part of the architecture and becomes a
sandbox with a toolchain — a place to run a command with a filesystem and a
network. Everything that distinguishes Incus from Apple's `container` from a
Lima VM from no container at all is then confined to one file of shell behind
the verb layer.

That dissolves question 2. "macOS tier 1 or tier 2" was framed as a product
decision — which backend *is* the Mac product — and it is not one. It is a
per-install configuration, chosen by the installer from what the machine can
actually do:

| The client's machine | Backend it gets | Chosen by |
|---|---|---|
| Linux | Incus, as today | `uname` |
| Mac, macOS 26, Apple silicon | `apple/container` (tier 1) | `uname` + version + arch |
| Intel Mac, or older macOS | Lima VM running the Incus install (tier 2) | the same check failing |
| Client refuses a VM | no container (tier 0) | explicit opt-in only — see §14 |

Both macOS tiers get built eventually because both have clients. The real
question was never *which*, it was **which one we write first**, and that is a
scheduling question with an obvious answer: tier 2 needs no Apple silicon and
no macOS 26, so it is the one that can be written and tested this month, and it
makes the Mac story "it works today" instead of "it works when hardware
arrives". Tier 1 is the better destination and stays the intended shape.

This is the reason the brief now says the thread answer was the load-bearing
one: it converted the platform question from a fork in the road into an
ordering.

## 11. The state comment, specified

One comment per issue, posted by the bot the first time the dispatcher touches
the issue, edited in place for ever after.

```markdown
**Pipeline** · Lead Engineer · spec review · updated 2026-10-04 18:42 UTC

<details><summary>Handoffs (3)</summary>

- 18:42 — Product Manager → Lead Engineer · spec written · [log](…)
- 18:05 — dispatcher → Product Manager · woken by issue opened
- 18:05 — opened by @someone

</details>

<!-- my-ai-org:v1 {"holder":"lead-engineer","phase":"spec-review",
"cursor":{"issue":2211,"pr":null},"question":null,
"runs":[{"id":"r-41","role":"product-manager","exit":"handoff","cents":37}],
"orgRef":"a1b2c3d","updated":"2026-10-04T18:42:11Z"} -->
```

| Field | Means | Written by | Re-derivable from |
|---|---|---|---|
| `holder` | the role that owns the work now | dispatcher, on handoff | the GitHub assignee |
| `phase` | where in the nine-handoff pipeline | dispatcher | the holder plus the PR's state |
| `cursor` | highest comment id already folded into a wake | dispatcher, after assembling a wake | re-read the thread; worst case one repeated wake |
| `question` | the comment id of an outstanding human question | dispatcher, when an agent asks | the `needs:operator` label |
| `runs` | id, role, exit reason, cost per run | dispatcher, on exit | nothing — this is the only copy, and it is the thin run history 0004 accepted |
| `orgRef` | default-branch sha the role config was read at | dispatcher, per run | the default branch's current head |

Everything except `runs` is a cache of something GitHub already knows, which is
what makes recovery boring: delete the comment and the dispatcher rebuilds it
from the assignee, the labels and the thread, losing only cost history.

**Who writes it.** Only the dispatcher. Agents emit a normal handoff comment
and exit; the dispatcher folds that into the log and updates the block. Two
reasons: it keeps the race surface at one process holding one per-issue lock,
and it keeps "maintain this JSON correctly" out of the agent's prompt, where it
would be both unreliable and a waste of the context window.

**Resuming on another machine, concretely.** The client's Mac dies on Tuesday.
On Wednesday the dispatcher is installed on a different machine, pointed at the
same repo with the same App. It reads the thread, finds `holder:
"lead-engineer"` and `cursor: 2211`, sees comment 2213 is newer, creates a
worktree at the PR's head, assembles a wake, and the Lead Engineer carries on
from where it was. Nothing was restored, because nothing was backed up. The
Paperclip edition cannot do this; its queue is in Postgres on the dead machine.

## 12. The dispatcher loop

The whole control plane, on either platform. Only step 6 differs between them,
and only in which backend file it calls.

```
every N seconds:
  1. events   ← App delivery log since cursor   (fallback: poll each repo)
  2. for each affected issue, enqueue once (coalesce: ten comments, one run)

  for each queued issue, holding a per-issue lock:
  3. state    ← read the state comment          (§11; rebuild if absent)
  4. decide   ← is a run owed? (new comments past cursor, a handoff, a human
                answer, a timer, a non-final exit to continue). If not, drop.
  5. role     ← read .my-ai-org/roles/<holder>.md AT THE DEFAULT BRANCH (§7)
                → record the sha as orgRef
  6. box      ← box_create if absent; token ← mint 1-hour installation token
                workspace ← git worktree inside the box at the base sha
  7. wake     ← assemble the §2 document from the thread, the answers, the
                cursor and the previous handoff comment
  8. run      ← box_exec <engine> --headless, wake on stdin, log to a file
  9. exit     ← final (handed off, asked the human, finished) → advance holder
                non-final (crashed, out of budget, hit the stop file) → mark,
                retry with backoff, escalate to the operator on the third
 10. write    ← comment as the agent if it produced one; update the state
                comment; release the lock
```

Three details that are not obvious until you write it out:

- **Step 6 cannot mount a host directory into an Incus box.** pixels' `agents`
  project deliberately refuses host-path disks — that is one of the trust
  boundary's load-bearing restrictions, verified in the install. So the
  dispatcher cannot stage a worktree on the host and mount it in, the way
  Paperclip stages a per-run directory today. The worktree is created *inside*
  the box instead: each box keeps a bare mirror of the repo and `git worktree
  add`s from it per run. The mirror is a cache — rebuildable, not state — which
  keeps it consistent with [0005](../decisions/0005-coordination-state-lives-in-the-github-thread.md).
- **The dispatcher needs no verb beyond [#3](https://github.com/dpeckham/my-ai-org/issues/3)'s
  seven**, provided `box_exec` carries stdin in and streams stdout out. The
  wake goes in on stdin; the log comes out on stdout. That is worth stating as
  a requirement on the verb layer before it is written, because it is cheap to
  design in and awkward to retrofit.
- **Coalescing at step 2 is what makes polling affordable.** Ten comments in a
  minute is one run, not ten — the same property Paperclip's wake payload
  already demonstrates, which is why this very run received one comment id and
  a full thread rather than ten wakes.

## 13. What the operator actually installs

**On Linux**, the whole GitHub-native install is:

- `apt`/`pacman`/`dnf` for Incus and mise; `install.sh` phases 0–3 unchanged.
- One systemd **user** service for the dispatcher and one timer, with
  `loginctl enable-linger` so it survives logout — the same mechanism the
  bridge already uses.
- The App's private key in a file readable only by that user, on the host.
- Per-project boxes cloned from `base:ready`, with the nftables egress
  allowlist.
- No Paperclip, no Postgres, no web UI, no SSH driver.

That is strictly *less* than today's install. It is the one genuinely
encouraging thing about this edition's Linux story: the work is all dispatcher,
and the install gets smaller.

**On a Mac**, the same list with four substitutions and one new instruction:

- Homebrew and mise instead of the distro package manager.
- A launchd **LaunchAgent** instead of a systemd user service — and here is the
  new instruction: a LaunchDaemon starts at boot but has no access to the
  user's XPC session, so it cannot drive `container`. The Mac therefore needs
  **auto-login on a dedicated user with FileVault unlocked at boot**, where
  Linux needs only lingering. This is the one thing in the Mac install a client
  has to be told rather than scripted, and it should be in the README's
  first screen, not its gotchas.
- `backends/apple.sh` or `backends/lima.sh` instead of `backends/incus.sh`,
  per §10.
- The `.test` DNS domain instead of `.incus` — invisible above the verb layer,
  which only ever returns a hostname.
- **No broker.** [#3](https://github.com/dpeckham/my-ai-org/issues/3) step 3
  exists only because Apple has no remote API and the Paperclip *container*
  therefore cannot drive boxes. With no Paperclip container, the only process
  that needs that power is the dispatcher, which is already a host process.
  Step 3 is Paperclip-edition-only.

## 14. Standing defaults for the two unanswered questions

Neither gates the work, so both get a default that holds until the operator
moves them. Reversing either is cheap for as long as the verb layer is the only
thing written.

**macOS backend (question 2) — default: build tier 2 first, tier 1 as the
destination.** §10 is the argument: the answer is a per-install config, not a
product fork, so the only real content of the question is ordering, and tier 2
is the only one that can be written without hardware we do not have. This also
removes the uncomfortable position where a Mac client is blocked on the
operator finding a Mac.

**Tier 0, no container (question 3) — default: document the risk, do not ship
the backend.** Worth knowing before deciding: tier 0 is the *null*
implementation of the verb layer — `box_create` is `mkdir`, `box_exec` is a
subshell, `capacity` is free disk — perhaps thirty lines. So the decision is
not "is it worth the engineering", it is purely "do we endorse it", and the
engineering cost cannot be used to dodge the question. The default is the
cautious half: the README states plainly what an agent with no sandbox can
reach (the user's whole `$HOME`, their keychain, their forwarded SSH agent, and
every credential any of it holds), and we do not ship a backend that makes it
one flag away. A client who does it anyway has been told; a client who is
handed it by our installer has been encouraged. Shipping it later is one file.
