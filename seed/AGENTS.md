# Agent Instructions

This repo is a central execution hub. Plans live here. You execute against them.

## Repo Structure

```
projects/
  work/            — work projects
  self-initiative/ — self-driven / research projects
templates/     — plan.md and tasks.md templates for new projects
index.md       — central registry: resolves short-name → path / repo / status / infographic
skills/        — the /todo-* skills that drive the workflow
```

## Entry Point

`index.md` is the registry. Skills resolve a short project name to its path, target repo,
and status. Keep `tasks.md` checkboxes and the `index.md` status column in sync.

The hub root is the `TODO_HUB` environment variable (default `~/todo`). Resolve every hub
path against it — skills may be invoked from inside another repo, so never assume the
current working directory is the hub.

Each project folder contains:
- `plan.md` — goal, context, constraints, key decisions
- `tasks.md` — checklist you execute against
- `research/` — raw notes and findings
- `artifacts/` — your outputs go here

## Artifact conventions

Keep `artifacts/` navigable — a cold session should reach any output from one place.

- **Naming.** Dated outputs are `YYYY-MM-DD-<kind>-<slug>.md`, `<kind>` ∈ `analysis · finding · handoff · session · design`. Living docs appended over time keep stable names: `journal.md`, `blockers.md`, `infographic.html` (plus any project-specific source-of-truth doc).
- **Header.** Every artifact opens with a one-line blockquote that backlinks its origin: `> **Kind:** … · **Source:** tasks.md#R7 (or a Phase) · **Date:** YYYY-MM-DD · **Index:** [README.md](README.md)`.
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
- `/todo-update-state` flip status/checkboxes · `/todo-list` overview (`sort` reorders by completion)
- `/todo-verify` reconcile the verification result · `/todo-revise` fix gaps
- `/todo-review` review a diff against the plan · `/todo-resume` pick up where a project left off
- `/todo-sync` reconcile index status vs repo reality · `/todo-archive` compact tasks.md + retire done projects
- `/todo-triage` tabulate open tasks/revisions across projects + recommend a model tier per item
- `/todo-infographic`, `/todo-refer`, `/todo-learn`

Status lifecycle: planning → ready → in-progress → done

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
