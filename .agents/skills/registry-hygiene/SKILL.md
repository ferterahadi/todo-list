---
name: registry-hygiene
description: Project-specific corrections about what may be written into the hub registries (index.md, archive.md). Learned conventions for how to work on this in the todo-list hub. Consult before editing a registry file or adding a status/handoff surface to a skill.
metadata:
  internal: true
---

# Registry hygiene — learned conventions

Corrections captured via /todo-learn. Each is a standing rule for this repo.

## 2026-07-27 — Never write status prose into index.md or archive.md
- **Rule:** The registries hold their title, fixed preamble, the one-line `Start here` pointer, and the section tables. Nothing else — no status banner, release note, deploy summary, or revision narrative, and no `##` heading that is not a section. Status goes to the owning project's `artifacts/`: a dated `YYYY-MM-DD-handoff-<slug>.md` for what is next, `journal.md` for what happened, `blockers.md` for what is stuck. If a cold session needs to be pointed at it, that is a link, not a copy.
- **Why:** A registry is read constantly and edited narrowly, so a pasted paragraph is paid for on every hub-wide scan and re-read by nobody before they edit a row. It rots in place while still looking current. This happened for real: a 398-word 2.18.0 release report sat on top of `$TODO_HUB/index.md` and within a day contradicted itself — it named `2.18.0_a9ef26a` on 15/15 deployments and then, two clauses later, said `2.18.0_173d082` had superseded it and to "read image tags, never this line". Every claim in it already existed in the project's own handoff artifact and journal.
- **How to apply:** Editing a registry means editing a row. Wanting to surface "what is hot" means setting the single `Start here` line (`REGISTRY.md` § *The `Start here` line*), which `/todo-state` owns and repoints on `in-progress` flips — no other skill writes it. Answering "where was I" is `/todo-refer <short-name> resume`, which derives the answer from live files and git. When adding a report or handoff surface to any `skills/todo-*/SKILL.md`, route its output to `artifacts/`, never to `index.md`. `/todo-state audit` reports violations; fixing one relocates the text into the project's `artifacts/` rather than deleting it.
