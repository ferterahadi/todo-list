#!/usr/bin/env bash
# The deterministic half of /todo-push: branch, stage, commit, push, open the PR, merge it,
# land back on the base branch. Every judgment call (branch name, which files, the message,
# the PR body) arrives as an argument — this script makes none of them.
#
# usage:
#   land.sh --branch <name> --title <text> --body-file <path> \
#           [--message-file <path> --file <path> [--file <path>...]] \
#           [--base <name>] [--no-merge] [--strategy merge|squash|rebase]
#   land.sh --merge-existing --branch <name> [--base <name>] [--strategy merge|squash|rebase]
#
# Ship mode branches off the current HEAD, so commits the checkout already carries ship too.
# --file paths are repo-root-relative, as preflight.sh reports them; a rename is both paths.
# Only the named paths are committed — anything else already staged stays staged. With no
# --file, the commits HEAD already carries beyond origin/<base> ship on their own.
#
# --merge-existing is for a merge queue: run it on the checkout of a branch whose PR is
# already open. It rebases that branch onto origin/<base> (autostashing unrelated local
# changes), pushes it with --force-with-lease, and merges the PR. It never deletes the
# branch and never switches the checkout to the base.
#
# Without --strategy, both modes pick one the way preflight.sh does: the repo's recent
# merge pattern, limited to what the repo allows (one `gh repo view`).
#
# stdout is one JSON object on every exit (--help aside); git and gh output goes to stderr.
# exit codes:
#   0   merged and landed (with --no-merge: the PR is open)
#   10  the PR is open but the merge is blocked (protection, review) — reported, not forced
#   11  the rebase onto origin/<base> hit a real conflict — aborted, branch and PR unchanged
#   12  precondition failed (bad argument, missing file, no open PR) — nothing was mutated
#   13  the branch was pushed but `gh pr create` failed — no PR exists
#   14  a step failed after mutation began — `failed_step`, `done` and `error` say where
#
# Every step is skipped when its effect is already present, so re-running with identical
# arguments after fixing a problem is safe — including after a conflict was resolved by
# hand: the rebased branch is pushed with a lease on the tip it replaces.
set -Eeuo pipefail

# The JSON result is the only thing on stdout; everything else goes to stderr.
exec 3>&1 1>&2

readonly EXIT_BLOCKED=10
readonly EXIT_CONFLICT=11
readonly EXIT_PRECONDITION=12
readonly EXIT_PR_CREATE=13
readonly EXIT_STEP_FAILED=14

# Anything that becomes part of a git command is validated, never interpolated on trust.
readonly REF_PATTERN='^[A-Za-z0-9._/-]+$'
# A --file is a literal path — never a glob or pathspec magic such as ':(exclude)'.
export GIT_LITERAL_PATHSPECS=1

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

mode=ship
branch=""
base=""
title=""
message_file=""
body_file=""
strategy=""
no_merge=false
ship_only_flag=""
files=()

pr_url=""
merged=false
is_worktree=false
base_synced=false
force_pushed=false
carried_commits=0
commit_sha=""
conflict_files=""
dirty_files=""
staged_not_named=""
unstaged_reported=""
cleanup_hint=""
done_steps=""
step=validate
failed_step=""
error=""
last_command=""
emitted=false

emit_result() {
  emitted=true
  MODE="$mode" \
  PR_URL="$pr_url" \
  BRANCH="$branch" \
  BASE="$base" \
  STRATEGY="$strategy" \
  MERGED="$merged" \
  IS_WORKTREE="$is_worktree" \
  BASE_SYNCED="$base_synced" \
  FORCE_PUSHED="$force_pushed" \
  CARRIED_COMMITS="$carried_commits" \
  COMMIT_SHA="$commit_sha" \
  DONE_STEPS="$done_steps" \
  FAILED_STEP="$failed_step" \
  ERROR="$error" \
  CONFLICT_FILES="$conflict_files" \
  DIRTY_FILES="$dirty_files" \
  STAGED_NOT_NAMED="$staged_not_named" \
  UNSTAGED_REPORTED="$unstaged_reported" \
  CLEANUP_HINT="$cleanup_hint" \
  python3 -c '
import json, os

def lines(name):
    return [line for line in os.environ.get(name, "").splitlines() if line.strip()]

print(json.dumps({
    "mode": os.environ["MODE"],
    "pr_url": os.environ["PR_URL"],
    "branch": os.environ["BRANCH"],
    "base": os.environ["BASE"],
    "strategy": os.environ["STRATEGY"],
    "merged": os.environ["MERGED"] == "true",
    "done": lines("DONE_STEPS"),
    "failed_step": os.environ["FAILED_STEP"],
    "error": os.environ["ERROR"],
    "commit": os.environ["COMMIT_SHA"],
    "carried_commits": int(os.environ["CARRIED_COMMITS"] or 0),
    "force_pushed": os.environ["FORCE_PUSHED"] == "true",
    "is_worktree": os.environ["IS_WORKTREE"] == "true",
    "base_synced": os.environ["BASE_SYNCED"] == "true",
    "conflict_files": lines("CONFLICT_FILES"),
    "dirty_files": lines("DIRTY_FILES"),
    "staged_not_named": lines("STAGED_NOT_NAMED"),
    "unstaged_reported": lines("UNSTAGED_REPORTED"),
    "cleanup_hint": os.environ["CLEANUP_HINT"],
}, indent=2))
' >&3
}

