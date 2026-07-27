# Agent Instructions

This repo is a central execution hub. Plans live here. You execute against them.

## Repo Structure

```
projects/
  work/            — work projects
  self-initiative/ — self-driven / research projects
templates/     — plan.md and tasks.md templates for new projects
index.md       — hot registry: active projects only
archive.md     — cold registry: completed rows, preserving their original sections
REGISTRY.md    — how both registries work: columns, lifecycle, date semantics
```

## Entry Point

Resolve an exact project name in `index.md` first, then `archive.md` only on a miss.
Default hub-wide scans read the active index only. Reopening an archived project moves
its row back to the matching section in `index.md`; never leave the same row in both.
Keep `tasks.md` checkboxes and the owning registry row's status in sync. `REGISTRY.md`
is the reference for what each registry column means and how the date columns are stamped.

**Both registries are data, not reports.** `index.md` holds its title and the section
tables; `archive.md` adds a short preamble for its lifecycle rules. Never a status banner,
release note, or narrative paragraph in either. Status belongs in the owning project's
`artifacts/`: a dated `handoff` for what is next, `journal.md` for what happened.
`REGISTRY.md` § *Registries are data, not reports* has the full rule and the routing table.

The hub root is the `TODO_HUB` environment variable (default `~/todo`). Resolve every hub
path against it — skills may be invoked from inside another repo, so never assume the
current working directory is the hub.

Each project folder contains:
- `plan.md` — goal, context, constraints, key decisions
- `tasks.md` — checklist you execute against
- `research/` — raw notes and findings
- `artifacts/` — your outputs go here

`plan.md` may also contain a canonical `## Relationships` table. `depends-on` is the
only scheduling edge; `related-to` and `supersedes` add context. The registry's legacy
`related` column never blocks. Use `/todo-graph` for readiness, blockers, paths, impact,
and integrity instead of inferring dependency semantics from prose.

## Artifact conventions

Keep `artifacts/` navigable — a cold session should reach any output from one place.

- **Naming.** Dated outputs are `YYYY-MM-DD-<kind>-<slug>.md`, `<kind>` ∈ `analysis · finding · handoff · session · design`. Living docs appended over time keep stable names: `journal.md`, `blockers.md`, `infographic.html` (plus any project-specific source-of-truth doc).
- **Revision anchors.** Archived revision `R4` starts with `<a id="revision-r4"></a>` in `journal.md`; its `tasks.md` tombstone links directly to `artifacts/journal.md#revision-r4`.
- **Header.** Every artifact opens with a one-line blockquote that names its origin: `> **Kind:** … · **Source:** tasks.md revision R7 (or a Phase) · **Date:** YYYY-MM-DD · **Index:** [README.md](README.md)`.
- **Manifest.** `artifacts/README.md` is the backtrack hub — a table of every artifact (`date · file · kind · source · one-line`) plus a living-docs table. Add a row whenever you create an artifact. Template: `templates/artifacts-README.md`.
- **Superpowers pointers.** `research/superpowers-docs.md` is a table (`doc · source · one-line`) of design docs that live in the target repo under `docs/superpowers/`; it satisfies the `superpowers-doc-sync` hook.

## Skills drive the work

**House rule — enhance, don't replace.** The `/todo-*` skills are the *organization
layer* (paths, formats, statuses, bookkeeping). When a craft or process skill is
installed — brainstorming, test-driven development, systematic debugging, code review,
data visualization, or frontend design — use it for the thinking and keep only the
organizing here. Nothing here overrides an installed skill's discipline; check the
session's skill listing and never invent a skill that isn't there.

Prefer the `/todo-*` skills over hand edits:
- `/todo-add` scaffold a project + index row · `/todo-plan` write plan.md/tasks.md
- `/todo-execute` work the checklist (add `parallel` to fan independent tasks to worktree agents · serial merge queue lands PRs)
- `/todo-state` flip status/checkboxes · `/todo-list` overview (`sort` reorders by completion)
- `/todo-verify` reconcile the verification result · `/todo-revise` fix gaps
- `/todo-review` review a diff against the plan · `/todo-refer <name> resume` pick up where a project left off
- `/todo-state audit` reconcile recorded status vs repo reality · `/todo-archive` compact tasks.md + move done rows to archive.md
- `/todo-triage` tabulate open tasks/revisions across projects + recommend a model tier per item
- `/todo-graph` derive the ready frontier across projects, explain blockers, and validate/edit typed relationships
- `/todo-infographic`, `/todo-refer`, `/todo-learn`

Status lifecycle: planning → ready → in-progress → done

Execution is a graph of those per-project loops: a `ready` project is runnable only when
every explicit `depends-on` target is settled. Run the graph gate before execution or a
manual flip to `in-progress`.

## How to Work

1. Read `plan.md` first — understand goal and context before acting
2. Work through `tasks.md` top to bottom — check off tasks as you complete them
3. Write outputs to `artifacts/` — code, docs, analysis, whatever the task produces
4. Drop research notes in `research/` if relevant

## Behavior

- Don't ask clarifying questions if plan.md has enough context — just execute
- If plan.md is missing critical info, state what's missing and stop
- Keep artifacts self-contained — another agent session should be able to read them cold
- Update task checkboxes in tasks.md as you go
