# todo-* skills

The `/todo-*` skills that drive the hub. They ship inside the **todo-list plugin** and are
auto-discovered by Claude Code on install — see the [root README](../README.md) for how to
install the plugin. When invoked as slash commands they're namespaced by the plugin, e.g.
`/todo-list:todo-plan`; the natural-language triggers in each skill's `description` fire
without the prefix.

| Skill | Purpose |
|-------|---------|
| `todo-list` | Show the project index — at-a-glance view of all tracked projects, grouped by status (read-only) (dispatched to Haiku, latest) |
| `todo-triage` | Tabulate what's left (open tasks + open Revisions) across projects and recommend model · effort · skill pairing per item — Fable 5 / Opus / Sonnet / Haiku × low/med/high × installed skills like code-review, dataviz, design critique (read-only; gathering dispatched to Haiku, latest; routing judgment inline) |
| `todo-refer` | Load a project's `plan.md`+`tasks.md` into the current session as grounding context, plus a one-line goal digest for each project listed in its `related` column — cross-repo, read-only (run before `/code-review` etc. from another codebase) |
| `todo-add` | Scaffold a new project folder + register it in `index.md` (scaffolding delegated to Haiku, latest) |
| `todo-plan` | Write `plan.md` and `tasks.md` for a project |
| `todo-execute` | Work through `tasks.md`, write outputs to `artifacts/` |
| `todo-execute-parallel` | Fan file-disjoint tasks out to parallel agents in git worktrees of the target repo (no model pin — both implement and review waves inherit the session model), then land PRs via a serial merge queue |
| `todo-update-state` | Mark tasks/projects done, move status (edits delegated to Haiku, latest) |
| `todo-verify` | The "check" gate: drive a record-only verification run, tick tasks / flip status on green, open Revisions entries on failures or coverage gaps (pinned to Sonnet, latest, high reasoning) |
| `todo-revise` | Gap-driven rework: review done items, capture feedback per item, plan + run fixes, verify |
| `todo-learn` | Capture a correction as a durable rule in the worked-on repo's own `.claude/skills/<topic>/` (pinned to Sonnet, latest, high reasoning) |
| `todo-sort` | Reorder `index.md` rows by task completion, most-done first (runs on Haiku, latest) |
| `todo-infographic` | Turn a plan into a one-page HTML infographic, fresh theme each time (+ staleness hook). Generation runs on Sonnet, latest, high reasoning |
| `todo-push` | General-purpose git shipping workflow (any repo): branch off main, commit, push, PR, merge, land back on main (pinned to Haiku, latest) |

Status lifecycle: `planning → ready → in-progress → done`. The `plan → do → check → revise`
loop is `todo-plan` → `todo-execute` → `todo-verify` → `todo-revise`.

## Install

Install the plugin (see the [root README](../README.md)). That auto-discovers every
`/todo-*` skill — no symlinking, no copying, no per-skill setup.

## Bundled hooks (auto-registered)

The plugin ships two hooks in [`../hooks/`](../hooks/), registered automatically via
`hooks/hooks.json` on install:

- **`bootstrap-hub.sh`** (SessionStart) — creates the hub at `$TODO_HUB` (default `~/todo`)
  from the plugin's `seed/` on first run; silent thereafter.
- **`infographic-staleness.sh`** (Stop) — when a `ready`/`in-progress` project has a
  missing or stale `artifacts/infographic.html`, nudges Claude to regenerate it via
  `todo-infographic` before the turn ends. It self-scopes: it only acts when the current
  project has an `index.md` (i.e. you're working in the hub), so it's quiet everywhere else.

## Editing a skill

These files are the source. Edit them here and reinstall/refresh the plugin to pick up
changes. See [CONTRIBUTING.md](../CONTRIBUTING.md) for the local-development loop.
