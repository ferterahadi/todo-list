---
name: todo-review-handoff
description: Use when the user invokes /todo-review-handoff, says "hand this review to someone else", "turn the review into a document her agent can run", "let the PM judge these findings", "make the review checkable", "package this review for another team", or has review findings that a different person — often non-engineer — must rule on before anything is fixed. Converts findings into numbered falsifiable claims plus a ruling sheet, so the recipient's agent proves or refutes each one and the recipient decides which get addressed. Does NOT review code itself (it delegates that) and never applies a fix.
---

# Review Handoff Skill

You turn a code review into a document **someone else can adjudicate**.

A review is a pile of opinions. Handed over raw, the recipient can only trust it or
ignore it — and if they aren't an engineer, they can't judge it at all. This skill
converts each finding into a **falsifiable claim** with a verification method, so the
recipient's own agent proves or refutes it and prints the evidence in plain English. The
recipient then rules on each claim, including the option to rule that **the reviewer was
wrong**. Only accepted claims get fixed, by a second agent, from the same document.

Without this skill the flow is `/code-review` and then a wall of findings pasted into
chat, where the recipient's only move is to defer to whoever wrote it.

**You never fix anything and you never re-review.** Findings come from the installed
review skill; you own the conversion, the evidence spec, and the ruling surface.

