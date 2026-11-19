---
name: todo-add
description: Use when the user invokes /todo-add, says "add a new project", "create a project for X", "start tracking X", or describes a new feature/initiative to track. Scaffolds the project folder + index.md row; the step before /todo-plan.
---

# Project Add Skill

You scaffold a new project in a hub repo and register it in `index.md`. This is the entry point that runs *before* `todo-plan`: it creates the project folder and the index row, leaving the plan content empty for `todo-plan` to fill in. Keep this skill focused on scaffolding — do not write plan content, edit tasks, or execute anything.

This is light, mechanical work — a few file writes. Do it inline on the current session;
dispatching it to a subagent costs more than the work.

## Hub location

Resolve every hub path against `$TODO_HUB` — including the new project folder under
`projects/work/` or `projects/self-initiative/` — never the cwd. See
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Hub location.

## How the user invokes this

```
/todo-add rabbitmq dead-letter queue support
/todo-add migrate the auth service to OIDC
/todo-add                                     ← no description: ask what the project is
```

The argument is a free-text request and can include an explicit project name, category, repo choice, and a request to plan.

## Step 1 — Resolve the name and category

Use the supplied short-name when it is valid. If it is invalid, ask for a valid name. When no name was given, turn the feature description into a kebab-case slug suitable for a folder name and the `index.md` short-name column:

- lowercase, words joined by hyphens (e.g. `rabbitmq dead-letter queue support` → `rabbitmq-dlq-support`)
- keep it concise but recognizable — drop filler words ("the", "a", "support for"), keep the distinguishing terms
- prefix with a relevant subsystem if it clarifies (matching the existing naming style in `index.md`, e.g. `api-`, `web-`, `queue-`)

Use an explicit **work** or **self-initiative** classification. If it is missing,
ask which category to use, naming the proposed slug in the same prompt. Validate the
slug against `todo-conventions` § Placeholder safety before using it as a path.
The category determines both the folder and the registry section.

If the user gave no description at all, ask what the project is before deriving anything.

## Step 2 — Check for collisions

Read `$TODO_HUB/index.md`, then `$TODO_HUB/archive.md`. If the chosen short-name already
exists in either registry or any section:

- Stop. Do not overwrite or scaffold over it.
- Point the user at the existing project, its active/archived location, and status. Suggest
  either a different short-name or `/todo-sync <existing-name> in-progress` to
  reopen an archived project; never reuse an archived identity.

Also check that the target folder `projects/<work|self-initiative>/<short-name>/` doesn't already exist on disk — if it does, treat it as a collision the same way.

## Step 3 — Scaffold the folder

Create `projects/<work|self-initiative>/<short-name>/` with:

- `plan.md` — copied from `templates/plan.md`, with the `[Name]` placeholder replaced by a human-readable title derived from the description (e.g. "RabbitMQ Dead-Letter Queue Support"). Under `## Repo`, record an explicit “no repo” as `none — hub-only`, or a supplied local path for `todo-plan` to check. Leave an unknown repo as a placeholder. Preserve the rest of the template apart from the explicit relationship rule below.
- `tasks.md` — copied from `templates/tasks.md`, with the `[Project Name]` placeholder replaced by the same title. Leave the placeholder tasks for `todo-plan` to replace.
- `research/` directory with a `.gitkeep` so the empty directory is tracked by git.
- `artifacts/` directory containing `README.md` — copied from `templates/artifacts-README.md`, with the title placeholder replaced by the same human-readable title. This is the artifact manifest (backtrack hub); it seeds the folder so no `.gitkeep` is needed there.

Read the templates fresh from `templates/` rather than hardcoding their contents — they
may have changed. Existing hubs may carry a pre-graph `templates/plan.md`; after copying,
insert the canonical empty `## Relationships` table before `## Verification` (or
`## References` when Verification is absent) if the section is missing. Do not rewrite
any other template content.

If the user's description explicitly names an exact tracked project and relationship,
seed one canonical row in `plan.md` `## Relationships`:

- “depends on X” / “requires X” → `depends-on`
- “replaces X” / “v2 of X” → `supersedes`
- “related to X” / “follow-up to X” → `related-to`

Resolve X active-first, then archive; use the request's own clause as the reason. Never
infer an edge from naming similarity. If the wording is ambiguous, leave the table empty
for `/todo-plan` discovery rather than guessing.

## Step 4 — Register in index.md

Add a row to the correct section table (`## Work` or `## Self-initiative`) in `index.md`. The tables have **nine** columns — include them all:

| short-name | path | repo | status | started | completed | elapsed (days) | infographic | related |
|---|---|---|---|---|---|---|---|---|
| <short-name> | projects/<work\|self-initiative>/<short-name> | - | planning | <today> | - | - | - | - |

- `path` is the project folder path relative to the hub root.
- `repo` stays `-` — the local codebase path is confirmed later during `/todo-plan`.
- `status` is `planning` — the plan isn't filled in yet.
- `started` is today's date (`YYYY-MM-DD`) — the lowest-tier provisional stamp, overwritten
  by a later `ready` or `in-progress` flip. `completed` and `elapsed (days)` stay `-`. See
  `todo-sync` § Date stamping for the full tier chain.
- `infographic` stays `-` — `/todo-infographic` fills it after the plan exists.
- `related` stays `-` for new projects. It is a legacy context-only field retained for
  existing hubs; canonical typed relationships now live in `plan.md`.

Append the row to the bottom of the appropriate table, with bare cells like the rows
already there — no backticks. Don't reorder or touch other rows.

If Step 3 seeded a relationship, validate the now-registered source with:

```bash
python3 <todo-graph-skill-dir>/scripts/graph-report.py can-link \
  "$TODO_HUB" "<source>" "<relation>" "<target>"
```

**Validate before running it** —
[`../todo-conventions/SKILL.md`](../todo-conventions/SKILL.md) § Placeholder safety.
`<source>` and `<target>` come from free text the user typed or a registry cell; on a
failure, stop and report that value.

`EXISTS` confirms that the stored row is valid. On `ERROR`, remove only the seeded
relationship row, keep the new project registered as `planning`, and report why the edge
was not retained. Never leave a new cycle or ambiguous target in the hub.

## Step 5 — Confirm and offer to plan

Report the folder and registry row. When the request includes planning, continue
straight into `todo-plan` with the resolved short-name, category, supplied repo path
or explicit “no repo”, stated goal, and any seeded relationships. For a scaffold-only
request, offer `/todo-plan <short-name>` as the next step.
