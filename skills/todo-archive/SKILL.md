---
name: todo-archive
description: Use when the user invokes /todo-archive, says "compact tasks.md", "archive this project", "clean up the hub", "tidy the index", "this tasks file is huge", or a SessionStart archive-candidate report appears. Losslessly moves completed revision detail to anchored journal entries, leaves direct tombstones, and moves completed project rows from active index.md to cold archive.md.
---

# Project Archive Skill

Keep repeatedly read files small without deleting history:

1. Move completed `## Revisions` detail from `tasks.md` to
   `artifacts/journal.md`, leaving a direct two-line tombstone.
2. Move completed project rows from active `index.md` to cold `archive.md`.

Never move ordinary task checkboxes, project folders, `plan.md`, `research/`, or project
code. This is mechanical work with strict byte-preservation rules. Decide scope and
verify it yourself; delegate only the approved moves to a **fast**-tier subagent using
[`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md).

## Hub location

Resolve every path against `$TODO_HUB` (default `~/todo`) regardless of the current
working directory. `index.md` is active-only; `archive.md` is completed-project cold
storage. Project-relative paths remain unchanged in both registries.

## Invocation

```text
/todo-archive                     scan the whole hub and propose a sweep
/todo-archive api-token-rotation  compact one project
/todo-archive registry            retire completed project rows only
```

Plain language counts: "this tasks file is enormous", "clean up my done projects".

## Step 1 — Run the deterministic report

Run the bundled read-only helper, resolving the script relative to this `SKILL.md`:

```bash
bash <todo-archive-skill-dir>/scripts/archive-report.sh audit "$TODO_HUB"
bash <todo-archive-skill-dir>/scripts/archive-report.sh audit "$TODO_HUB" api-token-rotation
bash <todo-archive-skill-dir>/scripts/archive-report.sh audit "$TODO_HUB" registry
```

The same helper powers the plugin's SessionStart report. Its compact output identifies:

- completed revision entries still carrying detail, matched case-insensitively on a
  heading tag that starts with `[done`;
- tombstones needing a direct-link or stable-anchor repair;
- broken tombstones whose journal target is missing or ambiguous;
- duplicate short-names across active and archived registries;
- state conflicts such as archived non-`done` / open-revision rows or active `done`
  rows with an open revision;
- registry rows whose project `tasks.md` is missing;
- `tasks.md` files over 20,480 bytes;
- active `done` rows eligible to move to `archive.md`.

Show the files, byte counts, entry counts, link repairs, broken pointers, and row moves
before editing. A specific-project invocation needs one-line confirmation; a hub-wide
sweep needs the full proposal. Never mutate during this scan.

## Step 2 — Compact completed revisions

For each revision heading whose terminal tag starts with `[done` in any letter case
(`[done]`, `[DONE 2026-07-13]`, `[Done — shipped]`):

1. Append the complete entry—heading plus its revision detail—to a dated section in
   `artifacts/journal.md`. Preserve every entry byte and add one stable anchor immediately
   before it:

   ```markdown
   <a id="revision-r4"></a>
   ### R4 ⟵ Task 5.2 — rotate audit log   [DONE 2026-07-13]
   - Gap: rotate skips audit log
   - Expected: every rotation writes an audit row
   - Actual: only manual rotations logged
   - Fix: moved audit write into RotateService.execute
   - [x] implement + re-verify
   ```

2. Keep the original heading verbatim in `tasks.md` and replace only its detail with the
   direct tombstone:

   ```markdown
   ### R4 ⟵ Task 5.2 — rotate audit log   [DONE 2026-07-13]
   - archived → [journal:R4](artifacts/journal.md#revision-r4) (2026-07-13)
   ```

The anchor is lowercase `revision-r<n>` even when the heading uses uppercase or a
suffixed identifier such as `R72b`. Revision numbering is permanent and never reused.

### Repair legacy tombstones

For every `link_repairs` candidate:

1. Find exactly one matching `## R<n>` or `### R<n>` journal heading, using an exact
   boundary so `R1` cannot match `R10`.
2. Insert `<a id="revision-r<n>"></a>` immediately before it if absent.
3. Replace only the old plain `archived → artifacts/journal.md` line with the canonical
   direct link above.

If the journal contains zero or multiple exact headings, classify it as broken and stop
for that entry. Never guess or create a link to a nearby aggregate section.

### Safety rules

- Never archive an `[open]` entry. Leave `[superseded …]`, `[fixed …]`, and every other
  non-done tag untouched.
- Any entry already containing an `archived →` pointer is tombstoned even when unrelated
  comments or sections follow it. Repair its link if needed; never append its detail again.
- If an interrupted run left both task detail and a journal copy, compare the exact entry.
  Reuse the existing copy only when it matches; otherwise report the conflict.
- Move only the revision's heading and detail bullets. Preserve adjacent blockquotes,
  comments, section headings, and every line outside the entry byte-for-byte.
- Ordinary checkboxes under `## Tasks` or `## Phase …` never move.

## Step 3 — Retire completed projects

Ensure `$TODO_HUB/archive.md` exists with the same section tables and nine-column schema
as `index.md`. For each active row whose status is `done` and whose `tasks.md` has no
case-insensitive `[open]` revision:

Move the row verbatim to the same section in `archive.md`, creating that section with
the same table header when necessary. Apply the destination insert and source removal
as one atomic two-file edit. If the editing surface cannot do that, append and verify
the destination first, then remove the source; a temporary duplicate is recoverable,
while a row missing from both registries is not.

Preserve custom section names. Before moving, search both registries for the short-name;
duplicates are corruption, so stop instead of choosing one. Do not move or rename the
project folder.

Repair registry conflicts before retirement:

- Archived status other than `done`, or a case-insensitive terminal `[open…]`
  revision → move the row back to its original `index.md` section, set
  `in-progress`, and clear `completed` / `elapsed (days)` atomically.
- Active `done` row with an open revision → keep it active, set `in-progress`, and
  clear the completion fields.
- Missing `tasks.md` or duplicate registry names → stop for that project; do not move
  the row or infer its state.

`/todo-archive registry` uses the unfiltered deterministic audit above, then limits
edits to rows whose `registry_action` is not `-`; it does not look for a project named
`registry`.

For a legacy `## Archive` table still inside `index.md`, infer `Work` only from a
`projects/work/` path and `Self-initiative` only from `projects/self-initiative/`.
Move unknown paths under `## Other` and flag them for confirmation before any later
reopen.

This skill may repair a stale archived row reported by the audit. For a user-requested
status change away from `done`, `todo-state` owns the same atomic reverse move.

## Step 4 — Verify and report

Re-run the deterministic report. Broken tombstones and duplicate registry rows must be
zero; repaired or moved items must no longer appear as candidates.

Report one compact row per project:

```text
project             tasks.md        revisions → journal   links   registry
api-token-rotation  96KB → 11KB     12                    2       -
queue-migration     -                -                     -       index → archive
```

Include total bytes removed from `tasks.md`. `archive.md` is a cold file: default list,
triage, sync, and execution scans read only `index.md`; exact historical lookup falls back
to `archive.md`.
