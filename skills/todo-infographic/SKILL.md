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
| `legacy-migration` | Insert refresh markers deterministically; use one bounded exact patch only when stale prose or cards must change |
| `full-build` | Use the full design path below |

The semantic agent does **not** receive the full HTML, unchanged plan sections,
unchanged task phases, or design skills. It returns only the content-patch JSON
defined by the refresh contract. If it needs a new card, section, list row,
diagram node, rich markup, or an absent binding, escalate to `full-build`.

Finish every in-scope `plan.md` and `tasks.md` edit before `inspect`. The manifest
freezes both source hashes; never dispatch a content agent and then change either
source. If a source changes, discard the patch, inspect again, and redispatch.

For a Stop-hook auto-trigger, run `fresh`, `fast-refresh`, and `semantic-refresh`.
`legacy-migration` always needs an explicit semantic review decision, so do not start
it—or a foreground full build—merely to let the parent turn stop: report the exact
explicit command still needed.
An explicit user invocation authorizes a bounded legacy content patch or full build;
dispatch it in the background when the host supports that while the orchestrator
remains responsive.

## Legacy migration

Read [references/refresh-contract.md](references/refresh-contract.md). The helper
recognizes unambiguous task totals, phase meters, generated date, and decision cards,
then inserts markers without serializing the page. It preserves every `<style>` byte
and refuses ambiguous structure.

Legacy HTML has no source baseline, so absence of a structural mismatch does not prove
its prose is current. After a bounded review finds no stale content, run `migrate
--confirm-content-current`; no model reads the full HTML. When stale content must change:

1. Extract only the changed source block and the smallest matching HTML fragment with
   `fragment`. Never give the agent the full HTML, unchanged phases, or design skills.
2. Use the balanced tier at medium effort. Ask for only the exact-patch JSON from the
   refresh contract. The bounded patch may replace at most eight exact fragments and
   64 KiB total; it is not a rewritten page.
3. Run `migrate --exact-patch`, then `verify`. Migration rejects a stale inspection
   manifest, a non-unique replacement, a source edit made after inspection, CSS drift,
   missing bindings, or stale decision structure.

If the helper reports `legacy-migration-ambiguous`, use `full-build`; do not weaken its
proof checks or guess selectors.

## Full design path

Use the balanced tier with **exactly high** reasoning effort. High is the ceiling as
well as the floor: never request or inherit `xhigh` or `max`. If the host cannot select
the worker's effort, use a supported scoped session set to high; do not send a large
build into an inherited higher effort. Read
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

Monitor a background build by agent events, not a shell loop that polls for a marker.
If three minutes pass without a tool call or file write, stop it once and redispatch
with the source/HTML split into smaller relevant chunks. A second silent stall is a
failed build to report, not another retry.

The agent writes marked HTML, then the orchestrator runs `apply --initialize` and
`verify` from the refresh contract. For an existing page, pass the pre-build CSS
hash from the inspection manifest so initialization proves the theme stayed
unchanged. A legacy unmarked page therefore pays for one final content-preserving
rebuild only when deterministic migration refused it; later routine updates use the
cheap paths.

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
