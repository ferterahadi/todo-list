---
name: todo-execute-parallel
description: Use when the user invokes /todo-execute-parallel, says "execute these tasks in parallel", "work multiple features of the same repo at once", "fan this out with worktrees", or names a hub project and wants independent tasks done concurrently. For single or sequential work use /todo-execute.
---

# Parallel Project Execution Skill

You fan a hub project's independent tasks out to parallel agents, each in its own
git worktree of the target repo, and land the results on main through a serial
merge queue. You are the orchestrator: agents build and open PRs; only you merge,
only you touch hub files.

## Hub location

The hub repo root is `$TODO_HUB` — an environment variable pointing at your clone of this repo (default `~/todo`). Resolve every hub path against this
absolute root regardless of cwd (same convention as `todo-execute`).

## Invocation

```
/todo-execute-parallel <short-name>
/todo-execute-parallel <short-name> tasks 3,5,7   ← explicit task subset
```

## Step 1 — Resolve and orient

Same as `/todo-execute` steps 1–2: resolve the project via `$TODO_HUB/index.md`,
read `plan.md`, `tasks.md`, and `research/findings.md` if present. `plan.md` must name
the target repo path; verify it exists locally and `gh auth status` succeeds there —
stop and report if not. Set index.md status to `in-progress`.

## Step 2 — Partition tasks into features

Group the unchecked tasks into **file-disjoint features**: tasks that touch the same
files, or depend on each other's output, go in the SAME feature (they run sequentially
inside one agent). Judge overlap from plan.md scope notes and a quick read of the repo.

- 1 feature after grouping → parallelism buys nothing; say so and run `/todo-execute`.
- State the grouping (feature → task lines) before spawning so it's on record.

**Gate A — before spawning (every box checked, literally, or don't spawn):**

- [ ] For each feature, the expected file/dir set is WRITTEN OUT (from plan.md scope +
  a grep of the repo), and every pairwise intersection between features is empty. Two
  features sharing even one file → merge them into one feature now.
- [ ] Every agent prompt contains all four slots from step 4 (intent verbatim,
  workspace commands, implement instruction, return contract) — reread each prompt and
  point at the four slots before sending.
- [ ] `gh auth status` succeeded in the target repo THIS session (output seen, not
  assumed).

## Step 3 — No model pinning

This skill does not pin or recommend models for either wave. Implement and review
agents run on the inherited session model — omit `model` on the Agent calls in
steps 4 and 5. The todo-push sub-step stays pinned to Haiku (latest) by its own skill —
don't override that.

## Step 4 — Implement wave (one agent per feature, all in one message, in parallel)

One background `general-purpose` Agent per feature, on the inherited session model
(no `model` param). Each prompt is self-contained — agents start with zero history.
Every prompt MUST contain these slots:

1. **Intent** — plan.md `## Goal` + relevant context/constraints, and the exact task
   lines this feature covers, verbatim. This grounds the code review later.
2. **Workspace** — create an isolated worktree of the TARGET repo (never the hub):
   ```
   git -C <repo> fetch origin
   git -C <repo> worktree add <repo>-wt/<feat> -b feat/<name> origin/<base>
   cd <repo>-wt/<feat>   ← all work happens here
   ```
   Then install dependencies the way the repo does (check its README/CLAUDE.md).
3. **Implement** the feature's tasks, with unit tests, committed in the worktree.
4. **Return contract** — branch name, worktree path, files added/changed, blockers.
   Implement agents NEVER edit hub files, NEVER open PRs, NEVER merge — review and
   shipping belong to step 5.

Agents that hit an external blocker (creds, live services) report it in their return
and stop that feature — same rule as `/todo-execute` step 5, but the blocker lands in
`artifacts/blockers.md` via YOU, not the agent.

## Step 5 — Review wave (no model pin — inherited session model)

The moment a feature's implement agent returns, spawn its review agent — pipeline,
don't wait for the other features. Review agents are spawned by YOU with no `model`
param (inherited session model), same as the implement wave. Review agent prompt
slots:

1. **Intent** — the same intent block from step 4, verbatim.
2. **Workspace** — `cd <repo>-wt/<feat>` (the existing worktree; create nothing).
3. **Review** — invoke the `code-review` skill at **high** effort on the worktree
   diff, with the intent restated. Apply the fixes.
4. **Coverage gate** — for every file the diff ADDS: find all its call sites
   (grep the repo for imports/usages of its exported symbols), then run the repo's
   coverage tooling scoped to the added files and those call-site files. Require 100%
   line coverage on all of them; write unit tests and re-run until green. Report the
   final coverage numbers — never claim the gate passed without the run output.
5. **Ship to PR only** — invoke the `todo-push` skill with the instruction: "You are in a
   linked worktree. Stop at the PR — do not merge; the orchestrator owns the merge
   queue." (todo-push's worktree mode handles the rest.)
6. **Return contract** — PR URL, branch name, worktree path, review findings applied,
   coverage output, blockers. Review agents NEVER edit hub files and NEVER merge.

## Step 6 — Serial merge queue

Parallel until PR; **serial at merge**. When agents return, merge PRs one at a time:

```
git -C <repo>-wt/<feat> fetch origin
git -C <repo>-wt/<feat> rebase origin/<base>      ← replay on latest main
git -C <repo>-wt/<feat> push --force-with-lease
gh pr merge <url> --merge                          ← never --delete-branch here
```

- Rebase conflict → resolve it in that worktree if the resolution is mechanical;
  otherwise skip the PR, finish the queue, and open a Revisions entry in tasks.md.
- Never merge two PRs concurrently, and never merge before its rebase + push.

**Gate B — before EACH merge (re-run per PR, not once for the queue):**

- [ ] The previous PR in the queue is confirmed merged (`gh pr view <prev> --json state`
  shows `MERGED` — output seen).
- [ ] This PR's branch was rebased onto latest `origin/<base>` in THIS queue round —
  a rebase from before the previous merge doesn't count; redo it.
- [ ] Tests/CI are green on the post-rebase commit, with the run output in hand. No
  output → run them now; red → this PR skips the queue and gets a Revisions entry.

## Step 7 — Cleanup

From the PRIMARY repo copy (first path in `git worktree list`), for each feature:

```
git -C <repo> worktree remove <repo>-wt/<feat>
git -C <repo> branch -d feat/<name>
git -C <repo> worktree prune
git -C <repo> pull --ff-only        ← once, if primary sits on <base> and is clean
```

## Step 8 — Reconcile hub state and report

Only now, and only you: tick the completed task lines in `tasks.md`, write blockers to
`artifacts/blockers.md`, and set index.md status per `/todo-execute` step 6 (a
`## Verification` block in plan.md means stay `in-progress` and point at
`/todo-verify` — merged PRs + unit tests ≠ done).

Report per feature: PR link, merge result, coverage numbers, blockers. Keep it short.

## Rules

- Parallel until PR, serial at merge — no exceptions, races corrupt main.
- Review always runs as a separate agent from implementation, but neither wave pins
  a model — both inherit the session model.
- Agents never write hub files; the orchestrator is the only hub writer.
- A feature = file-disjoint task group; overlapping tasks share one agent.
- Worktrees are of the target repo. `Agent isolation: 'worktree'` worktrees the
  CURRENT repo (usually the hub) — don't use it for this; agents run the
  `git worktree add` themselves inside the target repo.
