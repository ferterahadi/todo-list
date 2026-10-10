---
name: todo-state
description: Renamed to todo-sync in 1.16.0. Use only when the user types /todo-state; this alias is removed in 2.0.0.
metadata:
  renamed-to: todo-sync
---

# /todo-state was renamed to /todo-sync

1. Say exactly one line: "`/todo-state` is now `/todo-sync` — the old name stops working in 2.0.0."
2. Load [`../todo-sync/SKILL.md`](../todo-sync/SKILL.md) and follow it with the same
   arguments. Every mode is unchanged: `/todo-state X 2.1 done` behaves as
   `/todo-sync X 2.1 done`, and `/todo-state audit` as `/todo-sync audit`.
