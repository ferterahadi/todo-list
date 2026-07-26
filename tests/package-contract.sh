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

extract_install_skills() {
  local document="$1"
  local destination="$2"

  awk '
    !in_command && /npx[[:space:]]+skills[[:space:]]+add/ {
      in_command = 1
      found_command = 1
    }
    in_command {
      line = $0
      gsub(/\\/, " ", line)
      count = split(line, fields, /[[:space:]]+/)

      for (field_index = 1; field_index <= count; field_index++) {
        token = fields[field_index]
        if (token == "") {
          continue
        }
        if (token == "--skill") {
          capture = 1
          found_skill_flag = 1
          continue
        }
        if (capture && token == "--agent") {
          found_end = 1
          exit
        }
        if (capture) {
          print token
        }
      }
    }
    END {
      if (!found_command || !found_skill_flag || !found_end) {
        exit 3
      }
    }
  ' "$document" > "$destination" ||
    fail "could not parse the explicit install command in ${document#"$repo_root"/}"
}

assert_same_skill_set() {
  local label="$1"
  local expected="$2"
  local actual_raw="$3"
  local actual_sorted="$4"
  local duplicate_count
  local missing
  local unexpected

  LC_ALL=C sort "$actual_raw" > "$actual_sorted"
  duplicate_count="$(LC_ALL=C uniq -d "$actual_sorted" | wc -l | tr -d '[:space:]')"
  if [ "$duplicate_count" != "0" ]; then
    printf 'not ok - %s install command contains duplicate skills:\n' "$label" >&2
    LC_ALL=C uniq -d "$actual_sorted" >&2
    exit 1
  fi

  missing="$(LC_ALL=C comm -23 "$expected" "$actual_sorted")"
  unexpected="$(LC_ALL=C comm -13 "$expected" "$actual_sorted")"
  if [ -n "$missing" ] || [ -n "$unexpected" ]; then
    printf 'not ok - %s install command does not match public skills\n' "$label" >&2
    if [ -n "$missing" ]; then
      printf 'missing:\n%s\n' "$missing" >&2
    fi
    if [ -n "$unexpected" ]; then
      printf 'unexpected:\n%s\n' "$unexpected" >&2
    fi
    exit 1
  fi
}

require_command awk
require_command comm
require_command python3
require_command sort
require_command uniq

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
repo_skill_files=("$repo_root"/.agents/skills/*/SKILL.md)
shopt -u nullglob

[ "${#skill_files[@]}" -gt 0 ] || fail "no public skills found"

for skill_file in "${skill_files[@]}"; do
  skill_directory="$(basename "$(dirname "$skill_file")")"
  declared_name="$(frontmatter_name "$skill_file")"
  [ -n "$declared_name" ] ||
    fail "missing frontmatter name: ${skill_file#"$repo_root"/}"
  [ "$declared_name" = "$skill_directory" ] ||
    fail "frontmatter name mismatch in ${skill_file#"$repo_root"/}: $declared_name != $skill_directory"
  printf '%s\n' "$skill_directory" >> "$public_skills"
done
LC_ALL=C sort -u -o "$public_skills" "$public_skills"

grep -Fxq 'todo-llm-routing' "$public_skills" ||
  fail "public skills are missing todo-llm-routing"
grep -Fxq 'todo-graph' "$public_skills" ||
  fail "public skills are missing todo-graph"

documents=(
  "$repo_root/README.md"
  "$repo_root/skills/README.md"
  "$repo_root/CONTRIBUTING.md"
)
for document in "${documents[@]}"; do
  label="${document#"$repo_root"/}"
  safe_label="$(printf '%s' "$label" | tr '/.' '__')"
  install_raw="$temp_root/${safe_label}.raw"
  install_sorted="$temp_root/${safe_label}.sorted"

  extract_install_skills "$document" "$install_raw"
  assert_same_skill_set "$label" "$public_skills" "$install_raw" "$install_sorted"

  for repo_skill_file in "${repo_skill_files[@]}"; do
    repo_skill="$(basename "$(dirname "$repo_skill_file")")"
    if grep -Fxq "$repo_skill" "$install_sorted"; then
      fail "$label install command exposes repo-only skill: $repo_skill"
    fi
  done
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
