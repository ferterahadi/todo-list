---
name: todo-llm-routing
description: Use when choosing a Claude Code or Codex model for todo-list work, mapping capability tiers across providers, or balancing model cost, accuracy, and reasoning effort.
---

# Cross-platform model routing

Route by capability tier first, then choose the lowest-cost available model that can
meet the task's accuracy and verification needs. Optimize cost per accepted result,
including retries and review time. Provider model names belong here; other skills
keep using the four tiers.

| Tier | Claude Code | Codex | Use for |
|---|---|---|---|
| `frontier` | `Fable 5.1`, high effort | `gpt-6-astra`, high effort | Security, payments, data integrity, concurrency, multi-repo architecture |
| `deep` | `Opus 5`, high effort | `gpt-5.6-sol`, high effort | Ambiguous design, unknown-cause debugging, cross-file refactors |
| `balanced` | `Sonnet 5`, medium effort | `gpt-5.6-terra`, medium effort | Well-scoped implementation, verification, visual generation |
| `fast` | `Haiku 4.5`, default settings (no effort parameter) | `gpt-5.6-luna`, low effort | Mechanical edits, formatting, state updates, routine Git operations |

These are workload defaults, not cross-provider accuracy equivalences. Use `balanced`
for ordinary implementation and `fast` only when the result is easy to check. Start
at `deep` or `frontier` when ambiguity or the cost of a wrong result warrants it.

## Cost and accuracy rules

- Preserve a calling skill's explicit tier floor and effort override; for example,
  `balanced` at high effort keeps the balanced model and raises its effort.
- If a model misses a requirement or cannot resolve the cause after a focused attempt,
  inspect the failure and escalate effort or tier with that evidence. Fix missing context,
  tool failures, and environment problems directly; a stronger model will not repair them.
- Reserve `xhigh` or `max` for unresolved reasoning problems or an explicit requirement.
  High effort is the starting point for difficult work, not a guarantee of correctness.
- Do not lower the tier for security, payments, or data-integrity decisions just because
  quota is tight. Use cheaper models for separable mechanical work where permitted.
- Verify the result using the task's acceptance criteria. A passing format check does
  not establish semantic correctness, and a benchmark rank does not establish local accuracy.

### Price reference

Reviewed 2026-09-06. USD per million uncached input / output tokens, standard direct API
processing; OpenAI figures below use short-context rates. These are price references,
not Codex or Claude Code subscription-quota multipliers.

| Tier | Claude input / output | OpenAI input / output |
|---|---|---|
| `frontier` | $10 / $50 | $10 / $50 |
| `deep` | $5 / $25 | $4 / $20 |
| `balanced` | $2 / $10 | $2 / $12 |
| `fast` | $1 / $5 | $0.20 / $1.20 |

At equal uncached token counts, Terra costs 50% less for input and 40% less for output
than Sol; Sonnet costs 60% less than Opus for both. Actual task savings and accuracy
on this repository are **unmeasured**. Token counts, reasoning, cache reuse, long-context
rates, retries, and plan-specific limits can change the economics. For subscription
users, use observed quota consumption and completion quality instead of converting
these API prices into assumed message allowances.

Price sources: [OpenAI pricing](https://developers.openai.com/api/docs/pricing) and
[Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing).
Sol's listed price is promotional through at least 2026-11-21; Anthropic now lists
Sonnet 5's $2 / $10 rate as standard, replacing its previously scheduled price increase.

## When dispatching

1. Select the tier required by the task and any calling-skill constraints.
2. Resolve the model and effort against the current host's exposed model list or picker.
   API documentation does not prove account or subagent availability. On Claude Code,
   verify the version behind an alias rather than assuming `sonnet` means Sonnet 5.
3. If the entry is unavailable, prefer an available model that meets the same capability
   need; use a higher tier if necessary. State the fallback and use only supported effort
   values. If no adequate model is available, report the limitation rather than silently
   lowering the task's accuracy requirement.
4. If the host cannot choose a model for a subagent, inherit the session model or run
   inline. Never invent unsupported model or tool parameters.
5. Keep user-selected models. Treat this table as the default only.
6. Refresh the dated prices and capability guidance when provider lineups, pricing,
   host availability, or observed task outcomes change. Use comparable local outcomes
   (accepted results, retries, elapsed time, and cost or quota) to tune these defaults.

Capability sources: [Codex model guidance](https://learn.chatgpt.com/docs/models),
[Claude model comparison](https://platform.claude.com/docs/en/models/fable-5-1/overview),
and [Claude effort support](https://platform.claude.com/docs/en/build-with-claude/effort).
The tier assignments are routing judgments based on this guidance, not measured
accuracy rankings for todo-list.
