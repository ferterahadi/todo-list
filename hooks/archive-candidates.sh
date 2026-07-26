#!/usr/bin/env bash
# SessionStart hook: report archive debt without editing the hub.
set -euo pipefail

HUB="${TODO_HUB:-$HOME/todo}"
case "$HUB" in
  "~"*) HUB="${HOME}${HUB#\~}" ;;
esac

PLUGIN="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
REPORT="$PLUGIN/skills/todo-archive/scripts/archive-report.sh"

[ -f "$HUB/index.md" ] || exit 0
[ -f "$REPORT" ] || exit 0

bash "$REPORT" hook "$HUB"
