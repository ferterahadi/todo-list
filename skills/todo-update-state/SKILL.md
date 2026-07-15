---
name: todo-update-state
description: Use when the user invokes /todo-update-state, says "mark X as done", "tick off task Y", "uncheck that", "set this to in-progress", "mark this project done", or wants to record progress without a full execution pass. Edits tasks.md checkboxes + index.md status in sync.
---

# Project State Skill

You update the recorded state of projects in a hub repo. This is the lightweight write companion to `todo-execute` — use it when the user just wants to *record* progress (check a task off, flip a status) without the agent actually doing the work. State lives in two places, and your job is to edit them and keep them honest:

This is light, mechanical work. Use the **fast** tier from
[`../model-routing.md`](../model-routing.md) when dispatching is available; otherwise
perform the edits inline.

- **`tasks.md`** in each project — task checkboxes: `- [ ]` (not done) and `- [x]` (done)
- **`index.md`** in the hub root — the `status` column per project: `planning` → `ready` → `in-progress` → `done`

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Resolve **every** path against this absolute root — `index.md` and each project's `path`/`tasks.md` — regardless of the current working directory. This skill may be invoked from another repo; never assume cwd is the hub. Pass this absolute root to the edit subagent so it writes there, not into the cwd. (Same convention as `todo-refer`.)

## How the user invokes this

```
/todo-update-state queue-migration       ← show that project's state, then edit it
/todo-update-state queue-migration done  ← mark the whole project done
/todo-update-state                               ← ask which project, or act on context
```

The user will usually say what they want in plain language: "mark the migration done", "tick off the first two tasks", "uncheck task 3", "set queue-migration back to ready", "this project is in-progress now". Interpret that against the resolved project.

## Step 1 — Resolve the project

Read `$TODO_HUB/index.md` to map short names → full paths and current status.

- Short name → look it up in `index.md` to get the `path`
- Full path passed directly → use as-is
- Not found → tell the user and stop
- No project named and it's not obvious from context → ask which project before changing anything

## Step 2 — Show current state before editing

Read the project's `tasks.md` and report the current checklist with each task's checkbox state, plus the current `status` from `index.md`. This grounds the edit so the user (and you) act on what's actually there, not what you assume. Number the tasks so the user can refer to them ("task 3").

If `tasks.md` is missing or empty, say so — there's nothing to check off yet, and `/todo-plan <name>` is the way to create tasks.

## Step 3 — Apply the requested change

Make exactly the edits the user asked for. The common operations:

**Mark a task done / not done** — flip the checkbox in `tasks.md`:
- done: `- [ ] …` → `- [x] …`
- not done: `- [x] …` → `- [ ] …`

Match on the task's text, not its position alone, so you edit the right line even if the list shifts. If the user refers to a task by number, map the number to the task you showed in Step 2.

**Mark the whole project done / not done:**
- "done" → check every task in `tasks.md` and set `status: done` in `index.md`
- "not done" / "reopen" → the user will usually mean the status, not unchecking every task; confirm whether they want tasks unchecked too before doing it, since that's destructive to recorded progress.

**Change status only** — update just the `status` column for that project's row in `index.md` to one of `planning` / `ready` / `in-progress` / `done`.

Do not touch anything the user didn't ask about. Leave `plan.md`, `research/`, and `artifacts/` alone — this skill edits state, not content.

## Step 4 — Keep status and tasks in sync

After editing, the project's `status` in `index.md` and its task completion in `tasks.md` should tell the same story. When they'd otherwise disagree, reconcile — and say what you did:

- All tasks now checked, but status isn't `done` → offer to set it `done` (or just set it and report, if the user already said "mark done").
- A task got unchecked on a project marked `done` → it's no longer truly done; flag it and suggest moving status back to `in-progress`.
- First task checked on a `planning`/`ready` project → work has started; suggest `in-progress`.

Don't silently override the user's explicit instruction — if they said "set status to ready" while tasks are all checked, do what they asked and just note the mismatch.

**Size housekeeping (offer, don't auto-do):** if the `tasks.md` you touched exceeds
~20KB, mention it and offer the archival sweep from `todo-revise`'s "Archival rule" —
move `[done]` revision detail to `artifacts/journal.md`, leaving heading + one
`archived →` line per entry. Same discipline for closed `[done]` revision checkboxes
you flip here: after flipping, apply the same two-line tombstone collapse.

## Counting tasks

To report progress (e.g. "5/8 done"), count the checkboxes — but skip the `## Status` legend block that the `tasks.md` template includes (its `- [ ] Not started` / `- [x] Done` lines are documentation, not real tasks), and skip anything inside HTML comments (the template's `## Revisions` section ships a commented-out example with a `- [ ]` line). Count only checkboxes under the actual work sections (`## Tasks`, `## Phase …`, or real `## Revisions` entries).

A quick count from the shell (same snippet `todo-list` sort mode and `todo-infographic` use):

```bash
# completed/total real tasks — skips the ## Status legend and HTML-commented examples
awk '/<!--/{c=1} c{if(/-->/)c=0; next} /^## /{p=($0!~/^## Status/)} p&&/^[[:space:]]*- \[/{t++} p&&/^[[:space:]]*- \[x\]/{d++} END{print d+0"/"t+0}' tasks.md
```

## Step 5 — Confirm what changed

Report the edits plainly: which tasks flipped, the new completion count, and the status before → after. Keep it short. If you reconciled a mismatch in Step 4, say so explicitly so the user knows state was kept consistent.