This is judgment work — grading your own confidence in someone else's findings is the
hard part. Run it inline on the current session model; use at least the **deep** tier
from [`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md), **balanced** as a
floor.

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your hub folder
(default `~/todo`). Resolve every hub path against this absolute root regardless of the
current working directory — this skill is usually invoked FROM the target repo, so never
assume cwd is the hub. (Same convention as `todo-refer`.)

**The hub is optional here.** A review handoff is frequently about a pull request in a
repo that has no hub project — another team's, another product's. Both paths are
first-class; Step 2 decides which.

## How the user invokes this

```
/todo-review-handoff https://github.com/org/repo/pull/1062   ← review that PR, hand it off
/todo-review-handoff queue-migration                          ← hub project's diff
/todo-review-handoff                                          ← infer from current repo
```

Plain language counts: "package this review for the PM", "make my findings checkable",
"let her agent verify this".

If the user already has findings — from an earlier `/code-review` in this session, or
pasted in — use those and skip Step 1. Do not re-review work that was just reviewed.

## Step 1 — Get the findings (delegate, don't rebuild)

Establish what's under review first: a PR URL (fetch the diff and metadata via `gh`), a
branch comparison, a patch, or the current repo's unlanded diff. State the target —
branch, commit range, file count — before judging it.

Then obtain findings, in this order of preference:

1. **Findings already in this session** — reuse them.
2. **`todo-review`**, when the target maps to a hub project. It adds plan compliance
   (scope drift, violated constraints, ticked tasks with no evidence) on top of the
   correctness pass, and those make excellent claims.
3. **The installed `code-review` skill** on the diff.
4. **Fallback, nothing installed:** run the pass yourself — security, correctness,
   performance, maintainability, test coverage — with a `file:line` for every finding.
   Prioritise real defects over style.

**Read the tests too, not only the source.** A large share of the most useful claims are
about the test suite: what has no coverage, what is pinned as intended that maybe
shouldn't be, and tests that don't execute the code they claim to guard. A review that
only reads source cannot produce those claims.

## Step 2 — Resolve the target and the recipient

**Hub project?** Resolve an explicit short-name using `todo-refer`'s active-first,
archive-on-exact-miss rules. With no name, match the current repo against active
`index.md` rows first, `archive.md` only on a miss. One match → use it and say which
registry supplied it. Several or none → treat it as standalone; don't ask twice.

| | Hub project resolved | Standalone |
|---|---|---|
| Document path | `$TODO_HUB/projects/<name>/artifacts/review-handoff.md` | `./review-handoff-<slug>.md` in cwd |
| Fix step | Accepted rows become `## Revisions` entries for `todo-revise` | Second-agent brief inside the document |
| Registry | Link the artifact in the owning `index.md` / `archive.md` row | — |

**Who is ruling?** Ask if it isn't obvious, because it changes the writing:

- **A non-engineer** (product manager, founder, account lead) — the common case. Every
  claim must be readable without opening the code, and the evidence spec must demand
  plain-English decoding.
- **An engineer on another team** — you can lean on `file:line` and skip some glossing,
  but keep the claim/verdict/ruling separation intact.

Never assume the recipient can read the diff.

## Step 3 — Convert each finding into a claim

This step is the skill. A finding is an assertion; a claim is an assertion **someone can
disprove**. Work through the findings and drop or merge any that won't convert.

Number them `R1…Rn` in severity order, most consequential first, and group them under
short headings that say what the group is about ("the tool reports a write it did not
make"). Each claim carries exactly these parts:

- **Title** — one line, plain words, judgeable cold. *"Hours tool reports success when it
  wrote nothing."*
- **Claim** — the falsifiable statement. Not *"error handling is weak"* — that cannot be
  disproved. *"`applied[]` contains `timeOptions` when no record was written."*
- **Mechanism** — how the code produces it, with `file:line` for every step.
- **Trigger** — the concrete input or situation that reaches it, described as a real
  person's action. A claim with no trigger is a hypothesis; say so or drop it.
- **Why it matters** — the consequence in the recipient's terms: customers, orders,
  money, reversibility. Not "violates the principle of…".
- **Confidence** — one of:
  - `observed` — you ran it, or the line literally says it. `staged: true` is a hardcoded
    literal; that's observed.
  - `corroborated` — inferred, but independent evidence elsewhere in the repo agrees.
    Cite it.
  - `inferred` — deduced from reading, and it could be wrong. **Say plainly how it could
    be wrong and what would settle it.** Under-grading your confidence costs you nothing;
    over-grading it spends the recipient's trust once.
- **Verify** — `OFFLINE` (mockable now), `NEEDS LIVE` (requires a real environment), or
  `READ` (settled by reading, nothing to run).
- **Agent verifies** — the specific check: what to call, what to mock, what to assert,
  what to print.
- **Reviewer suggests** — the smallest fix. For `inferred` claims, state what happens if
  the claim is refuted: *"no change — and the reviewer was wrong."*

Three rules that keep the ledger honest:

1. **Mark product decisions as such.** Some findings aren't defects — the code is
   working as written and someone has to choose whether that's wanted. Label them and say
   there's a defensible answer either way. Burying a product decision among bugs steals
   the decision.
2. **Every claim must be disprovable.** If you cannot describe evidence that would refute
   it, it is taste, not a finding. Move it to the appendix as a note or cut it.
3. **Never inflate the count.** Nineteen real claims beat thirty padded ones; the ruling
   sheet is read row by row and every weak row costs attention the strong ones need.

## Step 4 — Write the handoff document

One markdown file, five parts, in this order.

### 4.1 Header

What the document is, in four sentences: a reviewer made N claims; an agent verifies
them; the recipient rules; only accepted claims get fixed. Then the target (repo, branch,
PR link), the base path all file references are relative to, what the code does in plain
words, and what was reviewed (file and line counts, **including the tests**).

### 4.2 Instructions for the first agent

Its job is to produce **one runnable script** — not a test suite, a demonstration the
recipient can run and read.

State the script path and that it takes one command, no arguments, no credentials, no
dev server. Then the per-claim output block:

```
────────────────────────────────────────────────
R1  Hours tool reports success on a write of nothing

    CLAIM      applied[] contains "timeOptions" when no record was written
    RAN        <the real call>
               In plain terms: <the situation a person would be in>
    UPSTREAM   <what actually reached the mocked client, or "0 calls">
               <one plain sentence>
    RETURNED   <the verbatim returned value>
    MEANS      <the payload decoded into ordinary words>
    HAPPENED   <what the mocks observed>
    VERDICT    CONFIRMED — <one sentence>
────────────────────────────────────────────────
```

The rules that make this block work, all of which must appear in the document:

- **`RETURNED` is verbatim.** Not trimmed, not summarised, not prettied.
- **`MEANS` decodes field names into ordinary words** for someone who has never seen
  them. And it must **never paraphrase the code's own success message as fact** — on the
  claims that matter, that message *is* the false statement. Quote it under `RETURNED`;
  describe it under `MEANS` as *what the code asserts*, not as what occurred.
- **No judgement in `MEANS`.** It says what the payload claims, never whether the claim
  is true. Unclear field? Write that rather than guessing.
- **`VERDICT` stands alone** — `CONFIRMED`, `REFUTED`, `PARTLY CONFIRMED`,
  `CANNOT VERIFY` with a reason. Separate from `MEANS` on purpose: the recipient must be
  able to accept the decoding and still reject the conclusion.
- **`NEEDS LIVE` claims print `CANNOT VERIFY`** and say what would settle them. Never
  infer a verdict from mocks.
- **The script exits 0 either way.** It is a report, not a gate.
- **Expand every abbreviation and internal term on first use.** Assume no knowledge of
  the codebase.
- **Refute freely** — a refuted claim is as useful as a confirmed one, and the ledger
  says which claims are only `inferred`.
- **Fix nothing.** Not the source, not the tests. A failing test is the evidence working.

If a structural blocker stops the agent from executing the code at all — undecodable
decorators, an unbuildable module, a missing harness — name it in the document with the
minimum mechanical change that unblocks it, and tell the agent to **stop and report** if
that isn't enough rather than working around it.

### 4.3 The ruling sheet

One row per claim: the number, the one-line title, an **`Agent verdict`** column the
first agent fills, then four columns the recipient fills — **fix now · fix later · won't
fix · reviewer is wrong**.

The fourth column is mandatory and must be described as real in the surrounding text,
naming the claims most likely to fall to it (the `inferred` ones). A ruling sheet where
the reviewer cannot lose is a rubber stamp.

Under the table, in prose: which rows are product decisions rather than defects, and
which rows need an engineer rather than an agent.

### 4.4 Instructions for the second agent

Written to be read cold, months later, by an agent that has none of this context. It
fixes only rows marked *fix now* or *fix later*, and:

- **Ignores *won't fix* and *reviewer is wrong* rows — including any it disagrees with.**
  Those were decided by someone with the authority to decide them. It may note the
  disagreement in its report and must still leave them alone.
- **Stops and asks** when a row is marked *fix now* but its agent verdict came back
  `REFUTED`.
- States each change in one sentence before writing it, makes the smallest change that
  satisfies the claim, and adds or repairs the test named in that row's suggestion. A fix
  with no test that would have caught it is not done.
- Re-runs the suite and the claim-check script. **The claim's verdict flipping to
  `REFUTED` on fixed code is the proof.**
- Does not touch the appendix, and does not tidy adjacent code.
- **Hands `NEEDS LIVE` and structural rows to a human** — writes the failing test, leaves
  it skipped with the reason, does not implement blind.
- Records `Fixed` / `Not fixed — reason` per row in the same file.

On the hub path, replace this section with a pointer: accepted rows become
`## Revisions` entries and `todo-revise` owns the fix loop. Keep the ignore-the-rejected
and stop-on-refuted rules either way.

### 4.5 Appendix — what's strong

What the review judged sound, with `file:line`, so it doesn't get "improved" while the
rest is being fixed. This is not padding: an agent handed a list of defects will
generalise, and naming the good code bounds the blast radius. It also makes the ledger
credible — a review with no positives reads as an attack.

## Step 5 — Write the covering note

A short message the user pastes when sending the file. Not a summary of the findings —
the document holds those. Four numbered steps (give the file to your agent, run the
script, fill the ruling sheet, hand it to a second agent), one line that the
*reviewer is wrong* column is real, and one line naming the product decisions as the rows
only they can settle.

Keep it under 300 words. It competes with everything else in their inbox.

## Step 6 — Register and report

On the hub path: link the artifact in the owning `index.md` / `archive.md` row, and add a
`tasks.md` pointer if the project tracks the handoff as work. Never edit `plan.md` —
findings are not a plan change until the recipient rules.

Report to the user: where the document is, the claim count by confidence grade
(`observed` / `corroborated` / `inferred`), which claims are product decisions, which
need a live environment, and the covering note ready to paste.

## When the ruling comes back

The recipient returns the same file with verdicts and rulings filled in. Then:

- **Hub project** → open one `## Revisions` entry per accepted row, expected-vs-actual
  captured from the claim, and hand to `todo-revise`.
- **Standalone** → the document's own second-agent section is the brief; run it or pass
  it on.
- **Refuted claims** → say so plainly and move on. No re-litigating a claim the
  recipient's own agent disproved; the ledger did its job.
- **`Reviewer is wrong` on a claim you graded `observed`** → that's a genuine
  disagreement, not a closed matter. Surface it once, with the evidence, and let the user
  decide whether to escalate.

## Invariants

- **Never fix anything in this skill.** Conversion and packaging only.
- **Never re-review** work the session already reviewed.
- **Every claim carries a `file:line`** and a stated confidence grade.
- **Every claim is disprovable**, or it isn't a claim.
- **The recipient can always rule that the reviewer was wrong.**
- **Product decisions are labelled**, never smuggled in as defects.
- **`inferred` claims say how they could be wrong** and what would settle them.
- **Report-only on the hub**: no `plan.md`, `tasks.md`, or registry-status edits beyond
  linking the artifact.
- **One file carries the whole chain** — claimed, verified, decided, done.
