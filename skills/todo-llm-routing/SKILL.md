---
name: todo-llm-routing
description: Use when choosing a Claude Code or Codex model for todo-list work, translating Fable, Opus, Sonnet, or Haiku tiers to GPT models, or selecting reasoning effort.
---

# Cross-platform model routing

Route by capability tier first. Provider model names are implementations of the tier,
not part of a skill's behavior.

| Tier | Claude Code | Codex preferred | Codex fallback | Use for |
|---|---|---|---|---|
| `frontier` | Opus latest, max effort | `gpt-5.6-sol`, max effort | `gpt-5.5`, xhigh effort | Security, payments, data integrity, concurrency, multi-repo architecture |
| `deep` | Opus latest, high effort | `gpt-5.6-sol`, high effort | `gpt-5.5`, high effort | Ambiguous design, unknown-cause debugging, cross-file refactors |
| `balanced` | Opus latest, medium effort | `gpt-5.6-terra`, medium/high effort | `gpt-5.4`, medium/high effort | Well-scoped implementation, verification, visual generation |
| `fast` | Opus latest, low effort | `gpt-5.6-luna`, low effort | `gpt-5.4-mini`, low effort | Mechanical edits, formatting, state updates, routine Git operations |

This is a workload mapping, not a claim that the models are identical. On Claude Code all
four tiers resolve to Opus and **reasoning effort is the only lever**; on Codex the tier
still selects a different model.

## Why Opus at every Claude Code tier

Per [CursorBench 3.2](https://cursor.com/cursorbench), the Opus 5 effort sweep Pareto-dominates
the rest of the Claude lineup for agentic coding — it is both more accurate and cheaper per
task at the points that matter:

| Comparison | Loser | Winner | Delta |
|---|---|---|---|
| Whole Sonnet curve | Sonnet 5 max — 60.5% @ ~$6.6 | Opus 5 low — 62.3% @ ~$2.8 | +1.8pp for 2.4× less |
| Old `frontier` default | Fable 5 high — 65.5% @ ~$8.6 | Opus 5 max — 69.6% @ ~$8.2 | +4.1pp, marginally cheaper |

Consequences worth knowing before changing this back:

- **Sonnet and Haiku are not defaults anywhere.** Sonnet's best effort level scores below
  Opus's worst, so no tier justifies it on accuracy or price. Haiku is not on the benchmark.
- **Fable only wins at max effort** (70.0% @ ~$18 vs Opus max 69.6% @ ~$8.2) — +0.4pp for
  2.2× the cost. Not worth a default; reach for it by hand if a task genuinely warrants it.
- **The binding constraint is plan usage limits, not dollars.** Every tier now draws on the
  same Opus quota, so `fast`-tier work is no longer cheap relief. If quota is tight, drop the
  tier rather than the model — `fast` at low effort is the least expensive option here.

Benchmark numbers are read off the published chart and are approximate (±0.5pp / ±$0.5).

## When dispatching

1. Select the tier required by the task.
2. On Codex, use the preferred model only when it appears in `codex debug models` or the
   model picker. Otherwise use the fallback. Do not guess availability from API docs.
3. Use the current host's model and effort from the selected table entry.
4. If the host cannot choose a model for a subagent, inherit the session model or run
   inline. Never invent unsupported model or tool parameters.
5. Keep user-selected models. Treat this table as the default only.
6. Review this dated mapping when either provider changes its model lineup, or when
   CursorBench publishes a new revision.

Mapping reviewed: 2026-07-25 against CursorBench 3.2.
