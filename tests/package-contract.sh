#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command is unavailable: $1"
}

frontmatter_name() {
  awk '
    NR == 1 && $0 == "---" {
      frontmatter = 1
      next
    }
    frontmatter && $0 == "---" {
      exit
    }
    frontmatter && /^name:[[:space:]]*/ {
      sub(/^name:[[:space:]]*/, "")
      print
      exit
    }
  ' "$1"
}

frontmatter_internal() {
  awk '
    NR == 1 && $0 == "---" {
      frontmatter = 1
      next
    }
    frontmatter && $0 == "---" {
      exit
    }
    frontmatter && /^metadata:[[:space:]]*$/ {
      in_metadata = 1
      next
    }
    frontmatter && in_metadata && /^[^[:space:]]/ {
      in_metadata = 0
    }
    frontmatter && in_metadata && /^[[:space:]]+internal:[[:space:]]*true[[:space:]]*$/ {
      print "true"
      exit
    }
  ' "$1"
}

# The published install command carries no --skill filter, so `npx skills add` installs
# everything it discovers. Two invariants keep that safe, and both are asserted below:
# the documented command stays unfiltered, and every repo-local skill is marked internal
# so the installer never offers it.
assert_unfiltered_install() {
  local document="$1"
  local label="$2"

  local status=0
  awk '
    !in_command && /npx[[:space:]]+skills[[:space:]]+add/ {
      in_command = 1
      found_command = 1
    }
    in_command {
      line = $0
      if (line ~ /--skill/) {
        found_filter = 1
      }
      if (line !~ /\\[[:space:]]*$/) {
        in_command = 0
      }
    }
    END {
      if (!found_command) {
        exit 3
      }
      if (found_filter) {
        exit 4
      }
    }
  ' "$document" || status=$?

  case "$status" in
    0) ;;
    3) fail "$label has no 'npx skills add' install command" ;;
    4) fail "$label install command still filters with --skill; it must install every discovered skill" ;;
    *) fail "could not parse the install command in $label" ;;
  esac
}

require_command awk
require_command cmp
require_command python3
require_command sort

json_files=(
  "$repo_root/.codex-plugin/plugin.json"
  "$repo_root/.claude-plugin/plugin.json"
  "$repo_root/.claude-plugin/marketplace.json"
)
for json_file in "${json_files[@]}"; do
  python3 -m json.tool "$json_file" >/dev/null 2>&1 ||
    fail "invalid JSON: ${json_file#"$repo_root"/}"
done

codex_version="$(
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' \
    "$repo_root/.codex-plugin/plugin.json" 2>/dev/null
)" || fail "Codex manifest is missing a version"
claude_version="$(
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' \
    "$repo_root/.claude-plugin/plugin.json" 2>/dev/null
)" || fail "Claude manifest is missing a version"
[ "$codex_version" = "$claude_version" ] ||
  fail "Claude and Codex manifest versions differ: $claude_version != $codex_version"
grep -Fq "## [$codex_version]" "$repo_root/CHANGELOG.md" ||
  fail "CHANGELOG.md is missing version $codex_version"

generated_python_files="$(
  find "$repo_root/skills" -type f -name '*.pyc' -print
)"
[ -z "$generated_python_files" ] ||
  fail "generated Python bytecode is present under skills/"

temp_root="$(mktemp -d)"
trap 'rm -rf "$temp_root"' EXIT

public_skills="$temp_root/public-skills"
: > "$public_skills"

shopt -s nullglob
skill_files=("$repo_root"/skills/*/SKILL.md)
repo_skill_files=("$repo_root"/.agents/skills/*/SKILL.md "$repo_root"/.claude/skills/*/SKILL.md)
shopt -u nullglob

[ "${#skill_files[@]}" -gt 0 ] || fail "no public skills found"

for skill_file in "${skill_files[@]}"; do
  skill_directory="$(basename "$(dirname "$skill_file")")"
  declared_name="$(frontmatter_name "$skill_file")"
  [ -n "$declared_name" ] ||
    fail "missing frontmatter name: ${skill_file#"$repo_root"/}"
  [ "$declared_name" = "$skill_directory" ] ||
    fail "frontmatter name mismatch in ${skill_file#"$repo_root"/}: $declared_name != $skill_directory"
  case "$skill_directory" in
    todo-*) ;;
    *) fail "public skill is not todo-prefixed: ${skill_file#"$repo_root"/}" ;;
  esac
  [ "$(frontmatter_internal "$skill_file")" = "true" ] &&
    fail "public skill is marked metadata.internal: ${skill_file#"$repo_root"/}"
  printf '%s\n' "$skill_directory" >> "$public_skills"
done
LC_ALL=C sort -u -o "$public_skills" "$public_skills"

grep -Fxq 'todo-llm-routing' "$public_skills" ||
  fail "public skills are missing todo-llm-routing"
grep -Fxq 'todo-graph' "$public_skills" ||
  fail "public skills are missing todo-graph"

# Repo-local learned-convention skills sit in directories `npx skills` scans. Without
# metadata.internal they would install alongside the public set once the documented
# command dropped its --skill filter.
for repo_skill_file in "${repo_skill_files[@]}"; do
  [ "$(frontmatter_internal "$repo_skill_file")" = "true" ] ||
    fail "repo-only skill is missing 'metadata:\\n  internal: true': ${repo_skill_file#"$repo_root"/}"
done

for agents_skill_file in "$repo_root"/.agents/skills/*/SKILL.md; do
  [ -e "$agents_skill_file" ] || continue
  mirror="$repo_root/.claude/skills/$(basename "$(dirname "$agents_skill_file")")/SKILL.md"
  [ -e "$mirror" ] ||
    fail "repo-only skill has no .claude mirror: ${agents_skill_file#"$repo_root"/}"
  cmp -s "$agents_skill_file" "$mirror" ||
    fail "repo-only skill and its .claude mirror differ: ${mirror#"$repo_root"/}"
done

documents=(
  "$repo_root/README.md"
  "$repo_root/skills/README.md"
  "$repo_root/CONTRIBUTING.md"
)
for document in "${documents[@]}"; do
  assert_unfiltered_install "$document" "${document#"$repo_root"/}"
done

catalogs=(
  "$repo_root/README.md"
  "$repo_root/skills/README.md"
)
for catalog in "${catalogs[@]}"; do
  while IFS= read -r public_skill; do
    grep -Eq "^[[:space:]]*\\|[[:space:]]*\`$public_skill\`[[:space:]]*\\|" \
      "$catalog" ||
      fail "${catalog#"$repo_root"/} catalog is missing $public_skill"
  done < "$public_skills"
done

printf 'ok - package contract\n'
