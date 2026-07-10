---
name: todo-learn
description: Use when the user invokes /todo-learn, says "that's not what I wanted", "you did X but I wanted Y", "remember this correction", "learn from this", "don't do that again", "next time do Z", or otherwise flags a gap between what Claude did and what they expected. Records the correction as a durable rule in the working repo's skill files.
---

# Discrepancy Learning Skill

You turn a single correction into a **durable rule** that lives with the project it applies to. When the user says "that's not what I wanted" — or anything that means *what you did ≠ what I expected* — you capture the gap and write it into **the current working repo's own `.claude/skills/`**, so the next session in that repo inherits the lesson automatically.

The unit of learning is **one fact per correction**: what the right behavior is, *why*, and *how to apply it*. Project-scoped by default — the learning lands in the repo the work happened in, not globally — so each codebase accumulates its own corrections.

This is judgment work (deciding the right rule, the right topic, the right scope), so it's pinned to **Claude Sonnet (latest)** at **high reasoning effort** (`model: sonnet`, `effort: high`) rather than running inline on whatever the calling session is.

## How the user invokes this

```
/todo-learn                         ← capture the most recent correction from context
/todo-learn don't mark done before e2e   ← capture this specific lesson
```

Plain language counts too: "that's not what I wanted", "you did X but I wanted Y", "remember this for next time", "don't do that again", "learn from this".

## Step 1 — Pin down the discrepancy

State the gap back to the user in one line each, inferring from conversation context when you can:

- **What I did** — the actual behavior being corrected.
- **What you wanted** — the expected behavior.
- **Why it matters** — the reason the expected behavior is right (ask if not obvious; the *why* is the most valuable part and must not be guessed).

If you cannot cleanly separate did-vs-wanted, or the *why* is unclear, **ask before writing anything**. Never invent the user's intent on a correction.

## Step 2 — Resolve where the learning belongs

Default scope is **the current working repo** (the cwd's git root), because the user asked for per-project knowledge.

1. Find the repo root (`git rev-parse --show-toplevel`, or the cwd if not a repo).
2. The learning goes under `<repo-root>/.claude/skills/<topic>/SKILL.md`.
3. **Pick the topic** — a short kebab-case slug naming the *domain* of the lesson, not the one incident. Reuse an existing topic file when the lesson fits one; only create a new topic when none fits. Examples: `commit-style`, `voucher-checkout`, `test-discipline`, `pr-workflow`.
   - List existing topics first: `ls <repo-root>/.claude/skills/`.

If the lesson is clearly **not** project-specific — it's about how the user wants you to behave everywhere (tone, global workflow, universal preference) — say so and offer to write it to the auto-memory dir as a `feedback` entry instead (see Step 5). Don't force a global lesson into one repo's skill.

## Step 3 — Write or update the topic skill

If the topic file doesn't exist, create `<repo-root>/.claude/skills/<topic>/SKILL.md` with valid frontmatter so the project picks it up as a real skill:

```markdown
---
name: <topic>
description: Project-specific corrections about <topic>. Learned conventions for how to work on this in <repo>. Consult before doing <topic>-related work here.
---

# <Topic> — learned conventions

Corrections captured via /todo-learn. Each is a standing rule for this repo.
```

Then **append** one entry per correction (newest at the bottom). Keep entries atomic — one rule each:

```markdown
## <YYYY-MM-DD> — <one-line rule title>
- **Rule:** <the behavior to follow, imperative>
- **Why:** <the reason it matters>
- **How to apply:** <concrete trigger — when this comes up, do this>
```

Use today's date from context. If a new correction **refines or contradicts** an existing rule, edit that rule in place (and note the change) rather than leaving two conflicting entries.

## Step 4 — Make it callable globally (one-time, only if asked)

The *topic* skill is intentionally repo-local — it should only fire when working in that repo. Do **not** install topic skills globally.

(This `todo-learn` skill itself is the global piece: it ships in the todo-list plugin, so it's invocable from any project. The topic skill you write here does not — it lives in the worked-on repo's own `.claude/skills/<topic>/`.)

## Step 5 — Offer global memory for cross-project patterns

If the same class of correction has come up before, or the lesson is about how the user wants you to work *in general*, **offer** to also persist it as a `feedback` memory in the auto-memory dir — write it only on the user's OK. Follow the memory format: `feedback` type with `**Why:**` and `**How to apply:**` lines, linked to related memories like `[[definition-of-done]]`, plus a one-line pointer in `MEMORY.md`. Do not auto-write; do not nag if they decline.

## Step 6 — Confirm what changed

Report plainly and terse:
- Topic file written/updated (path) + whether it was created or appended.
- The rule title captured.
- Any memory entry written.

Keep it short — the rule entry speaks for itself.

## Notes
- **Project skill ≠ this hub.** The corrections land in the *worked-on* repo's `.claude/skills/`, not in the todo hub. The hub only hosts this capture skill.
- Topic files are committed with their repo, so the lesson travels to teammates and future clones — mention that the user may want to commit the new `.claude/skills/<topic>/SKILL.md`.
- One fact per entry. If a correction bundles several lessons, split them into separate entries (or separate topics).
- This skill never edits code — it only records how code work should be done.
