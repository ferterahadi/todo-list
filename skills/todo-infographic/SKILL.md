---
name: todo-infographic
description: Use when the user invokes /todo-infographic, says "make an infographic", "visualize this plan", "I can't read walls of text", or after a plan is finished. Also auto-triggered by the Stop hook when a ready/in-progress project's infographic is missing or stale. Builds artifacts/infographic.html and links it in index.md.
---

# Project Infographic Skill

You turn a project's `plan.md` + `tasks.md` into a **one-page, self-contained HTML infographic** — a visual the user can review at a glance instead of reading the full plan. The plan stays the source of truth; this is the scannable view.

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Resolve **every** path against this absolute root — `index.md`, each project's `path`, `plan.md`, `tasks.md`, `artifacts/infographic.html` — regardless of the current working directory. This skill may be invoked from another repo; never assume cwd is the hub. Pass this absolute root to each build subagent so it reads and writes there, not into the cwd. (Same convention as `todo-refer`.)

## The model this runs on

The infographic generation — the token-heavy, creative design + HTML work in Step 3 — is delegated to a subagent so it runs on **Claude Sonnet (latest)** with **high reasoning effort**. Don't build the HTML inline in the orchestrating session. The orchestrating session does the light work (resolve projects, stub-check, register in index.md, confirm); the actual build is dispatched.

Use the `Agent` tool with `model: sonnet`, `effort: high`. Spawn **one subagent per project** (run them in parallel when building several), each handed that project's `plan.md` + `tasks.md` content and the Step 3 spec below; it writes `artifacts/infographic.html` and returns a one-line confirmation. Then you (orchestrator) handle Steps 4–5.

**Compose with design skills.** Instruct each build subagent to load the `artifact-design` skill (if installed) before designing, and `dataviz` before drawing any chart-like element — progress bars, stat cards, phase meters all count. These skills are distilled design procedure; loading them is cheaper than a redesign round. If a design-critique / frontend-design skill is installed, the subagent runs one self-critique pass against it before writing the final file — one pass, not a loop.

**Before dispatching**, check whether `artifacts/infographic.html` already exists for each project. If it does, read its full content and pass it to the subagent as `existingHtml`. The subagent uses this to preserve the theme exactly (see Step 3).

## How the user invokes this

```
/todo-infographic event-fanout   ← one project by short-name
/todo-infographic projects/work/...                ← full path also works
/todo-infographic all                              ← every ready/in-progress/done project (explicit opt-in only)
/todo-infographic                                  ← the project in scope for this session (NOT all stale ones)
```

**Scope: single-project by default.** Generate the infographic only for the project the session is working on. Do **not** fan out to every project. `all` is an explicit opt-in — never inferred. If no single project is clearly in scope and no argument was given, ask which project rather than defaulting to all.

It is also fired automatically by the plugin's **Stop hook** (`infographic-staleness.sh`, auto-registered): when a project whose status is `ready` or `in-progress` has a missing or stale `artifacts/infographic.html`, the hook lists it before ending the turn. The hook's list is a repo-wide staleness scan, **not** a scope instruction — regenerate only the listed project(s) you actually worked on this session, and leave the rest stale. If none of the listed projects relate to this session, stop without generating anything.

## Step 1 — Resolve the project(s)

Read `$TODO_HUB/index.md` to map short-name → `path` / `repo` / `status`.

- Short name → look it up; not found → tell the user and stop.
- Full path → use as-is.
- `all` → operate on every project with status `ready`, `in-progress`, or `done`. Only when the user explicitly passes `all`.
- No argument → resolve to the single project in scope for this session. If that's ambiguous, ask — do **not** default to every project.

## Step 2 — Read the plan and guard against stubs

For each target project read `plan.md` and `tasks.md`.

**Stub check (important):** if `plan.md` still contains the template text `What success looks like in one sentence.` or has no real Goal/Scope content, it is an unfilled stub. **Do not generate an infographic for a stub.** Report it: e.g. "reserve-mcp-integration is marked `ready` but plan.md is still the template — run `/todo-plan <name>` to fill it first." Then skip that project.

## Step 3 — Build the infographic (Sonnet, latest, subagent)

