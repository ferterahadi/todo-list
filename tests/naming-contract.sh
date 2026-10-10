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
aliases="todo-state:todo-sync todo-list:todo-triage"
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

# --- E. todo-list is merged into todo-triage ------------------------------------------------
stale="$(stale_refs '(^|[[:space:]`(])/todo-list([^:@a-z-]|$)|skills/todo-list/|`todo-list`|overview is todo-list')"
[ -z "$stale" ] || fail "stale todo-list references:
$stale"
grep -Fq '/todo-triage archive' "$repo_root/skills/todo-triage/SKILL.md" ||
  fail "todo-triage must document its archive view"
grep -Fq '/todo-archive sort' "$repo_root/skills/todo-archive/SKILL.md" ||
  fail "todo-archive must document its sort mode"
grep -Fq 'then again with `archive`' "$repo_root/skills/todo-list/SKILL.md" ||
  fail "/todo-list all must still show active and archived projects"

# --- C. Internal skills are hidden from the command menu ------------------------------------
hidden_expected="todo-conventions todo-llm-routing"
hidden_actual=""
for skill_file in "$repo_root"/skills/*/SKILL.md; do
  if [ "$(frontmatter_field "$skill_file" user-invocable)" = "false" ]; then
    hidden_actual="$hidden_actual $(basename "$(dirname "$skill_file")")"
  fi
done
[ "${hidden_actual# }" = "$hidden_expected" ] ||
  fail "hidden skills are '${hidden_actual# }', expected '$hidden_expected'"
for name in $hidden_expected; do
  case "$(description "$repo_root/skills/$name/SKILL.md")" in
    "Internal — "*) ;;
    *) fail "$name description must start with 'Internal — ' (Codex cannot hide skills)" ;;
  esac
done
case "$(description "$repo_root/skills/todo-graph/SKILL.md")" in
  "Only needed when one project must wait for another."*) ;;
  *) fail "todo-graph description must open with when it is needed" ;;
esac

# --- D. Menu size -------------------------------------------------------------------------
visible=0
for skill_file in "$repo_root"/skills/*/SKILL.md; do
  if [ "$(frontmatter_field "$skill_file" user-invocable)" = "false" ]; then continue; fi
  if [ -n "$(frontmatter_metadata "$skill_file" renamed-to)" ]; then continue; fi
  visible=$((visible + 1))
done
[ "$visible" -eq 16 ] || fail "the command menu shows $visible skills, expected 16"

# --- F. The README says which command to use when ------------------------------------------
grep -Fq '`revise` = the result is wrong · `learn` = the agent'"'"'s habit is wrong' "$repo_root/README.md" ||
  fail "README must distinguish revise from learn"
grep -Fq '## The 16 commands' "$repo_root/README.md" ||
  fail "README heading must state the command count"

printf 'ok - naming contract\n'
