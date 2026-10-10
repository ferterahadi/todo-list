---
name: todo-list
description: Merged into todo-triage in 1.16.0. Use only when the user types /todo-list; this alias is removed in 2.0.0.
metadata:
  renamed-to: todo-triage
---

# /todo-list was merged into /todo-triage

1. Say exactly one line: "`/todo-list` is now `/todo-triage` (sorting moved to `/todo-archive sort`) — the old name stops working in 2.0.0."
2. Route the arguments, then load that skill and follow it:

| Typed | Run |
|---|---|
| `/todo-list` or `/todo-list <status>` | [`../todo-triage/SKILL.md`](../todo-triage/SKILL.md), no arguments |
| `/todo-list archive` | [`../todo-triage/SKILL.md`](../todo-triage/SKILL.md) with `archive` |
| `/todo-list all` | `../todo-triage/SKILL.md` with no arguments, then again with `archive` |
| `/todo-list sort` | [`../todo-archive/SKILL.md`](../todo-archive/SKILL.md) with `sort` |
