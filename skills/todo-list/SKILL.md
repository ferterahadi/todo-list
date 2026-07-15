---
name: todo-list
description: Use when the user invokes /todo-list, says "list my projects", "what's in the index", "show the todo", "what am I working on", "show project status", or asks for an overview of tracked work — or says "sort the index", "sort projects by completion", "reorder index.md", "rank my projects by progress". The view is read-only; sort mode reorders index.md rows by task completion and changes nothing else.
---

# Project List Skill

You render the contents of `index.md` as a readable overview so the user can see the state of every tracked project at a glance — and, in **sort mode**, reorder its rows by task completion so the most-finished work sits on top.

Two modes, one skill:

- **View (default)** — **read-only**: never edit `index.md`, `tasks.md`, statuses, or any project file. To change state use `/todo-update-state`.
- **Sort** — changes **row order only** inside each section table. It never edits content (paths, repos, statuses, infographic links), never touches headers, intro prose, or the `## Status Legend`.

Both modes are light, mechanical work. Use the **fast** tier from
[`../model-routing.md`](../model-routing.md) if dispatching; otherwise run inline.

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Read and write `$TODO_HUB/index.md` by absolute path regardless of the current working directory — this skill may be invoked from another repo; never assume cwd is the hub. (Same convention as `todo-refer`.)

## How the user invokes this

```
/todo-list                ← view: the grouped overview
/todo-list in-progress    ← view: only projects with that status
/todo-list sort           ← sort mode: reorder index.md by completion
```

Plain language counts too: "what am I working on" → view; "rank my projects by progress" → sort.

## View mode

1. **Read `$TODO_HUB/index.md`**. Parse every project row from each section table (`## Work`, `## Self-initiative`, and any other section tables present). Capture `short-name`, `path`, `repo`, `status`, and whether an `infographic` link exists.
2. **Render the overview** (see format below). Don't dump the raw markdown table — reformat for skim-first reading.
3. **End with a one-line summary** counting projects by status.

### Output format

Group by **section** (Work, Self-initiative, etc.), preserving the row order already in `index.md` (it's kept progress-sorted by sort mode — don't re-sort in the view). Within each section, list projects with a status icon, name, repo, and an infographic marker.

Map status → icon:

| status | icon |
|---|---|
| `done` | ☑️ |
| `in-progress` | 🔄 |
| `ready` | ✅ |
| `planning` | ➖ |

Use a compact table per section, e.g.:

```
## Work

| | project | repo | status | info |
|---|---|---|---|---|
| 🔄 | api-token-rotation | api-service | in-progress | 📊 |
| ➖ | service-auth | — | planning | — |
```

- `repo`: show the trailing folder name only (e.g. `~/code/api-service` → `api-service`); show `—` when repo is `-`.
- `info`: `📊` if an infographic link exists, `—` otherwise.
- Keep the project's full `short-name` — it's what the other `/todo-*` skills resolve against.

### Summary line

After the tables, one terse line, e.g.:

```
17 projects — 6 done · 4 in-progress · 0 ready · 7 planning
```

### Optional filter

If the user names a status ("show in-progress", "what's planning"), list only matching projects across all sections instead of the full grouped view. Still end with the count.

### View notes
- Pure display. If `index.md` is missing or empty, say so and stop — don't scaffold it (that's `/todo-add`).
- Don't open `plan.md`/`tasks.md` or compute completion ratios in the view — it reflects only what `index.md` records. For completion-ranked order run sort mode.

## Sort mode

Reorders the project tables in `index.md` so rows in each table are sorted by **how complete the project is**, most-done first. The completion number is computed, not stored — it decides order only and is never written into the table.

Delegate the work to a **fast**-tier subagent when available — it is mechanical counting
and reordering, but the write-back must reproduce every non-reordered line byte-for-byte,
so state that explicitly. Hand it the absolute hub root (`$TODO_HUB`) so it reads and
writes there, not into the cwd.

### What "completion" means

For each project row, completion = `done / total` task checkboxes in that project's `tasks.md`:

- Count `- [x]` (done) and `- [ ]` (open) checkboxes.
- **Skip the `## Status` legend block** in `tasks.md` — its `- [ ] Not started` / `- [x] Done` lines are documentation, not tasks. Also **skip anything inside HTML comments** — the template's `## Revisions` section ships a commented-out example entry containing a `- [ ]` line that must not count. Per-project count:
  ```bash
  awk '/<!--/{c=1} c{if(/-->/)c=0; next} /^## /{p=($0!~/^## Status/)} p&&/^[[:space:]]*- \[/{t++} p&&/^[[:space:]]*- \[x\]/{d++} END{print d+0"/"t+0}' tasks.md
  ```
- A project with `total == 0` (no real tasks yet — typically `planning` status or a stub `tasks.md`) is **0% complete**.
- If a project's folder or `tasks.md` is missing/unreadable, treat it as 0% and note it in the summary.

The `path` column gives each project's folder; `tasks.md` lives directly inside it.

### Sort rules

Within each section table independently (`## Work`, `## Self-initiative`, …):

1. **Primary:** completion ratio, descending — most-complete (1.0) at the top, 0% at the bottom. A `done` project is 100%, so done work rises to the top.
2. **Tie-break:** stable — projects with equal completion keep their existing relative order. Don't reshuffle ties.

Do not merge tables, re-rank across them, or change which table a project is in.

### Sort steps

1. **Read `$TODO_HUB/index.md`**. Capture every row of every section table verbatim (all columns), and note the row order.
2. **Dispatch the fast-tier subagent** when available. Hand it the hub root (`$TODO_HUB`)
   and the task: for each project row, resolve its `tasks.md` from the `path` column,
   compute completion via the awk above, then rewrite each section table in `index.md`
   sorted by the rules above — preserving headers, column content, and every other line
   byte-for-byte. Tell it to return the new order per table with each project's
   `done/total` so you can report it. If dispatching is unavailable, perform this step
   inline with the same preservation rule.
3. **Relay the result.** Report, per table, the new top-to-bottom order with each project's `done/total` (and any projects counted as 0% because tasks.md was missing/empty). Keep it terse. Don't paste the whole file.

### Sort notes
- Idempotent: sorting an already-sorted index is a no-op (stable sort, same data).
- Order-only. If the user also wants statuses corrected or tasks ticked, that's `/todo-update-state`, not this skill.
