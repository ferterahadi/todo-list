# todo-list

**A project tracker that Claude Code or Codex actually works through for you.** Tell it
about a project once. It writes the plan, works the checklist, checks whether the result
holds up, and fixes what didn't. It's all plain markdown you can open and edit yourself —
nothing to build, nothing to run, no database.

## The concept

There's one hub — a single folder (`~/todo` by default) that tracks *all* your projects,
kept separate from the repos where your actual code lives:

```
~/todo/
  index.md                     ← active projects, one row each
  archive.md                   ← finished rows, kept rather than deleted
  REGISTRY.md                  ← what each registry column means
  projects/
    work/api-rate-limiting/
      plan.md                       goal, scope, decisions
      tasks.md                      the checklist the agent works through
      artifacts/                    things the agent produces
```

Each project folder just points at wherever its code actually lives. Your repos aren't
touched until you ask the agent to go and do the work.

Four of the skills make up a `plan → do → check → revise` loop:

```
/todo-plan  ──▶  /todo-execute  ──▶  /todo-verify  ──▶  /todo-revise
  plan             do (build)         check (gate)       fix the gaps
                                                              │
                                          loops back until accepted
```

Here's a whole project, start to finish:

```
/todo-add "add rate limiting to the API"   # set it up and register it
/todo-plan api-rate-limiting               # look into it and write the plan
/todo-execute api-rate-limiting            # work the checklist
/todo-verify api-rate-limiting             # did it actually pass?
/todo-revise api-rate-limiting             # fix whatever the check caught
```

Stopped halfway through? `/todo-refer api-rate-limiting resume` works out where you left
off and picks it back up.

If one project is waiting on another, say so once and the agent plans around it:

```
/todo-graph link api-migration depends-on auth-foundation "consumes its token contract"
/todo-graph                                # what's ready to start right now
```

## Install

**Claude Code** — two commands. This repo doubles as its own marketplace:

```bash
claude plugin marketplace add ferterahadi/todo-list
```
```
/plugin install todo-list@todo-list
```

Next time you start a session, the `/todo-*` skills show up and a hub gets created at
`~/todo` with one example project in it. If you already have a hub there, it's left alone.

**Just the skills, for Claude Code and Codex** — one command. No hooks, and it won't set
up a hub for you:

```bash
npx skills add ferterahadi/todo-list --agent claude-code --agent codex --global --yes
```

**Want the hub somewhere else?** Set `TODO_HUB` in your shell profile *before* you run
anything:

```bash
export TODO_HUB=~/my/hub/path
```

### Try it

```
/todo-list                              # see the project index
/todo-refer example-feature             # load its plan + tasks
/todo-execute example-feature           # work its checklist
```

> In Claude Code the commands are prefixed with the plugin name, so `/todo-plan` is really
> `/todo-list:todo-plan`. In Codex, say `$todo-plan` or just describe what you want.

## Why the installer shows risk warnings

`npx skills add` prints a risk table from three independent scanners — Gen Agent Trust
Hub, Socket, and Snyk. Some rows come back amber. None of the three found malware,
credential harvesting, or malicious install behavior; Socket's own summary of `todo-push`
is that it "does exactly what it claims using official git/GitHub tooling."

The amber rows are the scanners noticing capabilities this pack grants on purpose:

| What they flag | Which skills | Why it's there |
|---|---|---|
| Runs shell commands | add, execute, graph, refer, state, triage | `python3` for the graph helper, `grep`/`awk` for task counts, `git`/`gh` for repo evidence |
| Reads text someone else wrote | most of them | `plan.md`, `tasks.md`, `index.md` are the input. A planning tool that won't read your plans is not a planning tool |
| Publishes and merges code | push, execute | `/todo-push` exists to branch, commit, push, open a PR, and merge. That authority is the feature |
| Hands work to subagents | execute, triage | Parallel execution and fast-tier gathering |

Two things worth knowing before you install:

- **`/todo-push` merges without asking.** Point it at a repo and it will land the change on
  your default branch. It refuses to force-merge past a conflict and never uses `--admin`,
  but it does not stop for confirmation at the merge itself.
- **Every skill validates names before they reach a command line.** Project short-names,
  branch names, and repo paths read out of your registry are checked against a strict
  pattern first; a value carrying a shell metacharacter stops the command and gets reported
  instead of being interpolated.

