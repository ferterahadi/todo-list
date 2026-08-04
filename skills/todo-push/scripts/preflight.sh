#!/usr/bin/env bash
# Read-only repo reconnaissance for /todo-push. Emits one JSON object describing the
# facts the skill would otherwise re-derive in prose, and fails before anything mutates
# when the ship can't work (no origin, no gh auth, no write access, nothing to ship).
#
# usage: preflight.sh          # operates on the current working directory's repo
set -euo pipefail

die() {
  # Machine-readable on stdout, human-readable on stderr, non-zero either way.
  printf '{"error": "%s"}\n' "$1"
  printf 'preflight: %s\n' "$1" >&2
  exit 1
}

git rev-parse --git-dir > /dev/null 2>&1 || die "not a git repository"

git_dir="$(cd "$(git rev-parse --absolute-git-dir)" && pwd -P)"
common_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
if [ "$git_dir" != "$common_dir" ]; then
  is_worktree=true
else
  is_worktree=false
fi

repo_root="$(git rev-parse --show-toplevel)"
primary_worktree="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
current_branch="$(git branch --show-current)"

git remote get-url origin > /dev/null 2>&1 ||
  die "no origin remote — nothing to push to (git remote -v)"

gh auth status > /dev/null 2>&1 ||
  die "gh auth failed — authenticate before shipping (gh auth status)"

# Being logged in proves only that *some* account is active. When that account has no write
# access to this repo, `gh pr create` fails with "must be a collaborator" — by which point
# land.sh has already branched, committed and pushed. Resolve the permission here instead,
# while nothing has moved, and fail closed if it can't be read.
# "Logged in to github.com account <login> (keyring)" — match the field, not a substring:
# a login can itself end in "account".
gh_account="$(gh auth status --active 2>/dev/null |
  awk '{for (i = 1; i < NF; i++) if ($i == "account") { print $(i + 1); exit }}')"
[ -n "$gh_account" ] || gh_account="unknown"

access_facts="$(
  gh repo view --json nameWithOwner,viewerPermission 2>/dev/null |
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
print(data.get("nameWithOwner") or "")
print((data.get("viewerPermission") or "").upper())
' 2>/dev/null || true
)"
repo_slug="$(printf '%s\n' "$access_facts" | sed -n 1p)"
viewer_permission="$(printf '%s\n' "$access_facts" | sed -n 2p)"
[ -n "$repo_slug" ] || repo_slug="$(git remote get-url origin)"

case "$viewer_permission" in
  ADMIN | MAINTAIN | WRITE) ;;
  "")
    die "could not read the gh account's permission on $repo_slug — active account is \
$gh_account; confirm it has access, or switch (gh auth switch)"
    ;;
  *)
    die "gh account $gh_account has $viewer_permission access to $repo_slug — the PR could \
not be opened after the branch was pushed; switch accounts (gh auth switch) and re-run"
    ;;
esac

# Base branch: the remote's default, then the remote's own report, then convention.
base=""
if ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"; then
  base="${ref#refs/remotes/origin/}"
fi
if [ -z "$base" ]; then
  base="$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' | head -1)"
fi
if [ -z "$base" ] || [ "$base" = "(unknown)" ]; then
  for candidate in main master; do
    if git show-ref --verify --quiet "refs/heads/$candidate"; then
      base="$candidate"
      break
    fi
  done
fi
[ -n "$base" ] || die "could not determine the base branch"

# -uall lists untracked files individually; the collapsed "dir/" form can't be handed to
# land.sh --file, which is the whole point of reporting them.
porcelain="$(git status --porcelain -uall)"
changed_list="$(printf '%s\n' "$porcelain" | sed -n 's/^[^?][^?] //p; s/^?? //p' | sort -u)"
[ -n "$porcelain" ] || changed_list=""

