---
name: response-style
description: Project-specific corrections about response-style prompt authoring. Learned conventions for changing the todo-list response packs. Consult before editing or reviewing the Claude-facing style pack.
metadata:
  internal: true
---

# Response style — learned conventions

Corrections captured via /todo-learn. Each is a standing rule for this repo.

## 2026-08-19 — Make Claude answers practical before technical

- **Rule:** Make the first scan answer four questions in plain words: **What's wrong?**, **What's the solution?**, **Why does it work?**, and **What should I do next?** Keep technical evidence below that practical story.
- **Why:** The reader should understand the problem, fix, reasoning, and next action immediately without translating system terms, logs, or diffs.
- **How to apply:** When editing or reviewing `skills/todo-style/assets/CLAUDE.md`, make these four questions the dominant briefing structure. Introduce services and code terms in everyday language, and move paths, identifiers, logs, and mechanism details to an optional technical-detail section. Do not change the Codex pack for this correction.
