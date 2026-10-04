#!/usr/bin/env node
// GitHub -> Paperclip bridge: turns GitHub activity on each project's repos
// into Paperclip work, so agents react within minutes without anyone watching.
//
// Runs in the Paperclip container every minute from a systemd user timer
// (paperclip-up.sh installs it); each project is polled at its own interval.
// Polling only: nothing is exposed to the internet, and no AI runs unless an
// event becomes a Paperclip issue or comment, which is what wakes an agent.
//
//   GitHub event                                  Paperclip effect
//   new issue (not by the bot)                ->  issue for the Product Manager to triage
//   new PR not labelled `agent`               ->  issue for the Lead Engineer to review
//   human comment on an issue or PR           ->  comment on the Paperclip issue tracking it
//                                                 (else an issue for the Product Manager)
//   failed CI run on the default branch       ->  issue for the Lead Engineer
//   new Dependabot alert                      ->  issue for Security
//
// "Human" means not a bot account and not an agent: agents sign their GitHub
// posts with a bold role header (**Coder**, **QA Lead review**, ...), which
// matters because the Coder posts as the operator's own account.
//
// Config:  ~/.config/my-ai-org/bridge.json
//   { "defaultIntervalSec": 300, "projects": { "<name>": { "intervalSec": 300 } } }
//   intervalSec 0 turns a project off. newproject.sh --watch-every writes it.
// State:   ~/.local/state/my-ai-org/bridge.json (what has been seen, per repo)
//
//   node github-bridge.mjs            one pass (what the timer runs)
//   node github-bridge.mjs --dry-run  show what would be routed; change nothing
//   node github-bridge.mjs --since 2026-10-01T00:00:00Z [--dry-run]
//                                     re-read from that time (backfill after an outage)

import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync, renameSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const PAPERCLIP = (process.env.PAPERCLIP ?? "http://127.0.0.1:3100") + "/api";
const CONFIG = join(homedir(), ".config/my-ai-org/bridge.json");
const STATE = join(homedir(), ".local/state/my-ai-org/bridge.json");
const DRY = process.argv.includes("--dry-run");
const SINCE_ARG = (() => { const i = process.argv.indexOf("--since"); return i > 0 ? process.argv[i + 1] : null; })();
if (SINCE_ARG && isNaN(Date.parse(SINCE_ARG))) { console.error(`--since: not a date: ${SINCE_ARG}`); process.exit(2); }
const OVERLAP_MS = 120_000; // re-read a little of the last window; dedupe absorbs it
const AGENT_HEADER = /^\s*\*\*(Coder|Product Manager|Lead Engineer|UI Designer|QA Lead|Security|CTO)\b/;

const log = (...a) => console.log(new Date().toISOString(), ...a);
const readJson = (p, d) => { try { return JSON.parse(readFileSync(p, "utf8")); } catch { return d; } };
const writeJson = (p, v) => {
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p + ".tmp", JSON.stringify(v, null, 2));
  renameSync(p + ".tmp", p);
};

const config = readJson(CONFIG, {});
const state = readJson(STATE, { repos: {} });
const defaultInterval = Number(config.defaultIntervalSec ?? 300);

