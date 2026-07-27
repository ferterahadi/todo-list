---
name: session-handoff
description: Project-specific corrections about end-of-session next-command handoffs. Learned conventions for how to recommend follow-up commands when working on the todo-list plugin. Consult before writing or editing report/handoff sections in the todo-* skills.
metadata:
  internal: true
---

# Session handoff — learned conventions

Corrections captured via /todo-learn. Each is a standing rule for this repo.

## 2026-07-16 — Deferred pickup goes through resume mode, not a direct work command
- **Rule:** When a skill's report hands work to a *later session* ("whenever you want it", end-of-session wrap-up), recommend `/todo-refer <short-name> resume` as the entry point. Direct work commands (`/todo-revise`, `/todo-execute`, `/todo-push`) are act-now pointers for the current session only.
- **Why:** A future session starts cold; git/worktree/blocker state may have drifted since the handoff was written. Resume mode re-orients on current state and its routing table already picks the right work command — jumping straight to `/todo-revise Rn` skips that orientation.
- **How to apply:** When adding or editing a report/handoff section in any `skills/todo-*/SKILL.md`, phrase deferred recommendations as `/todo-refer <short-name> resume`; keep the direct command only for immediate same-session next steps. `todo-refer` itself keeps its evidence→command routing table (it cannot recommend itself).
- **Updated 2026-07-27:** the standalone `/todo-resume` skill merged into `todo-refer` as its `resume` mode. The rule is unchanged; only the command spelling moved.
