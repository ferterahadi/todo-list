---
name: todo-archive
description: Use when the user invokes /todo-archive, says "compact tasks.md", "archive this project", "clean up the hub", "tidy the index", "this tasks file is huge", or when a skill notices a tasks.md over ~20KB or done projects cluttering the index. Moves closed detail to artifacts/journal.md and retires done projects to an Archive section — lossless, never deletes.
---

# Project Archive Skill

You keep the hub's hot files small. `tasks.md` is read by six skills and `index.md` by
all of them — closed history must not tax every future read. This skill owns the two
housekeeping sweeps other skills only *offer*:

1. **Compact a project's `tasks.md`** — move `[done]` revision detail to
   `artifacts/journal.md`, leaving two-line tombstones.
2. **Retire done projects** — move their `index.md` rows to an `## Archive` section so
   the active tables stay short.

Everything is **lossless**: detail moves, nothing is deleted. Never touch `plan.md`,
`research/`, or project code.

This is mechanical work with strict byte-preservation rules. Decide what gets archived
and verify the result yourself; when dispatching is available, delegate only the moves
to a **fast**-tier subagent using [`../model-routing.md`](../model-routing.md).

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Resolve **every** path against this absolute root — `index.md`, each project's `path`, `tasks.md`, `artifacts/` — regardless of the current working directory. This skill may be invoked from another repo; never assume cwd is the hub. (Same convention as `todo-refer`.)

## How the user invokes this

```
/todo-archive                     ← scan the whole hub, propose a sweep
/todo-archive api-token-rotation  ← compact one project's tasks.md
/todo-archive index               ← retire done projects from index.md only
```

Plain language counts too: "this tasks file is enormous", "clean up my done projects".

## Step 1 — Scan and propose

Read `$TODO_HUB/index.md`. For each in-scope project, check:

- `tasks.md` size (`wc -c`) — flag anything **> ~20KB**.
- Count of `[done]`-tagged revision entries still carrying full detail (heading plus 2+
  detail bullets, i.e. not yet a tombstone):
  ```bash
  grep -nE '^### R[0-9]+.*\[done' tasks.md    # done headings (prefix match — see rule below)
  ```
- `done`-status rows sitting in the active section tables.

Show the user what you found and what you'd do (files, byte counts, row moves) **before
editing anything**. Nothing here is destructive, but the user should see the sweep's
scope. If they invoked the skill on a specific project, a one-line confirmation is
enough; a hub-wide sweep gets the full proposal.

## Step 2 — Compact tasks.md (per project)

Apply the archival rule (shared with `todo-revise` — this is the batch form). For each
revision entry whose heading tag **starts with** `[done` — match `\[done` as a prefix,
not `\[done\]` literally, or annotated entries like `[done — shipped via Phases 7–14]`
silently escape the sweep:

1. **Append the full entry** (heading + all detail bullets) to `artifacts/journal.md`
   under a dated section, creating the file if needed:
   ```markdown
   ## R4 ⟵ Task 5.2 — rotate audit log   [done 2026-07-13]
   - Gap: rotate skips audit log
   - Expected: every rotation writes an audit row
   - Actual: only manual rotations logged
   - Fix: moved audit write into RotateService.execute
   - [x] implement + re-verify
   ```
2. **Collapse the entry in `tasks.md`** to a two-line tombstone — heading stays verbatim
   (numbering must never be reused, and `todo-verify`'s idempotency scan matches on it):
   ```markdown
   ### R4 ⟵ Task 5.2 — rotate audit log        [done]
   - archived → artifacts/journal.md (2026-07-13)
   ```

Hard rules:

- **Never archive an `[open]` entry.** `[superseded …]` and other non-open/non-done tags
  are left untouched.
- Entries already tombstoned (single `archived →` bullet) are skipped — the sweep is
  idempotent.
- Task checkboxes under `## Tasks` / `## Phase …` are NEVER moved or collapsed — only
  `## Revisions` entry *detail* is archived. The checklist is the project's live state.
- Every line outside the collapsed entries is reproduced byte-for-byte — remind the
  edit subagent of this explicitly.

## Step 3 — Retire done projects from index.md

For each row with status `done` in an active section table (`## Work`,
`## Self-initiative`, …), **and no open Revisions** (check its `tasks.md` for
`### R<n> … [open]` — a done project with open revisions isn't done; flag it and skip,
suggesting `/todo-revise`):

- Move the row, verbatim, to an `## Archive` section table at the bottom of `index.md` —
  same columns, created from the same header if it doesn't exist yet.
- Do NOT move or rename the project folder — the `path` column stays valid, and every
  skill can still resolve the project. Archive is an index-level shelf, not a deletion.

Skills that iterate "every project" (`todo-list`, `todo-triage`) naturally skip the
Archive section because they scope to active statuses; `todo-refer` and
`/todo-update-state` still resolve archived rows by short-name, so nothing breaks.

## Step 4 — Report

Per project: bytes before → after for `tasks.md`, entries archived, rows moved. One
compact table, then a one-line total, e.g.:

```
| project | tasks.md | entries → journal | index row |
|---|---|---|---|
| api-token-rotation | 96KB → 11KB | 12 | — |
| queue-migration | — | — | → Archive |

Sweep complete — 85KB out of the hot path, nothing deleted.
```

## Notes
- **Reversible by construction**: journal.md holds the full entries; a tombstone plus its
  journal section reconstructs the original. Index rows move, never vanish.
- If the user asks to archive a project that isn't `done`, don't — explain the status
  gate and point at `/todo-update-state` (if it really is finished) or `/todo-revise`
  (if open revisions are the blocker).
- Other skills (`todo-revise` Step 6, `todo-update-state` housekeeping) archive
  single entries as they close them; this skill is the batch sweep they point at when
  backlog has accumulated.
