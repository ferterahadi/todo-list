---
name: model-routing
description: Use when choosing a Claude Code or Codex model for todo-list work, translating Fable, Opus, Sonnet, or Haiku tiers to GPT models, or selecting reasoning effort.
---

# Cross-platform model routing

Route by capability tier first. Provider model names are implementations of the tier,
not part of a skill's behavior.

| Tier | Claude Code | Codex preferred | Codex fallback | Use for |
|---|---|---|---|---|
| `frontier` | Fable 5, high effort | `gpt-5.6-sol`, max effort | `gpt-5.5`, xhigh effort | Security, payments, data integrity, concurrency, multi-repo architecture |
| `deep` | Opus latest, high effort | `gpt-5.6-sol`, high effort | `gpt-5.5`, high effort | Ambiguous design, unknown-cause debugging, cross-file refactors |
| `balanced` | Sonnet latest, medium/high effort | `gpt-5.6-terra`, medium/high effort | `gpt-5.4`, medium/high effort | Well-scoped implementation, verification, visual generation |
| `fast` | Haiku latest, low effort | `gpt-5.6-luna`, low effort | `gpt-5.4-mini`, low effort | Mechanical edits, formatting, state updates, routine Git operations |

This is a workload mapping, not a claim that the models are identical. Fable and Opus
both map to the flagship Codex model; reasoning effort separates the highest-risk tier
from ordinary deep work.

When dispatching:

1. Select the tier required by the task.
2. On Codex, use the preferred model only when it appears in `codex debug models` or the
   model picker. Otherwise use the fallback. Do not guess availability from API docs.
3. Use the current host's model and effort from the selected table entry.
4. If the host cannot choose a model for a subagent, inherit the session model or run
   inline. Never invent unsupported model or tool parameters.
5. Keep user-selected models. Treat this table as the default only.
6. Review this dated mapping when either provider changes its model lineup.

Mapping reviewed: 2026-07-15.
