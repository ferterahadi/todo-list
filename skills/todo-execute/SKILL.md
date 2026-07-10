---
name: todo-execute
description: Use when the user invokes /todo-execute, says "execute this project", "work through tasks", or names a hub project and wants work done. Resolves the project via index.md and works tasks.md top to bottom, writing outputs to artifacts/.
---

# Project Execution Skill

You execute planned projects stored in a hub repo.

This involves real judgment and code work — run it inline on the main model; do not downgrade to Haiku.

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Resolve **every** path against this absolute root — `index.md`, each project's `path`, `plan.md`, `tasks.md`, `artifacts/` — regardless of the current working directory. This skill may be invoked from another repo; never assume cwd is the hub. (Same convention as `todo-refer`.)

## How the user invokes this

```
/todo-execute queue-migration
/todo-execute projects/work/queue-migration   ← full path also works
```

## Step 1 — Resolve the project path

Read `$TODO_HUB/index.md`.

- Short name (e.g. `queue-migration`) → look up in index.md to get the full `path`
- Not found → tell the user and stop
- Full path passed directly → use as-is

Check the project `status` in index.md:
- `ready` or `in-progress` → proceed
- `planning` → warn the user that plan.md/tasks.md may be empty, ask if they want to continue anyway

## Step 2 — Orient yourself

Read these files in order:
1. `plan.md` — goal, context, constraints, scope, and the repo path
2. `tasks.md` — full scope of work before touching anything
3. `research/findings.md` if it exists — prior research already done

Do not start executing until you've read all of them. If `plan.md` is missing critical info (goal unclear, no repo path, no context), state exactly what's missing and stop — suggest running `/todo-plan <name>` first.

## Step 3 — Update index.md status

Set the project status to `in-progress` in index.md.

## Step 4 — Isolate target-repo work in a worktree

Before editing any **target-repo** code, give this run its own git worktree, so a
concurrent session (another `/todo-execute`, another chat) sharing the same repo can't
overwrite your working tree — the usual cause of "my changes vanished."

- Scope: this applies **only** to code in the target repo (the `path`/repo named in
  `plan.md`). Hub files under `$TODO_HUB` — `artifacts/`, `tasks.md`, `index.md`,
  `research/` — are ALWAYS edited in the hub, never in the worktree.
- If the project produces only hub artifacts (analysis, docs) and touches no target-repo
  code, skip this step and note that you did.
- Create it off the base branch, named from the project short-name:
  ```
  git -C <repo> fetch origin
  git -C <repo> worktree add <repo>-wt/<short-name> -b todo/<short-name> origin/<base>
  ```
  `<base>` is the repo's default branch (usually main, occasionally master — confirm with
  `git -C <repo> symbolic-ref refs/remotes/origin/HEAD`). All target-repo code, builds,
  tests, and preview for this run happen inside `<repo>-wt/<short-name>`.
- Resumed run: if that worktree/branch already exists, reuse it — don't recreate.
- Do NOT push or merge here. Shipping is a separate, deliberate `/todo-push` the user runs
  when ready (see Step 7) — never auto-ship from this skill.

## Step 5 — Execute tasks top to bottom

Work through `tasks.md` one task at a time, running this **per-task loop for every
task, no exceptions** — it is what keeps execution quality independent of the model
running it:

1. **Define done first**: read the task line + the plan.md section it belongs to, and
   state in one line what evidence will prove THIS task is done (a passing test, a file
   existing, an output matching). If you can't state it, the task is ambiguous → Step 6.
2. **Do the work.**
3. **Verify with evidence**: run the proof you named in 1 and look at the output. Code
   → run the test/build. Doc/artifact → open it and check it answers the task. No
   runnable proof and no observable output → it is NOT done; treat as blocked.
4. **Only now tick the checkbox.** Ticking before step 3 is the failure mode this loop
   exists to prevent — a checked box is a claim, and claims need evidence first.
5. **One-line record** of what changed and where (worktree file, artifacts path).

Never batch steps 2–4 across multiple tasks. Rules of the road:

- Complete each task fully before moving to the next
- Target-repo code changes go in the Step 4 worktree; hub outputs (docs, analysis,
  scripts) go to `artifacts/`
- Keep artifacts self-contained — another Claude session should be able to read them cold
- Drop research notes or discoveries in `research/` if relevant
- When plan.md doesn't answer a question, that IS the answer — record the ambiguity
  (Step 6), don't improvise a decision the plan never made

After completing each task, check it off in `tasks.md`:
```
- [x] Task name
```

When checking off, **don't append findings or prose to the task line** — a task stays
one line. Discoveries go to `research/`, outcomes to `artifacts/`, with at most a short
pointer suffix (`— see research/findings.md § X`). `tasks.md` is read whole by six
skills; keeping it a bare checklist is what keeps every other skill cheap.

## Step 6 — Handle blockers

If a task requires external access you don't have (credentials, running services, live APIs):
- Document the blocker in `artifacts/blockers.md` with enough detail to unblock later
- Skip to the next task
- Never silently skip

If a task is ambiguous and `plan.md` doesn't resolve it:
- State the ambiguity clearly
- Ask the user before proceeding

## Step 7 — Report when done

Update index.md status:

- Blockers remain or tasks are open → stay `in-progress`.
- All tasks complete and `plan.md` has a `## Verification` block → stay `in-progress` and point the user at `/todo-verify <short-name>` — the verification run is the gate that flips `done`, not your own assessment. Code-complete + unit tests ≠ done.
- All tasks complete, no `## Verification` block, **but the Step 4 worktree has unmerged changes** → stay `in-progress`; the work isn't landed until it's shipped. Point the user at `/todo-push` (run from `<repo>-wt/<short-name>`).
- All tasks complete, no `## Verification` block, and nothing to ship (hub-only project) → set `done`.

Summarize:
- What was completed
- The worktree path + branch (`todo/<short-name>`) if one was created, and that shipping is a separate `/todo-push` run — left separate on purpose
- What's in `artifacts/` and what each file contains
- Any blockers in `artifacts/blockers.md`

Keep it short. The artifacts speak for themselves.
