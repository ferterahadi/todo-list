---
name: infographic-scope
description: Project-specific corrections about infographic generation scope. Learned conventions for how to work on this in the todo-list hub. Consult before doing infographic-related work here.
---

# Infographic Scope — learned conventions

Corrections captured via /todo-learn. Each is a standing rule for this repo.

## 2026-07-14 — Infographic generation is single-project by default
- **Rule:** When generating an infographic, only generate it for the specific task/project in scope for the current session. Do not generate infographics for all tasks/projects. Only do a bulk/all-projects run when the user explicitly asks for all.
- **Why:** Generating infographics for every project wastes work on unrelated tasks and produces output the user didn't ask for; the session's focus is one project.
- **How to apply:** On /todo-infographic (or any "make an infographic" request, including Stop-hook auto-triggers), build the infographic only for the project the session is working on. If no single project is clearly in scope, ask which one rather than defaulting to all. Treat "all" as opt-in — require explicit user request.