# Any exit that did not report on purpose (set -e tripping on a git or gh failure) still
# prints the JSON, with how far the run got, and maps to one documented exit code.
trap 'last_command="$BASH_COMMAND"' ERR
on_exit() {
  local code=$?
  [ "$emitted" = false ] || return 0
  failed_step="$step"
  error="${error:-$step failed (exit $code)${last_command:+: $last_command} — see stderr}"
  emit_result
  # Still validating means nothing has moved yet.
  if [ "$step" = validate ]; then
    exit "$EXIT_PRECONDITION"
  fi
  exit "$EXIT_STEP_FAILED"
}
trap on_exit EXIT

mark_done() {
  done_steps="${done_steps}$1"$'\n'
}

precondition() {
  failed_step=validate
  error="$1"
  printf 'land: %s\n' "$1" >&2
  emit_result
  exit "$EXIT_PRECONDITION"
}

stop() {
  # Report before exiting on a handoff — the caller needs the PR url even when blocked.
  failed_step="$step"
  error="$2"
  printf 'land: %s\n' "$2" >&2
  emit_result
  exit "$1"
}

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' \
    "${BASH_SOURCE[0]}" >&3
  emitted=true
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --merge-existing) mode=merge-existing; shift; continue ;;
    --no-merge) no_merge=true; ship_only_flag="${ship_only_flag:-$1}"; shift; continue ;;
    -h|--help) usage ;;
    --branch|--base|--strategy|--title|--message-file|--body-file|--file)
      [ $# -ge 2 ] || precondition "$1 needs a value"
      ;;
    *) precondition "unknown argument: $1" ;;
  esac
  case "$1" in
    --branch) branch="$2" ;;
    --base) base="$2" ;;
    --strategy) strategy="$2" ;;
    --title) title="$2" ;;
    --message-file) message_file="$2" ;;
    --body-file) body_file="$2" ;;
    --file) files+=("$2") ;;
  esac
  case "$1" in
    --title|--message-file|--body-file|--file) ship_only_flag="${ship_only_flag:-$1}" ;;
  esac
  shift 2
done

git rev-parse --git-dir > /dev/null 2>&1 || precondition "not a git repository"

valid_ref() {
  [[ "$1" =~ $REF_PATTERN ]] && [[ "$1" != -* ]]
}

[ -n "$branch" ] || precondition "--branch is required"
valid_ref "$branch" || precondition "--branch is not a valid ref name: $branch"
case "$strategy" in
  ""|merge|squash|rebase) ;;
  *) precondition "--strategy must be merge, squash, or rebase (got: $strategy)" ;;
esac

absolute() {
  printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"
}

if [ "$mode" = merge-existing ]; then
  [ -z "$ship_only_flag" ] ||
    precondition "$ship_only_flag does not apply to --merge-existing — it merges the PR already open"
else
  [ -n "$title" ] || precondition "--title is required"
  [ -n "$body_file" ] || precondition "--body-file is required"
  [ -s "$body_file" ] || precondition "--body-file is missing or empty: $body_file"
  body_file="$(absolute "$body_file")"
  if [ "${#files[@]}" -gt 0 ]; then
    [ -n "$message_file" ] || precondition "--message-file is required with --file"
    [ -s "$message_file" ] || precondition "--message-file is missing or empty: $message_file"
    message_file="$(absolute "$message_file")"
  fi
