---
name: todo-update-state
description: Use when the user invokes /todo-update-state, says "mark X as done", "tick off task Y", "uncheck that", "set this to in-progress", "mark this project done", or wants to record progress without a full execution pass. Edits tasks.md checkboxes and the owning active or archived registry row in sync.
---

# Project State Skill

You update the recorded state of projects in a hub repo. This is the lightweight write companion to `todo-execute` — use it when the user just wants to *record* progress (check a task off, flip a status) without the agent actually doing the work. Your job is to keep checklist state and the owning registry row honest:

This is light, mechanical work. Use the **fast** tier from
[`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md) when dispatching is available; otherwise
perform the edits inline.

- **`tasks.md`** in each project — task checkboxes: `- [ ]` (not done) and `- [x]` (done)
- **`index.md` / `archive.md`** in the hub root — active and completed project rows,
  including `status`, `started`, and `completed` columns (see Step 3.5)

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Resolve **every** path against this absolute root — active `index.md`, cold `archive.md`, and each project's `path`/`tasks.md` — regardless of the current working directory. This skill may be invoked from another repo; never assume cwd is the hub. Pass this absolute root to the edit subagent so it writes there, not into the cwd. (Same convention as `todo-refer`.)

## How the user invokes this

```
/todo-update-state queue-migration       ← show that project's state, then edit it
/todo-update-state queue-migration done  ← mark the whole project done
/todo-update-state                               ← ask which project, or act on context
```

The user will usually say what they want in plain language: "mark the migration done", "tick off the first two tasks", "uncheck task 3", "set queue-migration back to ready", "this project is in-progress now". Interpret that against the resolved project.

## Step 1 — Resolve the project

Resolve exact short-names in `$TODO_HUB/index.md` first, then `$TODO_HUB/archive.md`
only on an active miss. Record the owning file and section with the full path and status.

- Short name → look it up active-first to get the `path`
- Full path passed directly → use as-is
- Duplicate across both registries → stop; the hub is corrupt and choosing one loses state
- Not found in either registry → tell the user and stop
- No project named and it's not obvious from context → ask which project before changing anything

## Step 2 — Show current state before editing

Read the project's `tasks.md` and report the current checklist with each task's checkbox state, plus the current `status` and whether its row is active or archived. This grounds the edit so the user (and you) act on what's actually there, not what you assume. Number the tasks so the user can refer to them ("task 3").

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

**Change status only** — update the owning row's `status` column to one of `planning` /
`ready` / `in-progress` / `done`; the archived-project reopen rule below still applies.

Before a flip to `in-progress` or `done`, run:

```bash
python3 <todo-graph-skill-dir>/scripts/graph-report.py context \
  "$TODO_HUB" "<short-name>"
```

Refuse the status flip when a hard prerequisite is unsatisfied or an incident graph
identity/cycle issue exists. Name the blocker and point at `/todo-graph why <short-name>`
or `/todo-graph audit`. Context and lineage edges never gate state. A direct state edit
must not bypass the same dependency gate that `/todo-execute` enforces.
If the helper is unavailable, stop before a flip to `in-progress` or `done`; do not infer
dependency safety from the registry's legacy `related` cell.

**Reopen an archived project** — any status change away from `done` is also a registry
move. Remove the row verbatim from its section in `archive.md`, append it to the same
section in `index.md`, then update status and dates there. Preserve custom section names;
if a legacy row's source section is unknown, ask before moving it. The row move, status
change, and Step 3.5 date clearing are one atomic edit.

Do not touch anything the user didn't ask about. Leave `plan.md`, `research/`, and `artifacts/` alone — this skill edits state, not content.

## Step 3.5 — Stamp started / completed on a status flip

`started` picks the earliest reliable signal, in priority order — **`in-progress` > `ready`
> `planning` > `completed`** (see `index.md`'s header prose for the full rationale). Whenever
this step's edit changes the `status` cell, also update that row's `started` / `completed`
cells, using today's date (`YYYY-MM-DD`):

- **Flips to `planning`** (new project via `/todo-add`) — stamp `started` to today if it's
  currently `-`. This is the lowest-tier provisional stamp — see the overwrite rules below.
  A flip *back* to `planning` on an existing project (rare) leaves `started`/`completed`
  unchanged — it's not a new project.
- **Flips to `ready`** (from `planning`) — stamp `started` to today, **overwriting** any
  tier-3 (`planning`) stamp already there. Still provisional — see next bullet.
- **Flips to `in-progress`** *from `ready` or `planning`* — always stamp `started` to today,
  **overwriting** any tier-2/tier-3 value (a direct `planning`→`in-progress` jump skips the
  `ready` stamp but is just as real a start). This is the real, final signal: once set this
  way it is never overwritten again.
- **Flips to `in-progress`** *from anything else* (e.g. reopened from `done`)
  — leave `started` alone. It already holds the best available first-start date; a later
  resume doesn't reset it.
- **Flips to `done`** — set `completed` to today. This one *does* overwrite — if the project
  was reopened and is completing again, the newer date is the honest one. Then, if `started`
  is *still* `-` at this point (none of tiers 1–3 ever fired — typically a row added
  directly as `done`, retroactively documenting work finished elsewhere), fall back to the
  last resort: set `started` to the same date as `completed`. Finally, compute
  `elapsed (days)` = `completed − started` in whole days (0 if same-day) and stamp it —
  computed at the moment `completed` is set (recomputed if the project re-completes),
  never live-recomputed afterwards.
- **Flips away from `done`** (reopened to `in-progress`/`ready`) — clear `completed` back to
  `-`, and clear `elapsed (days)` back to `-` alongside it; it's no longer true that the
  project is finished, so neither a completion date nor a duration is honest anymore.

A status column edit and its date-column edit are the same logical change — make them in one pass, not as a follow-up.

If a row's table predates these columns (header has no `started`), the plugin's
SessionStart hook (`hooks/migrate-index-dates.sh`) migrates and git-backfills it on the
next session. If you hit an unmigrated table mid-edit, widen it yourself first: insert
`started` / `completed` / `elapsed (days)` after `status` in the header and separator, and
`-` cells in every row, then apply the stamp.

## Step 4 — Keep status and tasks in sync

After editing, the project's status in its owning registry row and its task completion in
`tasks.md` should tell the same story. When they'd otherwise disagree, reconcile — and
say what you did:

- All tasks now checked, but status isn't `done` → offer to set it `done` (or just set it and report, if the user already said "mark done").
- A task got unchecked on a project marked `done` → it's no longer truly done; flag it and suggest moving status back to `in-progress`.
- First task checked on a `planning`/`ready` project → work has started; suggest `in-progress`.

Don't silently override the user's explicit instruction — if they said "set status to ready" while tasks are all checked, do what they asked and just note the mismatch.

**Archive housekeeping:** if the `tasks.md` you touched exceeds 20,480 bytes, mention it
and offer `/todo-archive <short-name>`. When this skill itself flips a revision tag to a
case-insensitive `[done…]`, immediately apply `todo-archive`'s canonical single-entry
rule: add `<a id="revision-r<n>"></a>` before the exact journal entry and leave
`[journal:R<n>](artifacts/journal.md#revision-r<n>)` in the two-line tombstone. Never
archive ordinary task checkboxes.

## Counting tasks

To report progress (e.g. "5/8 done"), count the checkboxes — but skip the `## Status` legend block that the `tasks.md` template includes (its `- [ ] Not started` / `- [x] Done` lines are documentation, not real tasks), and skip anything inside HTML comments (the template's `## Revisions` section ships a commented-out example with a `- [ ]` line). Count only checkboxes under the actual work sections (`## Tasks`, `## Phase …`, or real `## Revisions` entries).

A quick count from the shell (same snippet `todo-list` sort mode and `todo-infographic` use):

```bash
# completed/total real tasks — skips the ## Status legend and HTML-commented examples
awk '/<!--/{c=1} c{if(/-->/)c=0; next} /^## /{p=($0!~/^## Status/)} p&&/^[[:space:]]*- \[/{t++} p&&/^[[:space:]]*- \[x\]/{d++} END{print d+0"/"t+0}' tasks.md
```

## Step 5 — Confirm what changed

Report the edits plainly: which tasks flipped, the new completion count, and the status before → after. If a status flip stamped or cleared a `started`/`completed` date (Step 3.5), say so in the same line. Keep it short. If you reconciled a mismatch in Step 4, say so explicitly so the user knows state was kept consistent.
