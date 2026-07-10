---
name: todo-list
description: Use when the user invokes /todo-list, says "list my projects", "what's in the index", "show the todo", "what am I working on", "show project status", or asks for an overview of tracked work. Read-only view of index.md grouped by status.
---

# Project List Skill

You render the contents of `index.md` as a readable overview so the user can see the state of every tracked project at a glance. This is **read-only**: never edit `index.md`, `tasks.md`, statuses, or any project file. To change order use `/todo-sort`; to change state use `/todo-update-state`.

This is light, mechanical read/render work, so it runs on **Claude Haiku (latest)**. Use the `Agent` tool with `model: haiku` if dispatching.

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Read `$TODO_HUB/index.md` by absolute path regardless of the current working directory — this skill may be invoked from another repo; never assume cwd is the hub. (Same convention as `todo-refer`.)

## Steps

1. **Read `$TODO_HUB/index.md`**. Parse every project row from each section table (`## Work`, `## Self-initiative`, and any other section tables present). Capture `short-name`, `path`, `repo`, `status`, and whether an `infographic` link exists.
2. **Render the overview** (see format below). Don't dump the raw markdown table — reformat for skim-first reading.
3. **End with a one-line summary** counting projects by status.

## Output format

Group by **section** (Work, Self-initiative, etc.), preserving the row order already in `index.md` (it's kept progress-sorted by `/todo-sort` — don't re-sort here). Within each section, list projects with a status icon, name, repo, and an infographic marker.

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

## Summary line

After the tables, one terse line, e.g.:

```
17 projects — 6 done · 4 in-progress · 0 ready · 7 planning
```

## Optional filter

If the user names a status ("show in-progress", "what's planning"), list only matching projects across all sections instead of the full grouped view. Still end with the count.

## Notes
- Pure display. If `index.md` is missing or empty, say so and stop — don't scaffold it (that's `/todo-add`).
- Don't open `plan.md`/`tasks.md` or compute completion ratios — this reflects only what `index.md` records. For completion-ranked order use `/todo-sort`.