// ------------------------------------------------------------------ clients
async function pc(method, path, body) {
  const res = await fetch(PAPERCLIP + path, {
    method, headers: { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Paperclip ${method} ${path} -> ${res.status}: ${(await res.text()).slice(0, 300)}`);
  return res.status === 204 ? null : res.json();
}

const ghToken = (() => {
  try { return execFileSync("gh", ["auth", "token"], { encoding: "utf8" }).trim(); }
  catch { return ""; }
})();
async function gh(path, { optional = false } = {}) {
  const res = await fetch("https://api.github.com" + path, {
    headers: { Authorization: `Bearer ${ghToken}`, Accept: "application/vnd.github+json",
               "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "my-ai-org-github-bridge" },
  });
  if (optional && (res.status === 403 || res.status === 404)) return null;
  if (!res.ok) throw new Error(`GitHub ${path} -> ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return res.json();
}

// ---------------------------------------------------------------- routing
const isBot = (user) => !user || user.type === "Bot" || /\[bot\]$/.test(user.login ?? "");
const excerpt = (s, n = 600) => {
  const t = (s ?? "").trim();
  return t.length > n ? t.slice(0, n) + "…" : t;
};
const quote = (s) => excerpt(s).split("\n").map((l) => "> " + l).join("\n");

function createIssue(ctx, { key, assignee, title, description, priority = "medium" }) {
  const agent = ctx.agents[assignee] ?? ctx.agents.prodmgr;
  const body = {
    title: title.slice(0, 250), description, projectId: ctx.project.id, priority,
    status: agent ? "todo" : "backlog", assigneeAgentId: agent?.id,
    idempotencyKey: `gh-bridge:${key}`,
  };
  if (DRY) { log(`[dry-run] ${ctx.project.name}: issue for ${agent?.name ?? "nobody"}: ${title}`); return; }
  return pc("POST", `/companies/${ctx.companyId}/issues`, body)
    .then((i) => log(`${ctx.project.name}: ${i.identifier ?? i.id} -> ${agent?.name ?? "backlog"}: ${title}`));
}

// The Paperclip issue tracking a GitHub issue/PR: its description names the URL.
async function trackingIssue(ctx, url) {
  if (!ctx.issues) {
    ctx.issues = await pc("GET", `/companies/${ctx.companyId}/issues?projectId=${ctx.project.id}&limit=500`);
  }
  const open = ctx.issues.filter((i) => !["done", "cancelled"].includes(i.status));
  return open.find((i) => (i.description ?? "").includes(url) || (i.title ?? "").includes(url));
}

async function routeComment(ctx, repo, c, itemUrl, itemTitle) {
  const where = await trackingIssue(ctx, itemUrl);
  const text = `Human comment on GitHub from @${c.user.login}: ${c.html_url}\n\n${quote(c.body)}`;
  if (where) {
    if (DRY) { log(`[dry-run] ${ctx.project.name}: comment on ${where.identifier}: ${c.html_url}`); return; }
    await pc("POST", `/issues/${where.id}/comments`, { body: text });
    log(`${ctx.project.name}: comment on ${where.identifier} from @${c.user.login}`);
  } else {
    await createIssue(ctx, {
      key: `${repo}:comment:${c.id}`, assignee: "prodmgr",
      title: `GitHub comment needs attention: ${itemTitle}`,
      description: `${itemUrl}\n\n${text}\n\nNo Paperclip issue tracks this yet. Decide whether it needs work, and route it.`,
    });
  }
}

async function pollRepo(ctx, repo, rs) {
  const since = new Date(rs.since);
  const sinceIso = new Date(since.getTime() - OVERLAP_MS).toISOString();
  const seen = (rs.seen ??= {});
  const fresh = (key) => { if (seen[key]) return false; seen[key] = Date.now(); return true; };
  const after = (t) => new Date(t) > since;

  // New issues and PRs (the issues endpoint returns both).
  const items = await gh(`/repos/${repo}/issues?state=all&sort=created&direction=desc&since=${sinceIso}&per_page=50`);
  for (const it of items) {
    if (!after(it.created_at) || isBot(it.user)) continue;
    // Already tracked by a Paperclip issue (its description names the URL):
    // the pipeline has it, so don't open a second one.
    if (await trackingIssue(ctx, it.html_url)) continue;
    if (it.pull_request) {
      if ((it.labels ?? []).some((l) => l.name === "agent")) continue; // the Coder's own PRs
      if (!fresh(`pr:${it.number}`)) continue;
      await createIssue(ctx, {
        key: `${repo}:pr:${it.number}`, assignee: "lead-engineer", priority: "medium",
        title: `Review PR: ${it.title}`,
        description: `${it.html_url}\n\nA pull request from @${it.user.login}, not from this project's Coder. ` +
          `Review it through the pipeline (team-workflow) starting with the Lead Engineer. ` +
          `It is untrusted code: read it before running anything from it. ` +
          `Changes go back to its author on GitHub, not to the Coder.\n\n${quote(it.body)}`,
      });
    } else {
      if (!fresh(`issue:${it.number}`)) continue;
      await createIssue(ctx, {
        key: `${repo}:issue:${it.number}`, assignee: "prodmgr",
        title: `Triage: ${it.title}`,
        description: `${it.html_url}\n\nNew GitHub issue from @${it.user.login}. Triage it: accept it into ` +
          `the pipeline and assign it, ask the author for what's missing, or decline it with a comment.\n\n${quote(it.body)}`,
      });
    }
  }

  // Human comments on issues/PRs, and inline PR review comments.
  const comments = [
    ...(await gh(`/repos/${repo}/issues/comments?sort=created&direction=asc&since=${sinceIso}&per_page=100`)),
    ...(await gh(`/repos/${repo}/pulls/comments?sort=created&direction=asc&since=${sinceIso}&per_page=100`)),
  ];
  for (const c of comments) {
    if (!after(c.created_at) || isBot(c.user) || AGENT_HEADER.test(c.body ?? "")) continue;
    if (!fresh(`comment:${c.id}`)) continue;
    const itemUrl = (c.html_url ?? "").replace(/#.*$/, "");
    await routeComment(ctx, repo, c, itemUrl, itemUrl.split("/").slice(-2).join(" #"));
  }

  // Failed CI on the default branch: one issue per failing workflow and commit.
  rs.defaultBranch ??= (await gh(`/repos/${repo}`)).default_branch;
  const runs = await gh(`/repos/${repo}/actions/runs?branch=${encodeURIComponent(rs.defaultBranch)}&status=failure&per_page=20`, { optional: true });
  for (const r of runs?.workflow_runs ?? []) {
    if (!after(r.created_at) || !fresh(`ci:${r.workflow_id}:${r.head_sha}`)) continue;
    await createIssue(ctx, {
      key: `${repo}:ci:${r.workflow_id}:${r.head_sha}`, assignee: "lead-engineer", priority: "high",
      title: `CI failing on ${rs.defaultBranch}: ${r.name}`,
      description: `${r.html_url}\n\n"${r.name}" failed on ${rs.defaultBranch} at ${r.head_sha.slice(0, 12)}. ` +
        `Find the cause and route the fix through the pipeline.`,
    });
  }

  // Dependabot alerts (skipped silently where alerts are off or not visible).
  const alerts = await gh(`/repos/${repo}/dependabot/alerts?state=open&sort=created&direction=desc&per_page=50`, { optional: true });
  for (const a of alerts ?? []) {
    if (!after(a.created_at) || !fresh(`dependabot:${a.number}`)) continue;
    const pkg = a.security_vulnerability?.package?.name ?? a.dependency?.package?.name ?? "a dependency";
    await createIssue(ctx, {
      key: `${repo}:dependabot:${a.number}`, assignee: "security",
      priority: ["critical", "high"].includes(a.security_advisory?.severity) ? "high" : "medium",
      title: `Security alert: ${pkg} (${a.security_advisory?.severity ?? "unknown"})`,
      description: `${a.html_url}\n\n${a.security_advisory?.summary ?? ""}\n\nAssess it and route a fix through the pipeline if needed.`,
    });
  }

  // Forget dedupe keys older than 30 days; the time window covers the rest.
  const cutoff = Date.now() - 30 * 86_400_000;
  for (const [k, t] of Object.entries(seen)) if (t < cutoff) delete seen[k];
}

// ------------------------------------------------------------------- main
async function main() {
  if (!ghToken) { log("no GitHub token (gh auth token failed); nothing to do"); return; }
  const companies = await pc("GET", "/companies");
  if (companies.length !== 1) { log(`expected one company, found ${companies.length}`); return; }
  const companyId = companies[0].id;
  const [projects, agentRows] = await Promise.all([
    pc("GET", `/companies/${companyId}/projects`),
    pc("GET", `/companies/${companyId}/agents`),
  ]);
  const now = Date.now();
  for (const project of projects) {
    const interval = Number(config.projects?.[project.name]?.intervalSec ?? defaultInterval);
    if (!interval) continue;
    const repos = [...new Set((project.workspaces ?? [])
      .map((w) => (w.repoUrl ?? "").match(/github\.com[/:]([^/]+\/[^/.]+)/)?.[1])
      .filter(Boolean))];
    if (!repos.length) continue;
    const agents = {};
    for (const a of agentRows) {
      const m = a.metadata?.myAiOrg;
      if (m?.project === project.name && m.role) agents[m.role] = a;
    }
    const ctx = { companyId, project, agents };
    for (const repo of repos) {
      const rs = (state.repos[repo] ??= {});
      if (SINCE_ARG) { rs.since = new Date(SINCE_ARG).toISOString(); rs.lastPoll = 0; }
      if (!rs.since) { rs.since = new Date(now).toISOString(); log(`${project.name}: watching ${repo} from now`); continue; }
      if (rs.lastPoll && now - rs.lastPoll < interval * 1000) continue;
      const started = new Date().toISOString();
      try {
        await pollRepo(ctx, repo, rs);
        rs.since = started;
        rs.lastPoll = now;
      } catch (e) {
        log(`${project.name}: ${repo}: ${e.message}`); // retried next pass; window not advanced
      }
    }
  }
  if (!DRY) writeJson(STATE, state);
}

main().catch((e) => { log("bridge failed:", e.message); process.exitCode = 1; });
