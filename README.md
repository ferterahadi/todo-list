# todo-list

**Pick up a project in a new Claude Code or Codex session and ask, “Where did I leave off?”**
The agent reads your saved plan and checklist, shows what’s done, and identifies the next
task. When you’re ready, ask it to do the work and verify the result.

## Install

Run the two commands for your client in a terminal, then start a new session.

**Claude Code**

```bash
claude plugin marketplace add ferterahadi/todo-list
claude plugin install todo-list@todo-list --scope user
```

**Codex**

```bash
codex plugin marketplace add ferterahadi/todo-list
codex plugin add todo-list@todo-list
```

Your **hub** is the folder where both clients read and write your project notes. It
defaults to `~/todo`. To choose another folder, set `TODO_HUB` in your shell profile
before opening the new session.

### Try it

The plugin’s startup hook seeds a new hub with `example-feature`, a fictional API
project. Ask about it before connecting a real repository.

| Client | Enter in the new session |
|---|---|
| Claude Code | `/todo-list:todo-refer example-feature` |
| Codex | `$todo-list:todo-refer example-feature` |

A fresh example has **0 of 10 tasks done**. Its plan gives each API token a bucket of
100 tokens, refilling at 100 per minute. An empty bucket returns HTTP 429 with a
`Retry-After` header.

Codex also offers three starting prompts:

- Show my projects, their status, and which are ready or blocked.
- Plan the next project in my todo hub.
- Resume the highest-priority unfinished project.

## Track your own project

Start in your repository and tell the agent what you want to achieve. For example:

| When | What to ask |
|---|---|
| Starting out | “Create a project called search-filters for this repo and plan how to add a date filter to search.” |
| After you approve the plan | “Work on the first task in search-filters.” |
| Returning in a new session | “Where did I leave off with search-filters?” |
| Checking the result | “Verify search-filters against the plan.” |

Each project has a `plan.md` for its goal and decisions and a `tasks.md` for its checklist.
You can edit both as plain Markdown. Code changes go in the linked repository. Research
and writing projects can live entirely in the hub.

## The 16 commands

Use plain language or choose a skill by name. In Claude Code, use `/todo-list:todo-plan`
for `todo-plan`. In Codex, use `$todo-list:todo-plan`.

| Skill | Use it to… |
|---|---|
| `todo-add` | Register a project in the hub. |
| `todo-plan` | Turn a goal into a plan and a checklist for approval. |
| `todo-execute` | Work through approved tasks, sequentially or in parallel. |
| `todo-review` | Compare changes with the plan and flag gaps. |
| `todo-verify` | Look up a test result or explicitly run verification. |
| `todo-revise` | Fix a finding and check the result. |
| `todo-push` | Open a pull request and merge it when repository rules allow. |
| `todo-refer` | Read one project’s context or resume where you stopped. |
| `todo-triage` | See what’s left across projects and what to work on next. |
| `todo-graph` | Record dependencies and see which projects are ready or blocked. |
| `todo-sync` | Update a project’s recorded status or audit it against Git. |
| `todo-archive` | Move finished work into the archive. |
| `todo-review-handoff` | Give a reviewer the findings that need their decision. |
| `todo-infographic` | Turn a plan into a one-page HTML graphic. |
| `todo-learn` | Save a correction for future sessions in that repo. |
| `todo-style` | Preview, install, or restore an optional response style. |

`revise` = the result is wrong · `learn` = the agent's habit is wrong.

Older names and internal skills also appear in the [skill reference](skills/README.md).

| Skill | Purpose |
|---|---|
| `todo-state` | Renamed to `todo-sync`. |
| `todo-list` | Formerly a separate command. Use `todo-triage`. |
| `todo-conventions` | Internal rules for reading and updating the hub. |
| `todo-llm-routing` | Internal model and reasoning-effort settings. |

## Update

**Claude Code** — refresh the marketplace, update the plugin, then restart Claude Code.
Check the installed version with `claude plugin list`.

```bash
claude plugin marketplace update todo-list
claude plugin update todo-list@todo-list --scope user
```

**Codex** — refresh the marketplace and install its current version. Check the result
with `codex plugin list --marketplace todo-list --json`.

```bash
codex plugin marketplace upgrade todo-list
codex plugin add todo-list@todo-list
```

If your Codex marketplace is pinned to an older tag, refreshes keep that pin. To switch
to a specific release, use its tag in the following commands:

```bash
codex plugin marketplace remove todo-list
codex plugin marketplace add ferterahadi/todo-list --ref v1.18.1
codex plugin add todo-list@todo-list
```

## Other installation options

**Skills only.** If you already manage your own hub, install the skills without the
startup hooks:

```bash
npx skills add ferterahadi/todo-list --agent claude-code --agent codex --global --yes
```

**Permissions.** The skills read your project files and use shell tools such as Git.
Asking `todo-push` to ship authorizes a merge without a second confirmation. Repository
branch protections still apply. [Installer scanner reports](https://skills.sh/ferterahadi/todo-list)

**Optional response style.** Use `todo-style diff` to preview the global instructions
that `todo-style install` will replace. The installer backs up your current file first.
Use `todo-style restore` to recover it. To adopt a newer style after a plugin update,
run `todo-style install` again. [Response-style guide](skills/todo-style/SKILL.md)

**Uninstall.** Removing the plugin leaves your project notes in the hub.

| Client | Remove plugin | Remove marketplace |
|---|---|---|
| Claude Code | `claude plugin uninstall todo-list@todo-list` | `claude plugin marketplace remove todo-list` |
| Codex | `codex plugin remove todo-list@todo-list` | `codex plugin marketplace remove todo-list` |

[Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [MIT license](LICENSE)
