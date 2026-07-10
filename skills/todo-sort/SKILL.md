---
name: todo-sort
description: Use when the user invokes /todo-sort, says "sort the index", "sort projects by completion", "reorder index.md", "rank my projects by progress", or asks to see most-finished work first. Reorders index.md rows by task completion.
---

# Project Sort Skill

You reorder the project tables in `index.md` so the user can see progress at a glance: the rows in each table are sorted by **how complete the project is**, most-done first.

This skill only changes **row order** inside each project section table (`## Work`, `## Self-initiative`, and any other section tables present). It never edits content (paths, repos, statuses, infographic links), never touches the headers, the intro prose, or the `## Status Legend`. The completion number is computed, not stored — it's used only to decide order and is not written into the table.

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Resolve **every** path against this absolute root — `index.md` and each project's `path`/`tasks.md` — regardless of the current working directory. This skill may be invoked from another repo; never assume cwd is the hub. Hand this absolute root to the sort subagent so it reads and writes there, not into the cwd. (Same convention as `todo-refer`.)

## The model this runs on

The completion read + sort is delegated to a subagent so it runs on **Claude Haiku (latest)** — it's mechanical counting and reordering, but the write-back must reproduce every non-reordered line byte-for-byte, so remind the subagent of that explicitly. Don't do the work inline in the orchestrating session — dispatch it. Use the `Agent` tool with `model: haiku`. The subagent does the reading, counting, sorting, and the write-back to `index.md`; the orchestrating session just dispatches it and relays the result.

## What "completion" means

For each project row, completion = `done / total` task checkboxes in that project's `tasks.md`:

- Count `- [x]` (done) and `- [ ]` (open) checkboxes.
- **Skip the `## Status` legend block** in `tasks.md` — its `- [ ] Not started` / `- [x] Done` lines are documentation, not tasks. Also **skip anything inside HTML comments** — the template's `## Revisions` section ships a commented-out example entry containing a `- [ ]` line that must not count. Per-project count:
  ```bash
  awk '/<!--/{c=1} c{if(/-->/)c=0; next} /^## /{p=($0!~/^## Status/)} p&&/^[[:space:]]*- \[/{t++} p&&/^[[:space:]]*- \[x\]/{d++} END{print d+0"/"t+0}' tasks.md
  ```
- A project with `total == 0` (no real tasks yet — typically `planning` status or a stub `tasks.md`) is **0% complete**.
- If a project's folder or `tasks.md` is missing/unreadable, treat it as 0% and note it in the summary.

The `path` column gives each project's folder; `tasks.md` lives directly inside it.

## Sort rules

Within each section table independently (`## Work`, `## Self-initiative`, …):

1. **Primary:** completion ratio, descending — most-complete (1.0) at the top, 0% at the bottom. A `done` project is 100%, so done work rises to the top.
2. **Tie-break:** stable — projects with equal completion keep their existing relative order. Don't reshuffle ties.

Do not merge tables, re-rank across them, or change which table a project is in.

## Steps

1. **Read `$TODO_HUB/index.md`**. Capture every row of every section table verbatim (all columns), and note the row order.
2. **Dispatch the Haiku subagent** (`Agent` tool, `model: haiku`). Hand it the hub root (`$TODO_HUB`) and the task: for each project row, resolve its `tasks.md` from the `path` column, compute completion via the awk above, then rewrite each section table in `index.md` sorted by the rules above — preserving headers, column content, and every other line of the file byte-for-byte. Tell it to return the new order per table with each project's `done/total` so you can report it.
3. **Relay the result.** Report, per table, the new top-to-bottom order with each project's `done/total` (and any projects counted as 0% because tasks.md was missing/empty). Keep it terse. Don't paste the whole file.

## Notes
- Idempotent: running it again on an already-sorted index is a no-op (stable sort, same data).
- This is order-only. If the user also wants statuses corrected or tasks ticked, that's `/todo-update-state`, not this skill.
