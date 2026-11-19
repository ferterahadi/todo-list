---
name: todo-review
description: Use when the user invokes /todo-review, says "review this against the plan", "does the diff match the plan", "check this work before verify", "review what the agent built for X", "review what the parallel wave merged", or has changes in a repo that belong to a hub project and wants them reviewed. Reviews a diff against the project's plan.md — scope, constraints, claimed-done tasks — plus a correctness pass.
---

# Project Review Skill

You review a repo's changes **against the hub project's plan**, closing the seam between
`todo-execute` (build) and `todo-verify` (gate). A generic code review checks whether
code is *good*; this skill first checks whether it's *the code the plan asked for* —
scope drift, violated constraints, and checked-off tasks the diff doesn't actually
evidence — then runs the correctness pass.

Without this skill the flow is two manual commands (`/todo-refer <name>` then
`/code-review`); this skill is that pairing as one deliberate step, with the plan
comparison the generic review can't do.

**Report-only on the hub**: never edit `index.md`, `tasks.md`, or `plan.md`. Findings
become the user's call — fixes land via `/todo-revise` (drifted done work) or directly
in the working tree if the user asks.

This is judgment work. Run it inline on the current session model; use at least the
**balanced** tier from [`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md).

## Hub location

Resolve every hub path against `$TODO_HUB` — see
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Hub location. This skill
is usually invoked from the target repo, so the cwd is the one thing the hub is never
resolved against.

## How the user invokes this

```
/todo-review queue-migration                 ← current repo's unlanded diff vs that plan
/todo-review queue-migration #1062           ← one PR, open or merged
/todo-review queue-migration a1b2c3d..origin/main  ← a landed range, e.g. after a parallel wave
/todo-review                                 ← infer the active project from the current repo
```

Plain language counts too: "review this against the plan", "did the parallel agents build what the plan said".

## Step 1 — Resolve project and load the plan

Resolve an explicit short-name per
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Resolving a project.
With no name, resolve a linked checkout to its primary repo and look for matching
active `index.md` rows. Search `archive.md` only when no active row matches. One match → use it and say which
registry supplied it; several or none → ask.

Load the grounding the way `todo-refer` does: `plan.md` in full (Goal, Scope,
Constraints, Key Decisions); every task with its state and ID
(`python3 <todo-graph-skill-dir>/scripts/graph-report.py tasks "$TODO_HUB" <short-name>`,
or extract `tasks.md` directly when that helper isn't installed); and the newest dated
section of `artifacts/journal.md` plus the newest `artifacts/*-handoff-*.md`, if any —
the latest recorded stretch of work. Step 3 builds the claimed-done set from these.

## Step 2 — Establish the diff

Use the resolved project's registered repo as the Git/gh context, including when the
command was invoked from the hub. Validate paths and refs per
[`todo-conventions`](../todo-conventions/SKILL.md) § Placeholder safety.

**Explicit PR or range** — review just that patch and go to Step 3. Run
`gh pr diff <number>` from the registered repo, or `git -C "<repo>" diff "<range>" --`.
Use a digits-only PR number. Each endpoint of a two-dot or three-dot range must
match `^[A-Za-z0-9._/~^-]+$`, must not start with a dash, and must resolve to a
commit in the registered repo. An explicit review excludes all local edits.

**Current work** — list checkouts with `git -C "<repo>" worktree list --porcelain`.
Use the user's named checkout or the current checkout if it belongs to this project.
From the hub, select the project's linked worktree by its branch/path. For parallel
worktrees, use the project's attributed `WORKTREE` rows from the read-only
`repo-evidence.sh` lookup in `todo-refer` Step 5. Ask which checkout if several
fit. With no linked project worktree, inspect the registered checkout if its branch
and changes belong to the requested project.

From that worktree, inspect the content of each layer:

```bash
git -C "<worktree>" status --short --untracked-files=all
git -C "<worktree>" symbolic-ref --short refs/remotes/origin/HEAD
git -C "<worktree>" diff "origin/<base>...HEAD" --  # committed branch work
git -C "<worktree>" diff --cached --                # staged
git -C "<worktree>" diff --                         # unstaged
git -C "<worktree>" ls-files --others --exclude-standard
```

Read the relevant untracked files from that worktree and trace findings against the
current file content so an unstaged correction to a staged change is accounted for.
If the base ref is unavailable, identify it from repo evidence or report the missing
comparison. Local edits can still be reviewed.

On a clean base checkout with no project diff, list recent landings from the registered
repo (`git -C "<repo>" log --first-parent --format='%h %s' -15 "origin/<base>"`).
Confirm the project’s oldest and newest landing with the user before reviewing the
range. If nothing matches, say so. Report the checkout, branch or explicit range,
and the distinct files reviewed before giving findings.

## Step 3 — Plan-compliance review (what generic review can't see)

Read the diff with `plan.md` open. Three checks, each producing findings with
file:line references:

1. **Scope** — files/areas the diff touches that the plan's scope never mentions
   (drift), and plan scope the ticked tasks claim but the diff doesn't touch (gaps).
   A diff can be excellent code and still be the wrong code.
2. **Constraints** — anything in `## Constraints` / `## Key Decisions` the diff
   contradicts (wrong library, forbidden pattern, decision silently reversed). Quote the
   plan line next to the violating hunk.
3. **Claimed-done evidence** — `tasks.md` has no timestamps and the hub isn't a git
   repo, so "ticked recently" can't be read off a checkbox. The **claimed-done set** is
   every `[x]` task that either the latest journal section or handoff records as done, or
   whose phase or named files the diff touches. For each, point at the diff hunks (or
   artifacts) that evidence it, and say which source put it in the set. A `[x]` in the set
   with no corresponding change is a finding — the checkbox is a claim, and this is the
   audit. A `[x]` in neither source is outside this diff's reach; don't audit it here.

Where the plan is silent, that's a plan gap, not a violation — note it separately and
point at `/todo-plan` rather than inventing a rule to enforce.

## Step 4 — Correctness pass

Invoke the installed `code-review` skill on the same diff, with the plan's intent
(Goal + constraints) restated so its findings are grounded — effort matched to the
work's tier (`todo-triage`'s rubric: mechanical → low, routine → medium,
security/concurrency → high). If no `code-review` skill is installed in this session,
do a direct correctness read of the diff yourself and say that's what happened.

## Step 5 — Report

One board, plan findings before code findings — severity-ordered, each row actionable:

```
## 🔍 queue-migration — review vs plan   (todo/queue-migration, 14 files vs origin/main)

Plan compliance:
| # | finding | where | plan says |
|---|---|---|---|
| P1 | ⚠️ retry logic added to producer — outside plan scope | src/producer.ts:88 | scope: consumers only |
| P2 | ❌ task 4.1 ticked (journal 2026-07-08), but no dead-letter exchange in diff | tasks.md 4.1 | Phase 4 |

Correctness (via code-review):
| # | finding | where |
|---|---|---|
| C1 | ❌ ack sent before the handler commits — a crash drops the message | src/consumer.ts:41 |
| C2 | ⚠️ retry count never reset between messages | src/consumer.ts:97 |

Verdict: not ready for /todo-verify — P2 is a claimed-done gap, C1 loses messages.
▶ Next: /todo-revise queue-migration (capture P2 as a gap) · fix C1 · fix P1 or amend the plan
```

The verdict line answers one question: **is this ready for `/todo-verify` / `/todo-push`,
or does something go back?** Findings that survive user triage become `/todo-revise`
gaps — offer to carry them over, don't write Revisions entries yourself. The `▶ Next`
command is an act-now pointer; a later session gets `/todo-refer <short-name> resume`
instead — see [`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Session
handoff.

When someone other than the user must rule on the findings — a product manager, another
team, a reviewer who won't read the diff — end with one line offering
`/todo-review-handoff <short-name>`, which turns this board into checkable claims and a
ruling sheet. It reuses these findings; it doesn't review again.

## Notes
- Hub-read-only; repo-read-only. This skill changes nothing — it produces findings.
- Reviewing mid-execution is fine (uncommitted diff); reviewing after
  `/todo-execute parallel` merges is the other common moment — then the diff is the
  merged PRs vs the pre-wave base (Step 2's landed-range branch).
- `/todo-verify` checks *behavior* via the verification MCP; this skill checks *intent*
  via the plan. They complement, not replace, each other.
