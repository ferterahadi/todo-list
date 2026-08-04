#!/usr/bin/env bash
# The deterministic half of /todo-push: branch, stage, commit, push, open the PR, merge it,
# land back on the base branch. Every judgment call (branch name, which files, the message,
# the PR body) arrives as an argument — this script makes none of them.
#
# usage:
#   land.sh --branch <name> --message-file <path> --title <text> --body-file <path> \
#           --file <path> [--file <path>...] \
#           [--base <name>] [--no-merge] [--strategy merge|squash|rebase]
#
# exit codes:
#   0   shipped and landed
#   10  PR is open but the merge is blocked (protection, required review) — reported, not forced
#   11  not mergeable and the rebase hit a real conflict — rebase already aborted
#   12  precondition failed (bad argument, missing file) — nothing was mutated
#
# Every step is skipped when its effect is already present, so re-running with identical
# arguments after fixing a problem is safe.
set -euo pipefail

readonly EXIT_BLOCKED=10
readonly EXIT_CONFLICT=11
readonly EXIT_PRECONDITION=12

# Anything that becomes part of a git command is validated, never interpolated on trust.
readonly REF_PATTERN='^[A-Za-z0-9._/-]+$'

branch=""
base=""
title=""
message_file=""
body_file=""
strategy=""
no_merge=false
files=()

precondition() {
  printf 'land: %s\n' "$1" >&2
  exit "$EXIT_PRECONDITION"
}

usage() {
  sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --branch) branch="${2:-}"; shift 2 ;;
    --base) base="${2:-}"; shift 2 ;;
    --title) title="${2:-}"; shift 2 ;;
    --message-file) message_file="${2:-}"; shift 2 ;;
    --body-file) body_file="${2:-}"; shift 2 ;;
    --strategy) strategy="${2:-}"; shift 2 ;;
    --file) files+=("${2:-}"); shift 2 ;;
    --no-merge) no_merge=true; shift ;;
    -h|--help) usage ;;
    *) precondition "unknown argument: $1" ;;
  esac
done

git rev-parse --git-dir > /dev/null 2>&1 || precondition "not a git repository"

[ -n "$branch" ] || precondition "--branch is required"
[[ "$branch" =~ $REF_PATTERN ]] ||
  precondition "--branch is not a valid ref name: $branch"
[ -n "$title" ] || precondition "--title is required"
[ -n "$message_file" ] || precondition "--message-file is required"
[ -s "$message_file" ] || precondition "--message-file is missing or empty: $message_file"
[ -n "$body_file" ] || precondition "--body-file is required"
[ -s "$body_file" ] || precondition "--body-file is missing or empty: $body_file"
[ "${#files[@]}" -gt 0 ] ||
  precondition "at least one --file is required — this script never stages blindly"
for path in "${files[@]}"; do
  [ -n "$path" ] || precondition "--file needs a path"
  [ -e "$path" ] || precondition "--file does not exist: $path"
done

case "$strategy" in
  ""|merge|squash|rebase) ;;
  *) precondition "--strategy must be merge, squash, or rebase (got: $strategy)" ;;
esac

if [ -n "$base" ]; then
  [[ "$base" =~ $REF_PATTERN ]] || precondition "--base is not a valid ref name: $base"
else
  # Kept deliberately cheap; preflight.sh does the thorough detection and the caller
  # normally passes the answer straight through.
  if ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"; then
    base="${ref#refs/remotes/origin/}"
  fi
  if [ -z "$base" ]; then
    for candidate in main master; do
      if git show-ref --verify --quiet "refs/heads/$candidate"; then
        base="$candidate"
        break
      fi
    done
  fi
  [ -n "$base" ] || precondition "could not determine the base branch — pass --base"
fi

git_dir="$(cd "$(git rev-parse --absolute-git-dir)" && pwd -P)"
common_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
if [ "$git_dir" != "$common_dir" ]; then
  is_worktree=true
else
  is_worktree=false
fi
primary_worktree="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
this_worktree="$(git rev-parse --show-toplevel)"

pr_url=""
merged=false
base_synced=false
conflict_files=""
cleanup_hint=""
unstaged_reported=""

emit_result() {
  PR_URL="$pr_url" \
  BRANCH="$branch" \
  BASE="$base" \
  MERGED="$merged" \
  STRATEGY="$strategy" \
  IS_WORKTREE="$is_worktree" \
  BASE_SYNCED="$base_synced" \
  CONFLICT_FILES="$conflict_files" \
  CLEANUP_HINT="$cleanup_hint" \
  UNSTAGED_REPORTED="$unstaged_reported" \
  python3 -c '
import json, os

def lines(name):
    return [line for line in os.environ.get(name, "").splitlines() if line.strip()]

print(json.dumps({
    "pr_url": os.environ["PR_URL"],
    "branch": os.environ["BRANCH"],
    "base": os.environ["BASE"],
    "merged": os.environ["MERGED"] == "true",
    "strategy": os.environ["STRATEGY"],
    "is_worktree": os.environ["IS_WORKTREE"] == "true",
    "base_synced": os.environ["BASE_SYNCED"] == "true",
    "conflict_files": lines("CONFLICT_FILES"),
    "cleanup_hint": os.environ["CLEANUP_HINT"],
    "unstaged_reported": lines("UNSTAGED_REPORTED"),
}, indent=2))
'
}