fi

# --file paths are repo-root-relative, as preflight.sh reports them.
repo_top="$(git rev-parse --show-toplevel)"
cd "$repo_top"

if [ -n "$base" ]; then
  valid_ref "$base" || precondition "--base is not a valid ref name: $base"
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
[ "$branch" != "$base" ] || precondition "--branch and --base are the same branch ($base)"

# A half-finished rebase, merge or cherry-pick is the user's to finish, not this script's.
for marker in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  if [ -e "$(git rev-parse --git-path "$marker")" ]; then
    case "$marker" in
      rebase-*) what=rebase ;;
      MERGE_HEAD) what=merge ;;
      CHERRY_PICK_HEAD) what=cherry-pick ;;
      *) what=revert ;;
    esac
    precondition "a $what is in progress — finish or abort it, then re-run"
  fi
done

git_dir="$(cd "$(git rev-parse --absolute-git-dir)" && pwd -P)"
common_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
if [ "$git_dir" != "$common_dir" ]; then
  is_worktree=true
fi
primary_worktree="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
this_worktree="$repo_top"
current_branch="$(git branch --show-current)"

compare_ref=""
if git rev-parse --verify --quiet "refs/remotes/origin/$base" > /dev/null; then
  compare_ref="origin/$base"
elif git show-ref --verify --quiet "refs/heads/$base"; then
  compare_ref="$base"
fi
if [ -n "$compare_ref" ]; then
  carried_commits="$(git rev-list --count "$compare_ref..HEAD")"
fi

tracked_or_present() {
  [ -e "$1" ] || [ -L "$1" ] ||
    git cat-file -e "HEAD:$1" 2> /dev/null ||
    [ -n "$(git ls-files -- "$1")" ]
}

if [ "$mode" = ship ]; then
  for path in ${files[@]+"${files[@]}"}; do
    [ -n "$path" ] || precondition "--file needs a path"
    case "/$path/" in
      //*|*/../*) precondition "--file must be a repo-relative path: $path" ;;
    esac
    tracked_or_present "$path" ||
      precondition "--file is neither on disk nor tracked: $path"
  done
  if [ "${#files[@]}" -eq 0 ] && [ "$carried_commits" -eq 0 ]; then
    precondition "nothing to ship — no --file named and HEAD has no commits beyond ${compare_ref:-$base}"
  fi
  if [ "${#files[@]}" -gt 0 ] && [ "$carried_commits" -eq 0 ] &&
    [ -z "$(git status --porcelain --untracked-files=all -- "${files[@]}")" ]; then
    precondition "nothing to ship — the named files have no changes and HEAD has no commits beyond ${compare_ref:-$base}"
  fi
  # Switching to an existing branch that lacks the current HEAD would strand the commits
  # this checkout carries — exactly the silent omission --branch must never cause.
  if [ "$current_branch" != "$branch" ] &&
    git show-ref --verify --quiet "refs/heads/$branch" &&
    ! git merge-base --is-ancestor HEAD "refs/heads/$branch"; then
    precondition "branch $branch already exists without the current HEAD — switching would leave commits behind; pick another --branch"
  fi
else
  [ "$current_branch" = "$branch" ] ||
    precondition "--merge-existing runs on the branch's own checkout; this one is on ${current_branch:-a detached HEAD}"
fi

find_open_pr() {
  gh pr list --head "$branch" --state open --json number,url |
    python3 -c '
import json, sys
items = json.load(sys.stdin)
print(items[0]["url"] if items else "")
'
}

if [ "$mode" = merge-existing ]; then
  step=pr
  pr_url="$(find_open_pr)" || precondition "could not list the PRs for $branch (gh pr list)"
  [ -n "$pr_url" ] || precondition "no open PR for $branch — ship it first"
fi

# --- helpers shared by both modes -------------------------------------------

