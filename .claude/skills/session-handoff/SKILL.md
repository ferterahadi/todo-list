---
name: session-handoff
description: Project-specific corrections about end-of-session next-command handoffs. Learned conventions for how to recommend follow-up commands when working on the todo-list plugin. Consult before writing or editing report/handoff sections in the todo-* skills.
---

# Session handoff — learned conventions

Corrections captured via /todo-learn. Each is a standing rule for this repo.

## 2026-07-16 — Deferred pickup goes through /todo-resume, not a direct work command
- **Rule:** When a skill's report hands work to a *later session* ("whenever you want it", end-of-session wrap-up), recommend `/todo-resume <short-name>` as the entry point. Direct work commands (`/todo-revise`, `/todo-execute`, `/todo-push`) are act-now pointers for the current session only.
- **Why:** A future session starts cold; git/worktree/blocker state may have drifted since the handoff was written. `/todo-resume` re-orients on current state and its routing table already picks the right work command — jumping straight to `/todo-revise Rn` skips that orientation.
- **How to apply:** When adding or editing a report/handoff section in any `skills/todo-*/SKILL.md`, phrase deferred recommendations as `/todo-resume <short-name>`; keep the direct command only for immediate same-session next steps. `todo-resume` itself keeps its evidence→command routing table (it cannot recommend itself).
