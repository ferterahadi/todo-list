---
name: todo-sync
description: Use when the user invokes /todo-sync, says "is the index accurate", "does the todo match reality", "audit my project statuses", "this says done but it never shipped", or suspects hub state has drifted from what actually happened in the repos. Compares index.md status against tasks.md and target-repo git evidence, reports mismatches, and fixes them only on confirmation.
---

# Project Sync Skill

You audit whether the hub's **recorded** state matches **reality**. Statuses are only
honest if something checks them: a project marked `done` whose branch never merged, an
`in-progress` project whose PR landed weeks ago, ticked tasks with no commits anywhere —
each is drift, and drift compounds (triage routes wrong, resume misleads, sort lies).

Detection is the deliverable; **fixing needs a yes**. Report first, then apply only the
corrections the user confirms (via the same edit rules as `/todo-update-state`).

Hybrid, matching the hub's house pattern: evidence-gathering across 3+ projects is
mechanical — delegate it to a **fast**-tier subagent using
[`../model-routing.md`](../model-routing.md) when dispatching is available; for 1–2
projects gather inline. The drift *verdicts* are judgment — always yours, inline on the
main model.

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Resolve every hub path against this absolute root regardless of the current working directory. This skill may be invoked from another repo; never assume cwd is the hub. (Same convention as `todo-refer`.)

## How the user invokes this

```
/todo-sync                      ← audit every ready/in-progress/done project
/todo-sync queue-migration      ← audit one project
/todo-sync fix                  ← audit, then apply confirmed fixes
```

Plain language counts too: "does my index match reality", "audit the hub".

## Step 1 — Resolve scope

Read `$TODO_HUB/index.md`. Default scope: every `ready` / `in-progress` / `done` row in
the active section tables (`planning` rows have nothing to drift against; `## Archive`
rows are skipped). A short-name limits to that project; not found → say so and stop.

## Step 2 — Gather evidence per project

Three sources, cross-checked:

1. **Recorded status** — the `status` column.
2. **Task state** — `done/total` via the shared awk snippet (skip the `## Status`
   legend and HTML comments, same as `todo-list` sort mode), plus open
   `### R<n> … [open]` revision headings.
3. **Repo evidence** — when the row names a local repo:
   ```bash
   git -C <repo> fetch origin --quiet
   git -C <repo> branch -a --list '*todo/<short-name>*' '*feat/*'
   git -C <repo> log origin/<base> --oneline --since='30 days' -- <plan-scoped-paths> | head -5
   gh pr list --repo <owner>/<repo> --search 'head:todo/<short-name>' --state all --limit 3
   git -C <repo> worktree list | grep '<short-name>'
   ```
   Take what succeeds (no gh auth, no repo → note the gap, don't fail the audit). What
   you want per project: **branch merged / PR open / commits exist / worktree lingering /
   no trace at all**.

Hub-only projects (repo `-`) are checked on sources 1–2 plus artifacts: `done` with an
empty `artifacts/` is suspicious; say so.

## Step 3 — Judge drift

Compare the three sources. The canonical mismatches and their fixes:

| Recorded | Evidence | Drift | Suggested fix |
|---|---|---|---|
| `done` | open tasks or `[open]` revisions | not actually done | status → `in-progress` |
| `done` | branch never merged / PR open | shipped on paper only | status → `in-progress`, point at `/todo-push` |
| `in-progress` | all tasks ticked, PR merged, worktree clean | finished but never recorded | status → `done` (via `/todo-verify` if plan.md has a `## Verification` block — the gate flips `done`, not this skill) |
| `ready`/`in-progress` | no commits, no worktree, tasks all unticked | stale — never started | status → `ready`, or ask if it's abandoned |
| any | ticked tasks but no commits/artifacts evidencing them | unbacked claims | flag the specific tasks; suggest `/todo-review <name>` for the audit-by-diff |
| any | lingering worktree with uncommitted changes | work at risk | surface it — `/todo-resume <name>` before anything else |

Evidence gaps (couldn't check gh, repo missing locally) make a project **unverifiable**,
not drifted — report it in its own bucket, never guess a verdict from partial evidence.

## Step 4 — Report the drift board

```
## 🔎 Hub sync — 14 projects audited

| project | recorded | evidence | verdict | fix |
|---|---|---|---|---|
| queue-migration | done | PR #42 still open | ❌ drifted | → in-progress, ship via /todo-push |
| api-token-rotation | in-progress | merged, 20/20 tasks | ❌ drifted | → done (verify gate first) |
| service-auth | ready | no repo locally | ⚠️ unverifiable | clone repo or fix repo column |
| 11 others | — | — | ✅ consistent | — |

2 drifted · 1 unverifiable · 11 consistent
```

Every drifted row cites its evidence (PR URL, branch, task numbers) — a verdict without
the evidence line is not reportable.

## Step 5 — Apply fixes (only on a yes)

If invoked as `/todo-sync fix`, or the user confirms after the board: apply exactly the
confirmed corrections — status column flips in `index.md`, checkbox reconciliation in
`tasks.md` — following `todo-update-state`'s edit + sync rules (delegate the mechanical
edits to the fast tier when available). Re-render the fixed rows. Never fix silently, never fix beyond what was
confirmed, and never flip a status to `done` past an unrun `## Verification` gate —
point at `/todo-verify` instead.

## Notes
- Detection is idempotent and safe to run weekly; nothing changes without confirmation.
- This skill reconciles **state**; it never edits code, plans, or task text.
- `/todo-verify` proves behavior via a verification run; this skill cross-checks
  bookkeeping against git. Verify is the gate, sync is the audit.
