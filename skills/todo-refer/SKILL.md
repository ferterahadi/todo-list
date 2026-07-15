---
name: todo-refer
description: Use when the user invokes /todo-refer, says "refer to project X", "pull in the context for X", "give me the plan for X to review against", or wants a hub project's plan/tasks loaded as grounding before another command. Read-only, cross-repo (works from any repo).
---

# Project Refer Skill

You load a hub project's context into the **current** session so a follow-on command (commonly `/code-review`) is grounded in that project's goal, decisions, and tasks. This is **read-only** and **cross-repo**: the session may be scoped to a *different* repository (e.g. `notify-service`), so you always reach the hub by **absolute path**, never via the current working directory.

Run it inline on the current session model; use at least the **balanced** tier from
[`../model-routing.md`](../model-routing.md).

## Hub location

The hub repo is always at:

```
$TODO_HUB
```

Read `$TODO_HUB/index.md` to resolve names — NOT any `index.md` in the current repo (there usually isn't one). Use the literal expanded path; `$HOME/Documents/todo` is fine, a bare `index.md` is not.

## Steps

1. **Resolve the project.**
   - If the user gave a short-name, read `$TODO_HUB/index.md` and find the row whose `short-name` matches exactly. Take its `path` (e.g. `projects/work/service-auth`) and resolve it against the hub root → `$TODO_HUB/<path>`.
   - **Exact match first.** If no exact match, fuzzy-match against all `short-name`s across every section table. If there's one obvious candidate, confirm it ("Did you mean `service-auth`?"); if several, list them and ask.
   - **No name given** → list the projects (grouped by section, like `/todo-list` but names only) and ask **"Which project?"**. Stop and wait. Do not guess.
   - **Not found / not in index** → say so, list the available short-names, and stop. Do NOT scaffold anything — that's `/todo-add`.
2. **Read the project files — plan fully, tasks by extraction.** Read
   `$TODO_HUB/<path>/plan.md` in full (it's the grounding). For `tasks.md`,
   **do not read the whole file** — large ones run 60–115KB (~15–30k tokens) because
   they accumulate revision history. Extract only what the digest needs:
   ```bash
   grep -n '^\s*- \[ \]' tasks.md | head -20        # open tasks
   grep -nE '^### R[0-9]+.*\[open\]' tasks.md        # open revisions
   awk '/<!--/{c=1} c{if(/-->/)c=0; next} /^## /{p=($0!~/^## Status/)} p&&/^[[:space:]]*- \[/{t++} p&&/^[[:space:]]*- \[x\]/{d++} END{print d+0"/"t+0}' tasks.md   # done/total
   ```
   Read `tasks.md` in full only if the file is small (< ~15KB) or the follow-on command
   explicitly needs completed-task detail. If either file is missing, note it and load
   what exists.
3. **Follow `related` one hop.** Check the resolved row's `related` column in `index.md`. For each short-name listed (skip `-`/empty), look up its row and read only its `plan.md` `## Goal` line (or first line if there's no `## Goal` header) — do **not** load its `tasks.md` or full `plan.md`. This keeps backtracking to prior context cheap: one line per related project instead of a second full plan+tasks load. If a related short-name isn't in `index.md` (stale reference), skip it silently rather than erroring.
4. **Emit a short digest** (see format) so the user can eyeball that the right context loaded. The full file contents are now in your context for whatever command comes next.

## Output format

After loading, print a terse digest — not the raw files:

```
Loaded context: service-auth  ($TODO_HUB/projects/work/service-auth)

Goal: <one line from plan.md ## Goal>
Status: <status from index.md>
Open tasks:
- [ ] <first few unchecked items from tasks.md>
Done: <N>/<total> tasks
Related: <short-name> — <its one-line goal> (<its status>)   ← omit this line entirely if `related` is `-`
```

Keep it ~5–8 lines (plus one line per related project). If there are many open tasks, show the first 3–5 and add `…(+K more)`.

## Then what

This skill only front-loads context — it does not run the next command. Each `/x` is its own invocation, so the usual flow is two turns:

```
/todo-refer service-auth      ← this skill: loads plan + tasks
/code-review …                   ← next turn: reviews the current repo's diff
                                   against the now-loaded context
```

End the digest with a one-line nudge, e.g. `Context loaded — run /code-review (or your next command) and I'll ground it in this project.`

## Notes
- **Read-only.** Never edit `index.md`, `plan.md`, `tasks.md`, or any hub or current-repo file. To change task/status state use the hub's `/todo-update-state`; to run work use `/todo-execute`.
- **Cross-repo is the whole point.** Do not assume the current repo is the hub. Always read from `$TODO_HUB`.
- Loads `plan.md` + `tasks.md` only for the resolved project; `related` projects (Step 3) get a one-line goal digest each, never their full plan/tasks. Do not dump `artifacts/` contents (token-heavy); if the user explicitly asks, list artifact filenames, not bodies.
- If the user names a project that maps to a different local code repo (the `repo` column), that's fine — you're loading the *plan*, not switching repos. The review still targets the current session's repo.