# Untracked files that look like build output or local scratch rather than deliverables.
# Reported so the caller leaves them out of --file deliberately; never removed here.
suspicious=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in
    .DS_Store|*/.DS_Store|*.tfplan|*.tfstate|*.tfstate.backup|*.swp|*.swo|*~|*.orig|\
    *.rej|*.pyc|*.log|node_modules/*|dist/*|build/*|target/*|__pycache__/*|\
    .pytest_cache/*|coverage/*|.terraform/*)
      suspicious="${suspicious}${path}"$'\n'
      ;;
  esac
done <<< "$(printf '%s\n' "$porcelain" | sed -n 's/^?? //p')"

if [ -n "$porcelain" ]; then
  dirty=true
else
  dirty=false
fi

ahead_of_base=0
if git show-ref --verify --quiet "refs/heads/$base" && [ "$current_branch" != "$base" ]; then
  ahead_of_base="$(git rev-list --count "$base..HEAD" 2>/dev/null || printf '0')"
fi

if [ "$dirty" = false ] && [ "$ahead_of_base" -eq 0 ]; then
  die "nothing to ship — the tree is clean and no commits sit ahead of $base"
fi

# Merge strategies the repo itself allows, rather than inferred from recent PRs.
strategies="$(
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
' 2>/dev/null || true
)"

# What the repo *allows* is not what it *does*: a repo can permit merge commits and still
# squash every PR. Report the recent pattern so the caller can pass --strategy deliberately.
recent_merges=0
recent_total=0
if git show-ref --verify --quiet "refs/heads/$base"; then
  read -r recent_total recent_merges <<< "$(
    git log --first-parent --max-count=10 --format=%p "$base" 2>/dev/null |
      awk 'NF>1{m++} {t++} END{printf "%d %d", t+0, m+0}'
  )"
fi
if [ "$recent_total" -gt 0 ] && [ $((recent_merges * 2)) -gt "$recent_total" ]; then
  observed_pattern=merge
else
  observed_pattern=linear
fi

# What the repo declares as its test command. Choosing and scoping stays with the caller.
candidates=""
add_candidate() {
  candidates="${candidates}${1}=${2}"$'\n'
}
if [ -f "$repo_root/Makefile" ] && grep -Eq '^test:' "$repo_root/Makefile"; then
  add_candidate makefile "make test"
fi
if [ -f "$repo_root/package.json" ] &&
  python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
raise SystemExit(0 if "test" in data.get("scripts", {}) else 1)
' "$repo_root/package.json" 2>/dev/null; then
  add_candidate package_json "npm test"
fi
if [ -f "$repo_root/Cargo.toml" ]; then
  add_candidate cargo "cargo test"
fi
if [ -f "$repo_root/go.mod" ]; then
  add_candidate go "go test ./..."
fi
if [ -f "$repo_root/pytest.ini" ] || [ -f "$repo_root/tox.ini" ] ||
  { [ -f "$repo_root/pyproject.toml" ] && grep -q pytest "$repo_root/pyproject.toml"; }; then
  add_candidate pytest "pytest"
fi
if [ -d "$repo_root/tests" ] &&
  [ -n "$(find "$repo_root/tests" -maxdepth 1 -name '*.sh' -print -quit 2>/dev/null)" ]; then
  add_candidate shell_tests "bash tests/*.sh"
fi
for doc in AGENTS.md CLAUDE.md README.md; do
  if [ -f "$repo_root/$doc" ] && grep -qi 'test' "$repo_root/$doc"; then
    add_candidate "${doc%%.md}_md" "see $doc"
  fi
done

REPO_ROOT="$repo_root" \
IS_WORKTREE="$is_worktree" \
PRIMARY_WORKTREE="$primary_worktree" \
BASE="$base" \
CURRENT_BRANCH="$current_branch" \
GH_ACCOUNT="$gh_account" \
VIEWER_PERMISSION="$viewer_permission" \
REPO_SLUG="$repo_slug" \
DIRTY="$dirty" \
AHEAD_OF_BASE="$ahead_of_base" \
CHANGED_FILES="$changed_list" \
SUSPICIOUS="$suspicious" \
STRATEGIES="$strategies" \
OBSERVED_PATTERN="$observed_pattern" \
RECENT_MERGES="$recent_merges" \
RECENT_TOTAL="$recent_total" \
CANDIDATES="$candidates" \
python3 -c '
import json, os

def lines(name):
    return [line for line in os.environ.get(name, "").splitlines() if line.strip()]

candidates = {}
for line in lines("CANDIDATES"):
    key, _, value = line.partition("=")
    candidates[key] = value

print(json.dumps({
    "repo_root": os.environ["REPO_ROOT"],
    "is_worktree": os.environ["IS_WORKTREE"] == "true",
    "primary_worktree": os.environ["PRIMARY_WORKTREE"],
    "base": os.environ["BASE"],
    "current_branch": os.environ["CURRENT_BRANCH"],
    "dirty": os.environ["DIRTY"] == "true",
    "ahead_of_base": int(os.environ["AHEAD_OF_BASE"]),
    "changed_files": lines("CHANGED_FILES"),
    "untracked_suspicious": lines("SUSPICIOUS"),
    "gh_auth": True,
    "gh_account": os.environ["GH_ACCOUNT"],
    "viewer_permission": os.environ["VIEWER_PERMISSION"],
    "repo_slug": os.environ["REPO_SLUG"],
    "has_origin": True,
    "allowed_merge_strategies": lines("STRATEGIES"),
    "observed_merge_pattern": os.environ["OBSERVED_PATTERN"],
    "recent_merge_commits": int(os.environ["RECENT_MERGES"]),
    "recent_commits_sampled": int(os.environ["RECENT_TOTAL"]),
    "test_cmd_candidates": candidates,
}, indent=2))
'