stop() {
  # Report before exiting on a handoff — the caller needs the PR url even when blocked.
  local code="$1"
  printf 'land: %s\n' "$2" >&2
  emit_result
  exit "$code"
}

# --- branch ------------------------------------------------------------------
# In a linked worktree this is normally already the dedicated feature branch, so the
# checkout is skipped rather than special-cased.
current_branch="$(git branch --show-current)"
if [ "$current_branch" != "$branch" ]; then
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout -q "$branch"
  else
    git checkout -q -b "$branch" "$base"
  fi
fi

# --- stage exactly what was named -------------------------------------------
git add -- "${files[@]}"

# Everything still dirty after that add is something the caller chose not to ship.
unstaged_reported="$(
  git status --porcelain |
    sed -n 's/^?? //p; s/^.[^ ] //p' |
    sort -u
)"

# --- commit -----------------------------------------------------------------
if git diff --cached --quiet; then
  : # already committed on this branch — re-run, nothing new to record
else
  git commit -q -F "$message_file"
fi

# --- push -------------------------------------------------------------------
local_head="$(git rev-parse HEAD)"
remote_head=""
if git rev-parse --verify --quiet "refs/remotes/origin/$branch" > /dev/null; then
  remote_head="$(git rev-parse "refs/remotes/origin/$branch")"
fi
if [ "$local_head" != "$remote_head" ]; then
  git push -q -u origin "$branch"
fi

# --- PR ---------------------------------------------------------------------
existing="$(
  gh pr list --head "$branch" --state open --json number,url 2>/dev/null |
    python3 -c '
import json, sys
try:
    items = json.load(sys.stdin)
except Exception:
    items = []
print(items[0]["url"] if items else "")
' 2>/dev/null || true
)"

if [ -n "$existing" ]; then
  pr_url="$existing"
else
  if ! created="$(gh pr create --title "$title" --body-file "$body_file" --base "$base" 2>&1)"; then
    printf '%s\n' "$created" >&2
    stop "$EXIT_BLOCKED" "gh pr create failed"
  fi
  pr_url="$(printf '%s\n' "$created" | grep -Eo 'https://[^[:space:]]+' | tail -1 || true)"
fi

if [ "$no_merge" = true ]; then
  cleanup_hint=""
  printf 'land: PR open at %s — stopping before the merge as asked\n' "$pr_url" >&2
  emit_result
  exit 0
fi

# --- merge ------------------------------------------------------------------
if [ -z "$strategy" ]; then
  strategy="$(
    gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed 2>/dev/null |
      python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
for key, name in (
    ("mergeCommitAllowed", "merge"),
    ("squashMergeAllowed", "squash"),
    ("rebaseMergeAllowed", "rebase"),
):
    if data.get(key):
        print(name)
        break
' 2>/dev/null || true
  )"
  [ -n "$strategy" ] || strategy=merge
fi

merge_flags=("--$strategy")
# --delete-branch fails inside a linked worktree: the branch is checked out here.
if [ "$is_worktree" = false ]; then
  merge_flags+=("--delete-branch")
fi

attempt_merge() {
  gh pr merge "$branch" "${merge_flags[@]}"
}

if attempt_merge; then
  merged=true
else
  state="$(gh pr view "$branch" --json mergeStateStatus -q .mergeStateStatus 2>/dev/null || true)"
  case "$state" in
    DIRTY|BEHIND)
      # Behind or conflicting because something else landed on base first. Sync and retry;
      # never force past it.
      git fetch -q origin "$base"
      if git rebase -q "origin/$base"; then
        git push -q --force-with-lease
        if attempt_merge; then
          merged=true
        else
          stop "$EXIT_BLOCKED" "merge still refused after rebasing onto origin/$base"
        fi
      else
        conflict_files="$(git diff --name-only --diff-filter=U || true)"
        git rebase --abort || true
        stop "$EXIT_CONFLICT" \
          "rebase onto origin/$base conflicts — resolve by hand, nothing was forced"
      fi
      ;;
    *)
      stop "$EXIT_BLOCKED" "merge refused (mergeStateStatus: ${state:-unknown})"
      ;;
  esac
fi

# --- land back on the base branch -------------------------------------------
if [ "$is_worktree" = true ]; then
  # git refuses to check out a branch already checked out elsewhere, so update the
  # primary copy instead of this worktree, and never remove the worktree we stand in.
  if [ -n "$primary_worktree" ] && [ "$primary_worktree" != "$this_worktree" ]; then
    if [ "$(git -C "$primary_worktree" branch --show-current)" = "$base" ] &&
      [ -z "$(git -C "$primary_worktree" status --porcelain)" ]; then
      git -C "$primary_worktree" pull -q --ff-only || true
    else
      git -C "$primary_worktree" fetch -q origin "$base" || true
    fi
  else
    git fetch -q origin "$base" || true
  fi
  cleanup_hint="run from $primary_worktree: git worktree remove $this_worktree && git branch -d $branch"
else
  git checkout -q "$base"
  git pull -q --ff-only || true
fi

sync_root="$this_worktree"
if [ "$is_worktree" = true ] && [ -n "$primary_worktree" ]; then
  sync_root="$primary_worktree"
fi
if [ "$(git -C "$sync_root" rev-parse "$base" 2>/dev/null || true)" = \
  "$(git -C "$sync_root" rev-parse "origin/$base" 2>/dev/null || true)" ]; then
  base_synced=true
fi

emit_result
