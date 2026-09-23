# Full infographic design specification

Read this reference only for `full-build`: a new infographic, legacy HTML whose
deterministic migration was ambiguous, or a structural change. Routine, semantic,
and deterministic legacy migrations do not need design instructions.

Produce `artifacts/infographic.html` inside the project folder. Keep it
self-contained: no network-loaded assets, everything inline, opens offline, and
prints cleanly. It is a polished, genuinely scannable one-pager rather than a
generic dashboard or a transcription of the plan.

## Theme

- **Existing HTML:** preserve the theme exactly. Carry its CSS, palette, font
  stack, card styles, layout, spacing, print rules, and visual personality forward
  unchanged. Update content and add the refresh markers from
  [refresh-contract.md](refresh-contract.md). New sections reuse existing classes.
- **No existing HTML:** invent a distinctive theme suited to this project. New
  projects should not converge on one house style.

## Content

Summarize; never transcribe. Compress long bullets to clauses.

- **Header:** project name, short-name and category, status pill, repo path.
- **Goal:** one sentence in one plain-text `goal` content leaf. Style the whole
  leaf; do not split it with inner emphasis markup.
- **What & why (`W1`):** 2–3 sentences from Context explaining what is being built
  and how, not merely repeating the goal, in the `what-why` content leaf.
- **Stat cards:** 3–5 numbers, always including phase count and task progress; add
  only the most meaningful project-specific metrics. Every task or phase number is a
  bound value; captions never restate one.
- **Scope:** the most important In versus Out items.
- **Flow / topology:** boxes and arrows only when the plan contains a real flow.
  Mark net-new pieces `.new`, the focal path `.accent`, and legacy pieces `.old`.
- **File footprint (`F1`, `F2`, ...):** an indented directory tree from the
  orchestrator-provided footprint. Show status and a task-backed reason where one
  exists; never invent a reason. Collapse same-status runs. Drop the section when
  there is no footprint.
- **Trade-off ledger (`D1`, `D2`, ...):** one card per Key Decision, retaining the
  plan's numbering. Show decision, gain, cost, and superseded state where present,
  with the status line in a `decision:D<n>:status` content leaf. Plans without a
  Trade-offs section use the decision rationale instead.
- **Forgone (`X1`, `X2`, ...):** rejected alternatives and reasoned scope cuts.
  Drop when absent.
- **Limitations (`L1`, `L2`, ...):** accepted known gaps, not general risks. Drop
  when absent.
- **Constraints:** short chips, with hard non-negotiables visibly distinct.
- **Execution plan:** one block per phase heading (`## Phase` or `### Phase`) in
  tasks.md; a flat task list gets no phase blocks. Use the exact phase counts and
  percentages from the refresh manifest, a `phase:<key>` summary leaf, and short
  summarized tasks. Do not mark individual tasks done (no ✓ glyphs or state-styled
  rows) and print no percentage or ratio that is not bound: the helper updates
  counts, not rows. Flag the riskiest or largest phase.
- **Note:** the single biggest risk or gotcha, in the `note` content leaf. Drop when
  none qualifies.
- **Footer:** generated date, “plan.md remains the source of truth”, and:
  “Feedback: quote an ID in chat ('D2 is wrong because…'). This session:
  `/todo-revise <short-name>`. Later session: start with
  `/todo-refer <short-name> resume`."

## Stable review IDs

| Prefix | Element |
|---|---|
| `W1` | What & why |
| `D<n>` | Decision / trade-off card; matches plan numbering |
| `F<n>` | File-footprint row |
| `X<n>` | Forgone item |
| `L<n>` | Limitation |

An element that still exists keeps its ID. New elements take the next unused
number; never renumber or reuse a removed ID. Put
`data-todo-review-id="D<n>"` on every decision card as required by the refresh
contract. IDs are feedback handles, not decoration.

Use the deterministic helper's phase and total counts; do not recount them in the
model. After writing, initialize and verify the page using the commands in
[refresh-contract.md](refresh-contract.md).