# Push this branch, and only this branch. A fast-forward is a plain push. A tip the rebase
# rewrote is replaced with --force-with-lease pinned to that exact old tip, and only when
# this branch once held it (its reflog) — a commit someone else pushed is never overwritten.
push_branch() {
  local local_sha remote_sha refspec held
  refspec="refs/heads/$branch:refs/heads/$branch"
  local_sha="$(git rev-parse HEAD)"
  remote_sha="$(
    git ls-remote --heads origin "refs/heads/$branch" |
      awk -v ref="refs/heads/$branch" '$2 == ref { print $1 }'
  )"
  held=$'\n'"$(git reflog show --format=%H "refs/heads/$branch" 2> /dev/null || true)"$'\n'
  if [ "$remote_sha" = "$local_sha" ]; then
    :
  elif [ -z "$remote_sha" ] || git merge-base --is-ancestor "$remote_sha" HEAD 2> /dev/null; then
    git push -q -u origin "$refspec"
  elif [[ "$held" == *$'\n'"$remote_sha"$'\n'* ]]; then
    git push -q -u --force-with-lease="refs/heads/$branch:$remote_sha" origin "$refspec"
    force_pushed=true
  else
    stop "$EXIT_STEP_FAILED" \
      "origin/$branch holds commits this clone never had — not overwriting them; inspect origin/$branch"
  fi
}

# Rebase onto origin/<base>. Unrelated local changes ride along via --autostash; a local
# change to a file that also changed on base could not be re-applied cleanly, so it stops
# the rebase before it starts rather than leaving conflict markers in the user's files.
rebase_onto_base() {
  step=rebase
  git fetch -q origin "$base"
  dirty_files="$(
    {
      git diff --name-only -z HEAD..."origin/$base"
      status_paths changed | tr '\n' '\0'
    } | python3 -c '
import sys
parts = sys.stdin.buffer.read().split(b"\0")
seen, overlap = set(), set()
for part in parts:
    if part in seen:
        overlap.add(part)
    seen.add(part)
for path in sorted(overlap):
    if path:
        sys.stdout.buffer.write(path + b"\n")
'
  )"
  if [ -n "$dirty_files" ]; then
    stop "$EXIT_STEP_FAILED" \
      "uncommitted changes to files that also changed on origin/$base block the rebase — commit, ship, or move them aside, then re-run"
  fi
  if git rebase -q --autostash "origin/$base"; then
    mark_done rebase
    return 0
  fi
  if [ -d "$(git rev-parse --git-path rebase-merge)" ] ||
    [ -d "$(git rev-parse --git-path rebase-apply)" ]; then
    conflict_files="$(git diff --name-only --diff-filter=U || true)"
    git rebase --abort
    cleanup_hint="to resolve by hand: git rebase origin/$base, fix the conflict_files, git add them, git rebase --continue — then re-run the same land.sh; it pushes the rebased branch with --force-with-lease"
    stop "$EXIT_CONFLICT" "rebase onto origin/$base conflicts — aborted, nothing was forced"
  fi
  stop "$EXIT_STEP_FAILED" "the rebase onto origin/$base could not start — see stderr"
}

resolve_strategy() {
  [ -z "$strategy" ] || return 0
  local allowed history_ref pattern
  allowed="$(
    gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed 2> /dev/null |
      allowed_strategies 2> /dev/null || true
  )"
  history_ref="origin/$base"
  if git show-ref --verify --quiet "refs/heads/$base"; then
    history_ref="$base"
  fi
  read -r pattern _ <<< "$(merge_history "$history_ref")"
  strategy="$(pick_merge_strategy "$pattern" "$allowed")"
}

# Merge the PR. Behind or conflicting because something else landed on base first: sync
# once and retry; never force past it.
merge_pr() {
  step=merge
  resolve_strategy
  local merge_flags=("--$strategy")
  # --delete-branch fails inside a linked worktree (the branch is checked out there), and a
  # merge queue keeps its branches until its own cleanup.
  if [ "$mode" = ship ] && [ "$is_worktree" = false ]; then
    merge_flags+=("--delete-branch")
  fi
  if gh pr merge "$branch" "${merge_flags[@]}"; then
    merged=true
  else
    local state
    state="$(gh pr view "$branch" --json mergeStateStatus -q .mergeStateStatus 2> /dev/null || true)"
    case "$state" in
      DIRTY|BEHIND)
        rebase_onto_base
        step=push
        push_branch
        step=merge
        if gh pr merge "$branch" "${merge_flags[@]}"; then
          merged=true
        else
          stop "$EXIT_BLOCKED" "merge still refused after rebasing onto origin/$base"
        fi
        ;;
      *)
        stop "$EXIT_BLOCKED" "merge refused (mergeStateStatus: ${state:-unknown})"
        ;;
    esac
  fi
  mark_done merge
}

