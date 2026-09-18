---
name: todo-infographic
description: Use when the user invokes /todo-infographic, asks to visualize a hub project, or current-session plan/task edits make its infographic stale. Builds or incrementally refreshes artifacts/infographic.html and registers it without rebuilding unchanged visual structure.
---

# Project Infographic

Turn one project's `plan.md` and `tasks.md` into a self-contained, scannable HTML
one-pager. The plan remains the source of truth. Prefer the cheapest safe refresh;
a task checkbox change is not a design assignment.

## Hub and scope

Resolve every hub path against `$TODO_HUB` using
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md). Resolve named
projects active-first and record the owning registry row.

- A named project or the project clearly in scope means that project only.
- `all` means every ready, in-progress, or done project, but only when the user
  explicitly requests `all`.
- With no inferable project, ask; never turn a staleness list into bulk scope.

The orchestrator reads `plan.md` and `tasks.md` for resolution, stub checks, and
classification. If `plan.md` contains `What success looks like in one sentence.`
or lacks real Goal/Scope content, report the stub and stop. Semantic agents receive
only the compact manifest; a full-build agent may read the source files.

## Gather the file footprint

The orchestrator gathers execution-time truth from the target repo before
classification:

- Feature branch: diff merge-base with the default branch, then add uncommitted and
  untracked files.
- Default branch: use attributable uncommitted files or an identifiable merged
  range/PR from project evidence.
- Missing repo or no attributable changes: no footprint.

Write the flat status/path/optional-task-reason list to a temporary JSON file. Do
not put a large footprint directly in a subagent prompt. Reasons must come from a
clear task match; never invent them.

## Classify before designing

Read [references/refresh-contract.md](references/refresh-contract.md), then run its
`inspect` command with the project, registry status, today's date, current HTML,
and footprint JSON when one exists.

| Mode | Execution |
|---|---|
| `fresh` | No write and no model call |
| `fast-refresh` | Run deterministic `apply` inline; no subagent |
| `semantic-refresh` | Give one balanced-tier, medium-effort build agent only the compact manifest; apply its plain-text patch |
| `full-build` | Use the full design path below |

The semantic agent does **not** receive the full HTML, unchanged plan sections,
unchanged task phases, or design skills. It returns only the content-patch JSON
defined by the refresh contract. If it needs a new card, section, list row,
diagram node, rich markup, or an absent binding, escalate to `full-build`.

For a Stop-hook auto-trigger, run `fresh`, `fast-refresh`, and
`semantic-refresh`. Do not start a foreground full build merely to let the parent
turn stop: report that the legacy/structural infographic still needs explicit
`/todo-infographic <short-name>`. An explicit user invocation authorizes the full
build; dispatch it in the background when the host supports that while the
orchestrator remains responsive.

## Full design path

Use the balanced tier with high reasoning effort. Read
[references/design-spec.md](references/design-spec.md) and give the build agent:

- the absolute project and output paths;
- `plan.md`, `tasks.md`, the compact inspection manifest, and the temporary
  footprint JSON;
- existing HTML only when upgrading or structurally rebuilding an existing page;
- the design specification and refresh-marker contract.

Only full builds load `artifact-design`, `dataviz`, and at most one installed
design-critique/frontend-design pass. A content-only refresh never loads them.
Spawn one agent per project and parallelize only when the user explicitly asked
for several projects.

The agent writes marked HTML, then the orchestrator runs `apply --initialize` and
`verify` from the refresh contract. For an existing page, pass the pre-build CSS
hash from the inspection manifest so initialization proves the theme stayed
unchanged. A legacy unmarked page therefore pays for one final content-preserving
rebuild; later routine updates use the cheap paths.

The full-build agent returns exactly:

```json
{
  "short_name": "<project short-name>",
  "result": "written | skipped-stub",
  "path": "<hub-relative infographic path, or null>",
  "theme": "preserved | new",
  "sections_dropped": ["flow", "footprint"]
}
```

`theme: preserved` is valid only when every visual property and the CSS hash are
unchanged. Validate the object before using it; malformed output is a failed build,
not prose to interpret.

## Register and confirm

After a successful `apply` and `verify`, set the owning `index.md` or `archive.md`
row's `infographic` cell to:

```markdown
[open](projects/<category>/<short-name>/artifacts/infographic.html)
```

Do not create a separate infographic table. Report the generated/refreshed files,
the mode used, and any stubs or deferred full builds. Link the HTML; do not paste
it.
