---
name: todo-resume
description: Use when the user invokes /todo-resume, says "where was I", "pick up where we left off", "continue the migration project", "what happened last session", "what's the state of X", or starts a fresh session on a project that has prior work. Reconstructs where the work stopped — tasks, revisions, blockers, worktree/git state — and points at the next command.
---

# Project Resume Skill

You reconstruct **where a project's work actually stopped** so a fresh session can
continue instead of re-discovering. `todo-refer` loads the plan as grounding for a
*different* command; this skill answers "what happened, what's in flight, what's next"
and hands the user the exact next command to run.

**Read-only**: never edit `index.md`, `tasks.md`, hub files, or repo code. Resuming the
*work* is the follow-on command's job.

Run it inline on the main model — assembling the picture takes judgment about what
matters; do not downgrade to Haiku.

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Resolve **every** hub path against this absolute root regardless of the current working directory. This skill may be invoked from another repo; never assume cwd is the hub. (Same convention as `todo-refer`.)

## How the user invokes this

```
/todo-resume queue-migration     ← reconstruct that project's state
/todo-resume                     ← no name: resume the most recently touched in-progress project
```

Plain language counts too: "where did we leave the token rotation work", "continue where we stopped".

## Step 1 — Resolve the project

Read `$TODO_HUB/index.md` (same resolution rules as `todo-refer`: exact short-name
first, then fuzzy with confirmation).

No name given → pick the `in-progress` project whose files changed most recently
(`ls -t` the project folders' `tasks.md`), say which one you picked, and offer the
others. No `in-progress` projects at all → show the index like `/todo-list` and ask.

## Step 2 — Gather the trail (hub side)

Read, in order — extract, don't ingest whole files (large `tasks.md` rules from
`todo-refer` apply):

1. `plan.md` — `## Goal` and `## Verification` presence (full read only if small).
2. `tasks.md` — open tasks, open revisions, done/total (the `todo-refer` extraction
   snippets).
3. `artifacts/blockers.md` — every unresolved blocker, one line each.
4. `artifacts/journal.md` — the **last dated section only** (tail the file); it records
   the most recent closed work.
5. `artifacts/README.md` — the newest 2–3 rows (most recent outputs).

## Step 3 — Gather the trail (repo side)

If the index row names a target repo that exists locally:

```bash
git -C <repo> worktree list                          # is <repo>-wt/<short-name> still there?
git -C <repo> branch --list 'todo/<short-name>' 'feat/*'
git -C <repo> log origin/<base>..todo/<short-name> --oneline | head -5   # unshipped commits
git -C <repo>-wt/<short-name> status --short 2>/dev/null | head -10      # uncommitted work
gh pr list --repo <owner>/<repo> --head todo/<short-name> --state all --limit 3   # PR state (if gh works here)
```

Take what succeeds and skip what doesn't (no repo, no gh auth) — note gaps rather than
erroring. The point is to know whether work is **uncommitted, committed-but-unshipped,
in an open PR, or merged**.

## Step 4 — Emit the resume digest

One compact briefing, newest signal first:

```
## ⏪ queue-migration — where you left off

Goal: move order events from Redis pub/sub to RabbitMQ quorum queues
Status: in-progress · ▓▓▓▓▓▓░░░░ 12/20 tasks · 1 open revision

Last recorded work: R3 closed 2026-07-08 — consumer retry backoff (journal.md)
In flight:
- 🔄 worktree <repo>-wt/queue-migration exists · branch todo/queue-migration
- 🔄 3 commits unshipped (ahead of origin/main) · no open PR
- ⚠️ uncommitted changes in src/consumers/ (2 files)
Blockers:
- ❌ staging RabbitMQ creds missing (blockers.md, 2026-07-05)
Next open task: 4.2 dead-letter exchange for poison messages

▶ Next: /todo-execute queue-migration   (or /todo-push from the worktree to ship the 3 commits first)
```

The `▶ Next` line is the deliverable — pick ONE primary recommendation from the
evidence, with at most one alternative:

| Evidence | Recommend |
|---|---|
| Open tasks, no unshipped work | `/todo-execute <name>` |
| All tasks done, `## Verification` block in plan.md | `/todo-verify <name>` |
| Open revisions | `/todo-revise <name>` |
| Committed-but-unshipped worktree commits | `/todo-push` (from the worktree) |
| Only blockers remain | name the blocker — no command unblocks a missing credential |

## Notes
- Read-only, idempotent — run it at the start of any session.
- If hub state and repo state disagree (tasks ticked but no commits anywhere, or merged
  PRs for unticked tasks), say so in the digest and point at `/todo-sync` — don't
  reconcile here.
- Uncommitted changes in a worktree are the highest-priority signal: surface them first,
  they're the easiest thing to lose.
