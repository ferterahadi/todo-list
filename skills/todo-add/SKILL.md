---
name: todo-add
description: Use when the user invokes /todo-add, says "add a new project", "create a project for X", "start tracking X", or describes a new feature/initiative to track. Scaffolds the project folder + index.md row; the step before /todo-plan.
---

# Project Add Skill

You scaffold a new project in a hub repo and register it in `index.md`. This is the entry point that runs *before* `todo-plan`: it creates the project folder and the index row, leaving the plan content empty for `todo-plan` to fill in. Keep this skill focused on scaffolding — do not write plan content, edit tasks, or execute anything.

This is light, mechanical work. Use the **fast** tier from
[`../model-routing/SKILL.md`](../model-routing/SKILL.md) when dispatching is available; otherwise
run it inline.

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Resolve **every** path against this absolute root — `index.md`, the new project folder under `projects/work/` or `projects/self-initiative/`, its `plan.md`/`tasks.md`/`research/`/`artifacts/` — regardless of the current working directory. This skill may be invoked from another repo; never assume cwd is the hub. Pass this absolute root to the scaffolding subagent so it writes there, not into the cwd. (Same convention as `todo-refer`.)

## How the user invokes this

```
/todo-add rabbitmq dead-letter queue support
/todo-add migrate the auth service to OIDC
/todo-add                                     ← no description: ask what the project is
```

The argument is a free-text feature/project description, not a short-name. You derive the short-name from it.

## Step 1 — Derive a short-name

Turn the feature description into a kebab-case slug suitable for a folder name and the `index.md` short-name column:

- lowercase, words joined by hyphens (e.g. `rabbitmq dead-letter queue support` → `rabbitmq-dlq-support`)
- keep it concise but recognizable — drop filler words ("the", "a", "support for"), keep the distinguishing terms
- prefix with a relevant subsystem if it clarifies (matching the existing naming style in `index.md`, e.g. `api-`, `web-`, `queue-`)

Show the derived short-name to the user and let them override it:

> "I'll call this project `rabbitmq-dlq-support`. Want a different short-name?"

If the user gave no description at all, ask what the project is before deriving anything.

## Step 2 — Ask work vs self-initiative

Always ask — classification isn't reliably inferable:

> "Is this a **work** or **self-initiative** project?"

This decides whether the folder goes under `projects/work/` or `projects/self-initiative/`, and which table in `index.md` gets the new row (`## Work` or `## Self-initiative`).

## Step 3 — Check for collisions

Read `$TODO_HUB/index.md`. If the chosen short-name already exists in either section:

- Stop. Do not overwrite or scaffold over it.
- Point the user at the existing project and its current status, and suggest either picking a different short-name or running `/todo-plan <existing-name>` / `/todo-update-state <existing-name>` if they meant the existing one.

Also check that the target folder `projects/<work|self-initiative>/<short-name>/` doesn't already exist on disk — if it does, treat it as a collision the same way.

## Step 4 — Scaffold the folder

Create `projects/<work|self-initiative>/<short-name>/` with:

- `plan.md` — copied from `templates/plan.md`, with the `[Name]` placeholder replaced by a human-readable title derived from the description (e.g. "RabbitMQ Dead-Letter Queue Support"). Leave the rest of the template structure intact for `todo-plan` to fill.
- `tasks.md` — copied from `templates/tasks.md`, with the `[Project Name]` placeholder replaced by the same title. Leave the placeholder tasks for `todo-plan` to replace.
- `research/` directory with a `.gitkeep` so the empty directory is tracked by git.
- `artifacts/` directory containing `README.md` — copied from `templates/artifacts-README.md`, with the title placeholder replaced by the same human-readable title. This is the artifact manifest (backtrack hub); it seeds the folder so no `.gitkeep` is needed there.

Read the templates fresh from `templates/` rather than hardcoding their contents — they may have changed.

## Step 5 — Register in index.md

Add a row to the correct section table (`## Work` or `## Self-initiative`) in `index.md`. The tables have **nine** columns — include them all:

| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |
|---|---|---|---|---|---|---|---|---|
| `<short-name>` | `projects/<work\|self-initiative>/<short-name>` | `-` | `planning` | `<today>` | `-` | `-` | `-` | `-` |

- `path` is the project folder path relative to the hub root.
- `repo` stays `-` — the local codebase path is confirmed later during `/todo-plan`.
- `status` is `planning` — the plan isn't filled in yet.
- `started` is today's date (`YYYY-MM-DD`) — the lowest-tier provisional stamp in the
  `in-progress` > `ready` > `planning` > `completed` fallback chain (`todo-update-state`
  Step 3.5). It gets overwritten by a `ready` or `in-progress` flip later; this is just the
  earliest signal available. `completed` stays `-`.
- `elapsed (days)` stays `-` — computed once the project reaches `done` (`completed −
  started` in whole days).
- `infographic` stays `-` — `/todo-infographic` fills it after the plan exists.
- `related` — if the user's description names or clearly implies another tracked project (e.g. "the v2 of X", "follow-up to Y", "depends on Z"), look it up in `index.md` and set this to its short-name(s), comma-separated. Otherwise leave `-`; the user or a later edit can fill it in once a link becomes obvious. Never guess a relation from naming similarity alone — only set it from an explicit statement.

Append the row to the bottom of the appropriate table. Don't reorder or touch other rows.

## Step 6 — Confirm and hand off

Report plainly what was created: the folder path, the files scaffolded, and the new `index.md` row. Then hand off to planning:

> "Created `projects/work/rabbitmq-dlq-support/` and registered it in index.md as `planning`. Run `/todo-plan rabbitmq-dlq-support` to fill in the plan and tasks."

Stop there. Do not start planning or executing — those are separate skills (`todo-plan`, `todo-execute`).