Every finding is readable in full at
[skills.sh/ferterahadi/todo-list](https://skills.sh/ferterahadi/todo-list) — open any
skill, then its Socket, Snyk, or Agent Trust Hub page.

## Update

Because this is a third-party marketplace, auto-update is **off** by default — new
releases won't just turn up. Updating takes two commands, and you need both. The first
fetches what's new, the second actually moves you onto it:

```bash
claude plugin marketplace update todo-list   # fetch the new releases
claude plugin update todo-list               # switch to the newest one
claude plugin list | grep -A1 todo-list      # check which version you're on now
```

Restart Claude Code afterwards and the new version is live. If you'd rather not do this by
hand, you can turn auto-update on for this marketplace in `/plugin` → Marketplaces →
todo-list.

One thing worth knowing: updating only refreshes the plugin's own files. If you use the
[response-style pack](#optional-the-response-style-pack), run `/todo-style install` again
afterwards — that's a separate step, and it's the one that rewrites your own instruction
file.

## The 17 skills

**Track** — getting projects in, and seeing where they stand

|Skill|Purpose|
|-|-|
|`todo-add`|Sets up a new project folder and adds it to the index|
|`todo-list`|Shows the index by status; also does `archive` and `sort`|
|`todo-triage`|Lists open work across every project and suggests a model for each task|
|`todo-state`|Tick tasks or change status by hand; `audit` checks it against what git shows|

**Work** — the loop itself, plus how projects depend on each other

|Skill|Purpose|
|-|-|
|`todo-plan`|Looks into it, then writes `plan.md` and `tasks.md`|
|`todo-execute`|Works through the checklist; `parallel` splits tasks across git worktree agents|
|`todo-graph`|Say which projects block which, then ask what's ready, what's stuck, and why|
|`todo-review`|Checks a diff against the plan — did it drift, is anything unproven|
|`todo-review-handoff`|Packages a review so someone else can make the call — claims, what to check, a sheet to fill in|
|`todo-verify`|The check: runs the tests, ticks tasks, opens Revisions for anything that failed|
|`todo-revise`|Fixes what the check caught, then checks again|

**Bridge** — connecting the hub to your real repos

|Skill|Purpose|
|-|-|
|`todo-refer`|Loads a project's context from any repo; `resume` works out where things stopped|
|`todo-push`|The whole shipping run: branch → commit → push → PR → merge|
|`todo-infographic`|Turns a plan into a one-page HTML infographic|
|`todo-learn`|Saves a correction as a lasting rule in that repo's own skill files|

**Housekeeping**

|Skill|Purpose|
|-|-|
|`todo-archive`|Moves finished rows into `archive.md` — nothing is thrown away|
|`todo-style`|Swaps in the bundled response-style pack for Claude Code and Codex, backing your current file up first|

**Shared** — not a command you run

|Skill|Purpose|
|-|-|
|`todo-llm-routing`|The shared settings that decide which model each skill asks for|

All 17 above share it.

Projects move through `planning → ready → in-progress → done`. If you want the full rules
for a skill, they're in [`skills/`](skills/).

**It works with your other skills rather than replacing them.** If you've got skills like
superpowers brainstorming, test-driven-development, code-review or dataviz installed, the
todo skills hand the thinking over to those. If you don't have any of them, each todo
skill falls back to doing it itself.

## Optional: the response-style pack

Every other skill here organises your *work*. `/todo-style` is the one that changes how
the agent *talks* to you. It's written for people who know their stuff but don't have much
time: pick one response shape, say what something means before showing evidence, use the
smallest useful visual, and reserve completion receipts for changed or verified work.

```
/todo-style            # what's installed now vs what ships
/todo-style diff       # exactly which lines would change
/todo-style install    # back up, then swap in
/todo-style restore    # put your old file back
```

It writes to your **global** agent instruction file — `~/.claude/CLAUDE.md` for Claude
Code, `~/.codex/AGENTS.md` for Codex (same rules, written for each one). Three things
protect you, because that file is usually one you've tuned yourself:

- It swaps the whole file out and never merges the two. `/todo-style diff` shows you that
  before anything happens.
- Your current file is copied to `$TODO_HUB/backups/agent-instructions/` and checked byte
  for byte **before** anything is written over. If the copy doesn't come out right, the
  install stops.
- Nothing in that folder is ever deleted, and `restore` puts the most recent one back.

Installing the plugin doesn't do this to you — `/todo-style install` is the only thing
that writes to that file, and updating the plugin later won't rewrite it either. Run
`/todo-style install` again when you want the newer wording. See [Update](#update).

It's entirely up to you — no hook runs it, no other skill calls it, and everything else in
the plugin works the same whether you install it or not.

## Remove it

```bash
claude plugin uninstall todo-list@todo-list      # remove the plugin (skills + hooks)
claude plugin marketplace remove todo-list       # remove the marketplace entry
```

That leaves the hub behind, which is your own plans and notes. Delete it whenever you
want:

```bash
rm -rf ~/todo    # or wherever TODO_HUB points
```

## More

- [CHANGELOG.md](CHANGELOG.md) — what changed in each release. See [Update](#update) for
  how to move onto a new one.
- [`skills/todo-verify/SKILL.md`](skills/todo-verify/SKILL.md) — `/todo-verify` can drive
  any MCP (Model Context Protocol) test server that meets a small contract. Haven't got
  one? Leave the `## Verification` block out of `plan.md` and the rest of the loop still
  works.
- [CONTRIBUTING.md](CONTRIBUTING.md) — issues and pull requests welcome.

MIT licensed — see [LICENSE](LICENSE).
