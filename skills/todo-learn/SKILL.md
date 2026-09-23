---
name: todo-learn
description: Use when the user invokes /todo-learn or wants the agent to behave differently in this repo from now on — says "don't do that again", "next time do Z", "learn from this", "make that a rule for this repo", or "always/never do X here". Records one standing rule in the working repo's skill files (`.agents/skills/`, mirrored to `.claude/skills/`) so Claude Code and Codex both follow it next time. Not for fixing a hub project's delivered work — "the result isn't what I expected" is /todo-revise — and not for the host's own memory of personal facts.
---

# Discrepancy Learning Skill

You turn a single correction into a **durable rule** that lives with the project it applies
to. When the user wants the agent to act differently *next time* — "don't do that again",
"next time do Z" — capture the rule in the current repo's canonical `.agents/skills/`,
then expose the same skill under `.claude/skills/`. This gives Codex and Claude Code one
shared lesson.

Two neighbours take requests that sound similar:

- **The work itself is wrong** — a hub project's delivered result misses the expectation
  and needs fixing → `/todo-revise`. If the user also wants the lesson kept, record it
  here after.
- **A personal fact to remember** — "remember that I prefer…" with no repo behavior
  attached → the host's own memory, not this skill.

The unit of learning is **one fact per correction**: what the right behavior is, *why*, and *how to apply it*. Project-scoped by default — the learning lands in the repo the work happened in, not globally — so each codebase accumulates its own corrections.

This is judgment work about the right rule, topic, and scope, and Step 1 reads the
correction out of this conversation — a separate agent would not see it. Run it inline
on the current session model; use at least the **balanced** tier at **high** effort from
[`../todo-llm-routing/SKILL.md`](../todo-llm-routing/SKILL.md).

## How the user invokes this

```
/todo-learn                         ← capture the most recent correction from context
/todo-learn don't mark done before e2e   ← capture this specific lesson
```

Plain language counts too: "don't do that again", "next time do Z", "learn from this", "make that a rule here".

## Step 1 — Pin down the discrepancy

State the gap back to the user in one line each, inferring from conversation context when you can:

- **What I did** — the actual behavior being corrected.
- **What you wanted** — the expected behavior.
- **Why it matters** — the reason the expected behavior is right (ask if not obvious; the *why* is the most valuable part and must not be guessed).

If you cannot cleanly separate did-vs-wanted, or the *why* is unclear, **ask before writing anything**. Never invent the user's intent on a correction.

## Step 2 — Resolve where the learning belongs

Default scope is **the current working repo** (the cwd's git root), because the user asked for per-project knowledge.

1. Find the repo root (`git rev-parse --show-toplevel`, or the cwd if not a repo).
2. The canonical learning goes under
   `<repo-root>/.agents/skills/<topic>/SKILL.md`.
3. **Pick the topic** — a short kebab-case slug naming the *domain* of the lesson, not the one incident. Reuse an existing topic file when the lesson fits one; only create a new topic when none fits. Examples: `commit-style`, `voucher-checkout`, `test-discipline`, `pr-workflow`.
   - List existing topics in both `.agents/skills/` and `.claude/skills/` first.

If the lesson is clearly **not** project-specific — it's about how the user wants you to behave everywhere (tone, global workflow, universal preference) — say so and offer to write it to the auto-memory dir as a `feedback` entry instead (see Step 5). Don't force a global lesson into one repo's skill.

## Step 3 — Write or update the topic skill

If the topic file doesn't exist, create
`<repo-root>/.agents/skills/<topic>/SKILL.md` with valid frontmatter so Codex picks it
up as a real skill:

```markdown
---
name: <topic>
description: Project-specific corrections about <topic>. Learned conventions for how to work on this in <repo>. Consult before doing <topic>-related work here.
metadata:
  internal: true
---

# <Topic> — learned conventions

Corrections captured via /todo-learn. Each is a standing rule for this repo.
```

`metadata.internal: true` is not decoration. `.agents/skills/` and `.claude/skills/` are
directories `npx skills add <repo>` scans, so without the flag a repo's private
corrections get offered to anyone installing that repo's skills. The flag only affects
that installer — Claude Code and Codex read these directories directly, so both agents
still pick the skill up normally.

Default to the flag. Add it to an older topic file that predates this rule the next time
you touch that file. Drop it only when the user explicitly wants the convention
distributed with the repo's public skills — say so when you do, since it stops being a
private note at that point.

Then **append** one entry per correction (newest at the bottom). Keep entries atomic — one rule each:

```markdown
## <YYYY-MM-DD> — <one-line rule title>
- **Rule:** <the behavior to follow, imperative>
- **Why:** <the reason it matters>
- **How to apply:** <concrete trigger — when this comes up, do this>
```

Use today's date from context. If a new correction **refines or contradicts** an existing rule, edit that rule in place (and note the change) rather than leaving two conflicting entries.

## Step 4 — Expose the same skill to Claude Code

The *topic* skill is intentionally repo-local — do **not** install it globally.

Create `.claude/skills/` if needed. Prefer a relative symlink so both agents read the
same source:

```bash
ln -s ../../.agents/skills/<topic> .claude/skills/<topic>
```

If symlinks are unavailable, copy the topic folder and keep both copies byte-identical
on later updates. Do not replace an existing real `.claude/skills/<topic>` directory
without user approval; reconcile its rules into the canonical file first.

## Step 5 — Offer global memory for cross-project patterns

If the same class of correction has come up before, or the lesson is about how the user wants you to work *in general*, **offer** to also persist it as a `feedback` memory in the auto-memory dir — write it only on the user's OK. Follow the memory format: `feedback` type with `**Why:**` and `**How to apply:**` lines, linked to related memories like `[[definition-of-done]]`, plus a one-line pointer in `MEMORY.md`. Do not auto-write; do not nag if they decline.

## Step 6 — Confirm what changed

Report plainly and terse:
- Topic file written/updated (path) + whether it was created or appended.
- The rule title captured.
- Any memory entry written.

Keep it short — the rule entry speaks for itself.

## Notes
- **Project skill ≠ this hub.** Corrections land in the worked-on repo's
  `.agents/skills/` and `.claude/skills/`, not in the todo hub.
- Topic files and links are committed with their repo, so the lesson travels to
  teammates and future clones — mention that the user may want to commit both paths.
- One fact per entry. If a correction bundles several lessons, split them into separate entries (or separate topics).
- This skill never edits code — it only records how code work should be done.