This step runs inside the dispatched Sonnet (latest) subagent (see "The model this runs on"). Produce `artifacts/infographic.html` inside the project folder. Self-contained: no network, no external assets, everything inline — must open offline. Print-friendly.

**Theme: existing vs. new — decide first.**

- **`existingHtml` provided** → **preserve the theme exactly.** Extract the CSS — palette (hex values / CSS variables), font stack, card styles, layout structure, spacing, visual personality — and carry it forward unchanged into the new file. Your job is **content-only**: update stat numbers, bullet text, phase progress bars, and section data to match the current `plan.md` / `tasks.md`. Do not change any visual property.
- **No `existingHtml`** → **invent a fresh visual theme.** Pick a distinctive palette, typographic treatment, and layout personality that suits this specific project; let it differ from other projects. Everything visual is yours to design.

In both cases: aim for a polished, genuinely scannable one-pager, not a generic dashboard. The structural constants are the content sections below and the at-a-glance, no-walls-of-text discipline.

Fill these sections from the plan. **Summarise — never transcribe.** No walls of text; if a bullet runs long, compress it to a clause.

- **Header** — project name, short-name · category, status pill (`ready`/`in-progress`/`done`), repo path.
- **Goal** — the one-sentence goal, lightly bolded on the key noun.
- **Stat cards** — 3–5 at-a-glance numbers. Always include phase count and task count (`N done`). Add 2–3 project-specific metrics that matter (channels, new apps, LOC, before→after footprint, target version — whatever the plan emphasises).
- **Scope** — In (green) vs Out (muted), the most important items only.
- **Flow / Topology** — if the plan has an architecture or data-flow (ASCII diagram, "topology", request path), render it as boxes + arrows. Mark net-new pieces `.new`, the focal path `.accent`, untouched/legacy `.old`. Delete the section entirely if there is no flow — don't ship an empty shell.
- **Key Decisions** — numbered cards, one-line rationale each. Note the "don't re-litigate" framing if the plan has it.
- **Constraints** — chips; mark hard non-negotiables with `.warn`.
- **Execution Plan** — one `.phase` block per phase header in `tasks.md`. Each shows a `done/total` badge, a progress bar whose width = `round(done/total*100)%`, and a short summarised bullet list of that phase's tasks. Flag the riskiest/biggest phase with a distinct badge.
- **Note** — the single biggest risk or gotcha from the plan's Notes.
- **Footer** — "Generated from plan.md + tasks.md · <today's date>" + "plan.md remains the source of truth". Use today's date from context — do not invent a timestamp.

### Counting tasks for the bars
Count `- [ ]` (open) and `- [x]` (done) checkboxes per phase. **Skip the `## Status` legend block** that the tasks.md template ships (its `- [ ] Not started` / `- [x] Done` lines are documentation, not tasks), and **skip anything inside HTML comments** (the template's `## Revisions` section has a commented-out example with a `- [ ]` line). A shell count, if useful:

```bash
awk '/<!--/{c=1} c{if(/-->/)c=0; next} /^## /{p=($0!~/^## Status/)} p&&/^[[:space:]]*- \[/{t++} p&&/^[[:space:]]*- \[x\]/{d++} END{print d+0"/"t+0}' tasks.md
```

## Step 4 — Register it in index.md

The section tables in `index.md` (`## Work`, `## Self-initiative`, …) have an `infographic` column. Set this project's cell to a link to the file you generated:

```
[open](projects/<cat>/<name>/artifacts/infographic.html)
```

Projects without one stay `-`. There is no separate Infographics table — the column is the only place this is tracked, so don't create one.

## Step 5 — Confirm

Tell the user, briefly, which infographics you generated/updated (with clickable paths), which projects you skipped as stubs, and that they can open the `.html` in a browser. Don't paste the HTML.

## Notes
- Visual quality matters — this exists because the user can't review walls of text. Favour structure, colour-coding, and whitespace over completeness. If a detail doesn't earn its place on one screen, leave it in plan.md.
- Give each **new** infographic its own character — a different palette and personality per project is the point. Don't converge on one house style when starting fresh. When updating an existing one, do the opposite: preserve the CSS verbatim so it stays visually consistent across refreshes.
