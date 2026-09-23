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

**Hook-triggered runs.** The Stop hook applies fast refreshes itself and blocks only
for `semantic-refresh`, naming those projects. A hook-triggered run handles only the
named projects, never starts a full build or legacy migration, and instead reports
the explicit command `/todo-infographic <short-name>` for any project that needs one.

## 1. Inspect first

Finish every in-scope `plan.md` and `tasks.md` edit first. Run `inspect` inline,
**without** a footprint; `<skill-dir>` is this skill's directory and `--html`
defaults to `<project-dir>/artifacts/infographic.html`:

```bash
python3 <skill-dir>/scripts/refresh-infographic.py inspect <project-dir> \
  --date <YYYY-MM-DD> --status <registry-status> --output <tmp>/manifest.json
```

The manifest freezes both source hashes. If either source changes afterward, discard
any patch and inspect again. Route on its `mode`:

| Mode | Next step |
|---|---|
| `stub` | Report the unfilled Goal/Scope (`reasons`) and stop; write nothing |
| `fresh` | Nothing to do |
| `fast-refresh` | Step 2 |
| `semantic-refresh` | Step 3 |
| `legacy-migration` | Step 4 (explicit invocation only) |
| `full-build` | Step 5 (explicit invocation only) |

## 2. Fast refresh (inline, no model)

Checkbox state, status, date, or an unrendered plan section (Relationships,
References, Repo, Verification) changed. Run both commands inline; read no
reference and start no subagent:

```bash
python3 <skill-dir>/scripts/refresh-infographic.py apply <project-dir> \
  --date <YYYY-MM-DD> --status <registry-status>
python3 <skill-dir>/scripts/refresh-infographic.py verify <project-dir>
```

## 3. Semantic refresh (inline patch, no subagent)

Rendered prose may be stale. Read the semantic section of
[references/refresh-contract.md](references/refresh-contract.md), then write the
patch yourself from the manifest's `changed` sections and `bindings.content`. Do not
read the full HTML, unchanged sections, or design skills.

1. Changed prose that fits an existing content leaf: write plain text for those keys
   as `{"content": {...}}` and run `apply --content-patch`.
2. Changed prose with no leaf: extract the smallest matching block with `fragment`,
   write a bounded exact patch, and run `apply --exact-patch`.
3. A change that affects no visible prose: run `apply --confirm-no-content-change`.
4. Run `verify`.

A new card, section, list row, diagram node, rich markup, or absent binding is a
`full-build`, not a patch.

## 4. Legacy migration

Read [references/refresh-contract.md](references/refresh-contract.md). The helper
recognizes unambiguous task totals, phase meters, generated date, and decision cards,
then inserts markers without serializing the page. It preserves every `<style>` byte
and refuses ambiguous structure; a refusal already routed `inspect` to `full-build`.

Legacy HTML has no source baseline, so absence of a structural mismatch does not prove
its prose is current. After a bounded review finds no stale content, run `migrate
--confirm-content-current`. When stale content must change, write the fix inline:

1. Extract only the changed source block and the smallest matching HTML fragment with
   `fragment`. Never load the full HTML, unchanged phases, or design skills.
2. Write the exact-patch JSON from the refresh contract: at most eight exact fragments
   and 64 KiB total, never a rewritten page.
3. Run `migrate --exact-patch`, then `verify`. Migration rejects a stale inspection
   manifest, a non-unique replacement, a source edit made after inspection, CSS drift,
   missing bindings, or stale decision structure.

Never weaken the helper's proof checks or guess selectors.

## 5. Full design path

**Gather the file footprint** only here, or when the user explicitly asks to refresh
it. From the target repo:

- Feature branch: diff merge-base with the default branch, then add uncommitted and
  untracked files.
- Default branch: use attributable uncommitted files or an identifiable merged
  range/PR from project evidence.
- Missing repo or no attributable changes: no footprint.

Write the flat status/path/optional-task-reason list to a temporary JSON file and
rerun `inspect --footprint-json <file>`. Reasons must come from a clear task match;
never invent them. Never paste a large footprint into a subagent prompt.

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
design-critique/frontend-design pass. Spawn one agent per project and parallelize
only when the user explicitly asked for several projects. Dispatch in the background
when the host supports it, so the orchestrator stays responsive.

Monitor a background build by agent events, not a shell loop that polls for a marker.
If three minutes pass without a tool call or file write, stop it once and redispatch
with the source/HTML split into smaller relevant chunks. A second silent stall is a
failed build to report, not another retry.

The agent writes marked HTML, then the orchestrator runs `apply --initialize` and
`verify` from the refresh contract. For an existing page, pass the pre-build CSS
hash from the inspection manifest so initialization proves the theme stayed
unchanged.

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
the mode used, and any stubs or deferred full builds with their explicit command.
Link the HTML; do not paste it.
