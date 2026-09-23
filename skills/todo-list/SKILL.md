---
name: todo-list
description: Use when the user invokes /todo-list, asks to list projects, wants the status overview of all projects ("what am I working on", "how far along is everything"), asks to show completed/archived projects, or says "sort the index", "rank projects by progress", or "reorder index.md". Hub-wide overview only — one project's context or where-was-I is todo-refer, and changing or auditing recorded state is todo-state. Default view reads active index.md plus one progress count; archive view reads cold archive.md; sort reorders active rows only.
---

# Project List Skill

Render a compact project overview or reorder active projects by completion.

- **View** — read-only active overview from `index.md`, with task progress.
- **Archive view** — read-only completed overview from `archive.md`.
- **All view** — read both registries only when explicitly requested.
- **Sort** — reorder rows inside active `index.md`; never edit content or `archive.md`.

Use the **fast** tier from
[`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md) when dispatching.

## Hub location

Resolve every hub path against `$TODO_HUB` — see
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Hub location.

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

Progress comes from one helper call for the whole hub, never from reading `tasks.md`:

```bash
python3 <todo-graph-skill-dir>/scripts/graph-report.py export "$TODO_HUB"
```

Each `NODE` row carries `tasks=<done>/<total>` and `open_revisions=<n>` for one project,
counted by the canonical rule in
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Counting tasks. Match a
row to its `NODE` by short-name and registry; read the rows, not the exit status (exit 1
only flags graph issues — mention `/todo-graph audit` when `ERROR` rows appear). If the
helper is unavailable, show `-` in the progress column and say why.

```text
Work
project             repo          status        progress          info
api-token-rotation  api-service   in-progress   14/20 · 1 rev     infographic
service-auth        -             planning      0/0               -
```

Append `· <n> rev` only when `open_revisions` is above zero. Archive and all views take
their progress from the same call (registry `archive`); never run it twice.

Keep full short-names because other skills resolve them. Show only the target registry's
count. In `all` mode, report active and archived totals separately.

`started`, `completed`, and `elapsed (days)` remain hidden unless the user asks for dates
or duration. Do not open `plan.md` or `tasks.md` in view mode; the helper's counts are the
only task data the view shows.

If `archive.md` is absent or contains no rows, archive view says there are no archived
projects. Do not scaffold it here; bootstrap or `todo-archive` owns that file.

## Sort mode

Sort only section tables in active `index.md`, most complete first. Never read or write
`archive.md`; never reorder a legacy `## Archive` section.

### Completion

Completion is `done/total` from the same single `graph-report.py export` call the view
uses — one call for the whole hub, never one count per project. Use only `NODE` rows whose
registry is `active`.

- `tasks=0/0` (missing or empty `tasks.md`) is 0%; report it.
- Sort descending by ratio; ties preserve existing relative order.
- Keep sections independent and reproduce every non-row line byte-for-byte.
- Helper unavailable → stop and report; do not count by hand.

Delegate the mechanical reorder to a fast-tier subagent when available, passing the
absolute hub root, the `done/total` per short-name, and the byte-preservation rule. Report
the new order and `done/total` for each section without pasting the whole file.

## Notes

- View modes are idempotent and read-only.
- Sort changes row order only.
- Status or checkbox changes belong to `todo-state`.
- Registry status is not dependency readiness. “What can I start now?” belongs to
  `todo-graph`, which evaluates canonical `depends-on` edges and completion evidence.
