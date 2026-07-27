---
name: todo-list
description: Use when the user invokes /todo-list, asks to list projects or status, asks to show completed/archived projects, or says "sort the index", "rank projects by progress", or "reorder index.md". Default view reads active index.md only; archive view reads cold archive.md; sort reorders active rows only.
---

# Project List Skill

Render a compact project overview or reorder active projects by completion.

- **View** — read-only active overview from `index.md`.
- **Archive view** — read-only completed overview from `archive.md`.
- **All view** — read both registries only when explicitly requested.
- **Sort** — reorder rows inside active `index.md`; never edit content or `archive.md`.

Use the **fast** tier from
[`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md) when dispatching.

## Hub location

Resolve the hub from `$TODO_HUB` (default `~/todo`) regardless of the current working
directory. `index.md` is the active hot path; `archive.md` is cold completed history.

## Invocation

```text
/todo-list                 active overview
/todo-list in-progress     active status filter
/todo-list archive         completed projects only
/todo-list all             active plus archived
/todo-list sort            reorder active index.md by completion
```

Plain language counts: "what am I working on" means active view; "show completed
projects" means archive view; "rank active projects" means sort.

## View modes

Choose exactly one source:

| Mode | Files read | Rows shown |
|---|---|---|
| default / status filter | `index.md` | active sections only |
| `archive` | `archive.md` | completed sections only |
| `all` | `index.md`, then `archive.md` | both, clearly separated |

Ignore a legacy `## Archive` section still inside `index.md`, note that it needs
`/todo-archive registry`, and never mix it into the active overview.

Parse section tables and capture `short-name`, `path`, `repo`, `status`, infographic
presence, and date fields. Preserve section and row order. Render compact tables rather
than raw Markdown.

```text
Work
project             repo          status        info
api-token-rotation  api-service   in-progress   infographic
service-auth        -             planning      -
```

Keep full short-names because other skills resolve them. Show only the target registry's
count. In `all` mode, report active and archived totals separately.

`started`, `completed`, and `elapsed (days)` remain hidden unless the user asks for dates
or duration. Do not open `plan.md` or `tasks.md` in view mode.

If `archive.md` is absent or contains no rows, archive view says there are no archived
projects. Do not scaffold it here; bootstrap or `todo-archive` owns that file.

## Sort mode

Sort only section tables in active `index.md`, most complete first. Never read or write
`archive.md`; never reorder a legacy `## Archive` section.

### Completion

For each active row, completion is real checked tasks divided by real task checkboxes:

```bash
awk '/<!--/{c=1} c{if(/-->/)c=0; next} /^[[:space:]]*(```|~~~)/{f=!f; next} f{next} /^## /{p=($0!~/^## (Status|Notes|Context)([[:space:]]|$)/)} p&&/^[[:space:]]*- \[/{t++} p&&/^[[:space:]]*- \[x\]/{d++} END{print d+0"/"t+0}' tasks.md
```

- Skip the `## Status` legend, `## Notes` / `## Context` sections, HTML-commented
  examples, and fenced code — the same exclusions `graph-report.py` applies.
- Missing or empty `tasks.md` is 0%; report it.
- Sort descending by ratio; ties preserve existing relative order.
- Keep sections independent and reproduce every non-row line byte-for-byte.

Delegate the mechanical count and reorder to a fast-tier subagent when available, passing
the absolute hub root and the byte-preservation rule. Report the new order and `done/total`
for each section without pasting the whole file.

## Notes

- View modes are idempotent and read-only.
- Sort changes row order only.
- Status or checkbox changes belong to `todo-state`.
- Registry status is not dependency readiness. “What can I start now?” belongs to
  `todo-graph`, which evaluates canonical `depends-on` edges and completion evidence.
