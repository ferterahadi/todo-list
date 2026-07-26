---
name: todo-refer
description: Use when the user invokes /todo-refer, says "refer to project X", "pull in the context for X", "give me the plan for X to review against", asks what happened in a completed revision such as R4, or wants a hub project's plan/tasks loaded before another command. Read-only, active-or-archived, and cross-repo.
---

# Project Refer Skill

Load a hub project's context into the current session so a follow-on command is grounded
in its goal, decisions, and current work. This is read-only and cross-repo: always reach
the hub by absolute path.

Run inline on at least the **balanced** tier from
[`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md).

## Hub location and registry contract

The hub root is `$TODO_HUB` (default `~/todo`):

- `index.md` contains active projects and is the default hot path.
- `archive.md` contains completed projects and is read only for an explicit archive view
  or when an exact short-name is absent from `index.md`.

Never use a same-named `index.md` from the current code repo.

## Invocation

```text
/todo-refer service-auth
/todo-refer service-auth R4
/todo-refer
```

## Step 1 — Resolve the project

1. Run bounded exact-name checks against both registry tables; do not load either file
   into model context.
2. If both match, stop and report registry corruption.
3. Otherwise select `index.md` first; select `archive.md` only on an active miss.
4. If exact lookup fails, fuzzy-match names from both files and ask for confirmation.
5. With no name, list active names from `index.md` only and ask which project.

Record the owning registry, section, path, repo, status, and related names. Resolve the
project folder as `$TODO_HUB/<path>`.

For an archived row, always run Step 2's bounded context helper—even on the
revision-only fast path. Any `REVISION` row means the registry is stale. Keep this
read-only, flag the mismatch, and direct the user to
`/todo-update-state <short-name> in-progress`.

## Step 2 — Read current context economically

For a revision-only question such as "what happened in R4?", take the fast path: read
only the `## Goal` paragraph from `plan.md`, skip current task counts and related-project
expansion, then jump to Step 3. A request that also needs the project as grounding for
another command uses the full path below.

Read `plan.md` in full because it is the grounding. Extract current state with the
bundled helper rather than loading `tasks.md`:

```bash
bash <todo-archive-skill-dir>/scripts/archive-report.sh context \
  "$TODO_HUB" "<project-path>"
```

`TASK` and `REVISION` rows are capped at 20 each. `SUMMARY` always carries complete
done / total / open-task / open-revision counts. The parser strips HTML comments,
ignores fenced examples and non-task Notes/Context sections, and reads only visible
current state.

Read all of `tasks.md` only when it is below about 15 kilobytes or the follow-on command
explicitly needs completed-task detail.

## Step 3 — Resolve requested revision history

When the user names a revision ID or explicitly asks about revision history, read only
that entry. Prefer the bundled read-only helper when `todo-archive` is installed:

```bash
bash <todo-archive-skill-dir>/scripts/archive-report.sh lookup \
  "$TODO_HUB" "<project-path>" "R4"
```

The helper returns a live or not-yet-tombstoned entry directly from `tasks.md`. For a
tombstone it resolves the stable `<a id="revision-r4"></a>` journal anchor and stops at
the next entry. It also supports legacy exact `## R4` / `### R4` headings, with a strict
boundary so `R1` never matches `R10`.

If the helper is unavailable:

1. Read the named revision block in `tasks.md`.
2. Follow its `artifacts/journal.md#revision-r<n>` link.
3. Read from that exact anchor until the next revision anchor or heading.
4. For a legacy unlinked pointer, search `journal.md` for exactly one case-insensitive
   `^#{2,3} R<n>(space-or-end)` heading and read only that block.

Zero or multiple journal matches are a broken tombstone. Report the ambiguity and do not
guess from nearby dated or aggregate sections.

## Step 4 — Load one bounded graph neighborhood

Skip this step on the revision-only fast path. Otherwise run:

```bash
python3 <todo-graph-skill-dir>/scripts/graph-report.py context \
  "$TODO_HUB" "<short-name>"
```

Use its exact one-hop `depends-on`, derived blocker, `related-to`, `supersedes`, and
legacy-context rows. Read only each named neighbor's `## Goal` paragraph when the
follow-on request needs that context; never load neighboring tasks or journals.

Graph issues are not stale names to skip: surface them and point at `/todo-graph audit`.
If the helper is unavailable, fall back to the owning registry row's legacy `related`
names as non-blocking context only. Never infer a dependency from the fallback.

## Step 5 — Emit the digest

Keep the digest to about 5–8 lines plus related projects:

```text
Loaded context: service-auth ($TODO_HUB/projects/work/service-auth)
Registry: active
Goal: <one line>
Status: in-progress
Open tasks: <first 3–5, then count>
Done: 12/20 tasks
Depends on: token-foundation — <goal> (done, archived)
Context: token-rotation — <goal> (in-progress)
```

When a revision was requested, add its exact heading plus a compact Expected / Actual /
Fix digest from the extracted entry. On the revision-only fast path, that digest plus the
one-line goal and registry state is the whole response. Do not dump unrelated journal
history.

This skill only loads context. End with one next-command nudge; do not run that command
or edit hub files.

## Notes

- Missing files are reported, not scaffolded.
- Artifact bodies remain cold by default. A named revision lookup is the deliberate
  exception; arbitrary artifact requests list filenames unless the user asks for content.
- To change state use `todo-update-state`; to execute use `todo-execute`.
