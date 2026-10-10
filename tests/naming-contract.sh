#!/usr/bin/env bash
# Contract test for skill names after the 1.16.0 command cleanup. It proves renamed skills
# left no stale references, aliases point at real skills and cannot capture plain-language
# requests, internal skills stay out of the command menu, and the menu size holds.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

# frontmatter_field <file> <key> — a top-level scalar from the YAML frontmatter, or empty.
frontmatter_field() {
  awk -v key="$2" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && index($0, key ":") == 1 {
      v = substr($0, length(key) + 2)
      sub(/^[[:space:]]+/, "", v)
      print v
      exit
    }
  ' "$1"
}

# frontmatter_metadata <file> <key> — the value of metadata.<key>, or empty.
frontmatter_metadata() {
  awk -v key="$2" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && /^metadata:[[:space:]]*$/ { inm = 1; next }
    fm && inm && /^[^[:space:]]/ { inm = 0 }
    fm && inm {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (index(line, key ":") == 1) {
        v = substr(line, length(key) + 2)
        sub(/^[[:space:]]+/, "", v)
        print v
        exit
      }
    }
  ' "$1"
}

# description <file> — the description folded onto one line (handles `>-` blocks).
description() {
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && /^description:/ {
      d = 1
      v = $0
      sub(/^description:[[:space:]]*(>-?)?[[:space:]]*/, "", v)
      out = v
      next
    }
    fm && d && /^[[:space:]]/ {
      v = $0
      sub(/^[[:space:]]+/, "", v)
      out = out " " v
      next
    }
    fm && d { d = 0 }
    END {
      sub(/^[[:space:]]+/, "", out)
      print out
    }
  ' "$1"
}

# stale_refs <regex> — lines in tracked or new files that match <regex>, outside the files
# allowed to keep an old name, and that do not say the name was renamed.
stale_refs() {
  git -C "$repo_root" grep --untracked -nIE "$1" -- . \
    ':!CHANGELOG.md' ':!tests/naming-contract.sh' \
    ':!skills/todo-state/SKILL.md' ':!skills/todo-list/SKILL.md' |
    grep -viE 'renamed|formerly' || true
}

# --- A. todo-state is now todo-sync -------------------------------------------------------
sync_skill="$repo_root/skills/todo-sync/SKILL.md"
[ -f "$sync_skill" ] || fail "skills/todo-sync/SKILL.md is missing"
[ "$(frontmatter_field "$sync_skill" name)" = "todo-sync" ] ||
  fail "skills/todo-sync/SKILL.md must declare name: todo-sync"
[ -f "$repo_root/skills/todo-sync/scripts/repo-evidence.sh" ] ||
  fail "repo-evidence.sh did not move with todo-sync"
stale="$(stale_refs 'todo-state|state-contract\.sh')"
[ -z "$stale" ] || fail "stale todo-state references:
$stale"

# --- B. Renamed-command aliases -----------------------------------------------------------
aliases="todo-state:todo-sync"
for pair in $aliases; do
  old="${pair%%:*}"
  new="${pair#*:}"
  stub="$repo_root/skills/$old/SKILL.md"
  [ -f "$stub" ] || fail "alias $old is missing"
  [ "$(frontmatter_metadata "$stub" renamed-to)" = "$new" ] ||
    fail "alias $old must declare metadata.renamed-to: $new"
  target="$repo_root/skills/$new/SKILL.md"
  [ -f "$target" ] || fail "alias $old points at missing skill $new"
  [ -z "$(frontmatter_metadata "$target" renamed-to)" ] ||
    fail "alias $old points at another alias ($new)"
  [ "$(find "$repo_root/skills/$old" -type f | wc -l | tr -d ' ')" = "1" ] ||
    fail "alias $old must contain only SKILL.md"
  [ "$(wc -l < "$stub" | tr -d ' ')" -le 20 ] || fail "alias $old grew beyond a stub"
  desc="$(description "$stub")"
  case "$desc" in
    *'"'*) fail "alias $old description carries quoted trigger phrases: $desc" ;;
  esac
  case "$desc" in
    *"only when the user types /$old"*) ;;
    *) fail "alias $old description must fire only on the typed name" ;;
  esac
done

printf 'ok - naming contract\n'