# Bring the base branch up to date. In a linked worktree git refuses to check out a branch
# already checked out elsewhere, so the primary copy is updated instead, and the worktree
# stood in is never removed. The merge already happened, so nothing here fails the run.
land_on_base() {
  step=land
  if [ "$is_worktree" = true ]; then
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
    # A squash or rebase merge leaves the branch tip unreachable from base, so -d refuses it;
    # the PR is already merged, so -D deletes nothing unshipped.
    local delete_flag=-d
    [ "$strategy" = merge ] || delete_flag=-D
    cleanup_hint="run from $primary_worktree: git worktree remove $this_worktree && git branch $delete_flag $branch"
  elif [ "$mode" = merge-existing ]; then
    git fetch -q origin "$base" || true
  elif git checkout -q "$base"; then
    git pull -q --ff-only || true
  else
    cleanup_hint="merged, but this checkout could not switch back to $base (see stderr) — run: git checkout $base && git pull --ff-only"
  fi

  local sync_root="$this_worktree"
  if [ "$is_worktree" = true ] && [ -n "$primary_worktree" ]; then
    sync_root="$primary_worktree"
  fi
  if [ "$(git -C "$sync_root" rev-parse "$base" 2>/dev/null || true)" = \
    "$(git -C "$sync_root" rev-parse "origin/$base" 2>/dev/null || true)" ]; then
    base_synced=true
  fi
  mark_done land
}

# --- merge an existing PR ---------------------------------------------------
if [ "$mode" = merge-existing ]; then
  mark_done branch
  mark_done pr
  unstaged_reported="$(status_paths changed)"
  rebase_onto_base
  step=push
  push_branch
  mark_done push
  merge_pr
  land_on_base
  emit_result
  exit 0
fi

# --- branch ------------------------------------------------------------------
# A new branch starts at the current HEAD, so commits already on this checkout ship with it.
# In a linked worktree this is normally already the dedicated feature branch.
step=branch
if [ "$current_branch" != "$branch" ]; then
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout -q "$branch"
  else
    git checkout -q -b "$branch"
  fi
fi
mark_done branch

# --- commit exactly what was named ------------------------------------------
if [ "${#files[@]}" -gt 0 ]; then
  step=commit
  # Staged before this run and not named: reported, left staged, and never committed.
  staged_not_named="$(
    status_paths staged | python3 -c '
import sys
named = {arg.encode("utf-8", "surrogateescape") for arg in sys.argv[1:]}
for line in sys.stdin.buffer.read().splitlines():
    if line and line not in named:
        sys.stdout.buffer.write(line + b"\n")
' "${files[@]}"
  )"
  # A path gone from both disk and index (the old side of a staged rename) has nothing to
  # add; the commit below still records it.
  addable=()
  for path in "${files[@]}"; do
    if [ -e "$path" ] || [ -L "$path" ] || [ -n "$(git ls-files -- "$path")" ]; then
      addable+=("$path")
    fi
  done
  if [ "${#addable[@]}" -gt 0 ]; then
    git add -- "${addable[@]}"
  fi
  # `git commit -- <paths>` commits those paths only, whatever else sits in the index.
  if ! git diff --cached --quiet HEAD -- "${files[@]}"; then
    git commit -q -F "$message_file" -- "${files[@]}"
    commit_sha="$(git rev-parse HEAD)"
  fi
  mark_done commit
fi

# Everything still uncommitted is something the caller chose not to ship.
unstaged_reported="$(status_paths changed)"

# --- push -------------------------------------------------------------------
step=push
push_branch
mark_done push

# --- PR ---------------------------------------------------------------------
step=pr
pr_url="$(find_open_pr)"
if [ -z "$pr_url" ]; then
  if ! created="$(gh pr create --title "$title" --body-file "$body_file" --base "$base" 2>&1)"; then
    printf '%s\n' "$created" >&2
    stop "$EXIT_PR_CREATE" \
      "the branch is pushed, but gh pr create failed: $(printf '%s\n' "$created" | tail -1)"
  fi
  pr_url="$(printf '%s\n' "$created" | grep -Eo 'https://[^[:space:]]+' | tail -1 || true)"
fi
mark_done pr

if [ "$no_merge" = true ]; then
  printf 'land: PR open at %s — stopping before the merge as asked\n' "$pr_url" >&2
  emit_result
  exit 0
fi

# --- merge, then land back on the base branch --------------------------------
merge_pr
land_on_base
emit_result
