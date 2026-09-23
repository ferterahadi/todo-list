#!/usr/bin/env bash
# Contract test for the state/context skills' deterministic repo evidence.
# Drives skills/todo-state/scripts/repo-evidence.sh against scratch repos with a local bare
# remote and a stubbed `gh`, so nothing here touches GitHub or a real hub. It proves the
# helper validates every input before running anything, derives owner/name and base from
# the repo, fetches at most once, attributes branches/worktrees/PRs without collapsing
# `api` into `api-v2`, detects merge / rebase / squash / PR merges, reports uncommitted
# work, keeps `unknown` distinct from `absent`, and writes nothing without --fetch.
# It also pins the skill text to the shared helpers so per-project counting, phantom-task
# greps, and unrunnable repo commands cannot creep back.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$repo_root/skills/todo-state/scripts/repo-evidence.sh"
bash_bin="$(command -v bash)"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

expect_equal() {
  if [ "$3" != "$2" ]; then
    printf 'not ok - %s\nexpected: %s\nactual:   %s\n' "$1" "$2" "$3" >&2
    exit 1
  fi
}

expect_contains() {
  case "$2" in
    *"$3"*) ;;
    *) printf 'not ok - %s\nexpected to contain: %s\nactual:\n%s\n' "$1" "$3" "$2" >&2; exit 1 ;;
  esac
}

expect_lacks() {
  case "$2" in
    *"$3"*) printf 'not ok - %s\nmust not contain: %s\nactual:\n%s\n' "$1" "$3" "$2" >&2; exit 1 ;;
  esac
}

[ -f "$helper" ] || fail "repo-evidence helper is missing"

work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$work"' EXIT

run() {
  run_code=0
  "$@" > "$work/run.out" 2> "$work/run.err" || run_code=$?
  run_out="$(cat "$work/run.out")"
}

# The SUMMARY row for one project, fields after the project column.
summary_of() {
  printf '%s\n' "$run_out" |
    awk -F '\t' -v p="project=$1" '$1 == "SUMMARY" && $3 == p { $1 = $2 = $3 = ""; sub(/^[ \t]+/, ""); print }' OFS=' '
}

branch_row() {
  printf '%s\n' "$run_out" |
    awk -F '\t' -v p="$1" -v b="$2" '$1 == "BRANCH" && $2 == p && $3 == b { $1 = $2 = $3 = ""; sub(/^[ \t]+/, ""); print }' OFS=' '
}

# ---------------------------------------------------------------------------
# Sandbox PATH: real tools plus logging `git` and a stub `gh`.
# ---------------------------------------------------------------------------
real_git="$(command -v git)"
tools="$work/tools"
mkdir -p "$tools"
for tool in awk sed sort mktemp rm tail tr cat python3; do
  ln -s "$(command -v "$tool")" "$tools/$tool"
done
cat > "$tools/git" <<STUB
#!$bash_bin
printf '%s\n' "\$*" >> "\${GIT_LOG:-/dev/null}"
exec "$real_git" "\$@"
STUB
chmod +x "$tools/git"

gh_bin="$work/gh-bin"
mkdir -p "$gh_bin"
printf '#!%s\n' "$bash_bin" > "$gh_bin/gh"
cat >> "$gh_bin/gh" <<'STUB'
printf '%s\n' "$*" >> "${GH_STUB_LOG:?GH_STUB_LOG unset}"
case "${1:-} ${2:-}" in
  "pr list")
    [ "${GH_STUB_FAIL:-no}" = yes ] && { echo "not logged in" >&2; exit 1; }
    printf '%s\n' "${GH_STUB_PR_LIST:-[]}"
    ;;
  *) echo "gh stub: unhandled: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$gh_bin/gh"

export GH_STUB_LOG="$work/gh.log" GIT_LOG="$work/git.log"
export GIT_CONFIG_GLOBAL="$work/gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL"
with_gh="$tools:$gh_bin"
without_gh="$tools"

evidence() {
  # $1 PATH; rest: helper arguments.
  local path="$1"
  shift
  PATH="$path" run "$bash_bin" "$helper" "$@"
}

# ---------------------------------------------------------------------------
# Fixture: bare remote + clone whose origin URL looks like GitHub.
# ---------------------------------------------------------------------------
git init -q --bare -b main "$work/remote.git"
git clone -q "$work/remote.git" "$work/seed" 2> /dev/null
g() { git -C "$work/seed" -c user.email=t@example.com -c user.name=t "$@"; }
echo base > "$work/seed/base.txt"
g add base.txt
g commit -qm "base"
g push -q origin main

repo="$work/demo"
git clone -q "$work/remote.git" "$repo" 2> /dev/null
r() { git -C "$repo" -c user.email=t@example.com -c user.name=t "$@"; }
r remote set-url origin https://github.com/acme/demo.git
r config "url.$work/remote.git.insteadOf" https://github.com/acme/demo.git
r fetch -q origin

commit_file() {
  # $1 file, $2 content, $3 message
  printf '%s\n' "$2" > "$repo/$1"
  r add "$1"
  r commit -qm "$3"
}

# api: merged with a merge commit.
r checkout -qb todo/api origin/main
commit_file api.txt "api" "api work"
r checkout -q main
r merge -q --no-ff todo/api -m "Merge todo/api"

# rebased: its commit is replayed onto main (same patch, new SHA).
r checkout -qb todo/rebased origin/main
commit_file rebased.txt "rebased" "rebased work"
r checkout -q main
r cherry-pick todo/rebased > /dev/null

# squashy: two commits squashed into one on main.
r checkout -qb todo/squashy origin/main
commit_file squash-a.txt "a" "squash a"
commit_file squash-b.txt "b" "squash b"
r checkout -q main
r merge -q --squash todo/squashy > /dev/null 2>&1
r commit -qm "Squashy (#7)"
r push -q origin main

# api-v2: two unshipped commits in its worktree, plus uncommitted work.
r branch -q todo/api-v2 origin/main
r worktree add -q "$repo-wt/api-v2" todo/api-v2
w() { git -C "$repo-wt/api-v2" -c user.email=t@example.com -c user.name=t "$@"; }
echo one > "$repo-wt/api-v2/v2.txt"
w add v2.txt
w commit -qm "v2 one"
echo two >> "$repo-wt/api-v2/v2.txt"
w commit -qam "v2 two"
echo dirty >> "$repo-wt/api-v2/v2.txt"
echo new > "$repo-wt/api-v2/untracked.txt"
# A feature branch that merely starts with "api-" must go to api-v2, never api.
r branch -q feat/api-v2-extra todo/api-v2

# fresh: worktree exists, branch has no commits of its own.
r worktree add -q -b todo/fresh "$repo-wt/fresh" origin/main

# parallel: a parallel-mode worktree whose folder is not the short-name.
r worktree add -q -b feat/parallel-login "$repo-wt/login" origin/main
echo login > "$repo-wt/login/login.txt"
git -C "$repo-wt/login" add login.txt
git -C "$repo-wt/login" -c user.email=t@example.com -c user.name=t commit -qm "login"

# gone: a worktree whose folder was deleted.
r worktree add -q -b todo/gone "$repo-wt/gone" origin/main
rm -rf "$repo-wt/gone"

# prmerged: local commits GitHub merged, but the merge is not in local main.
r checkout -qb todo/prmerged origin/main
commit_file prmerged.txt "pr" "pr merged work"
prmerged_oid="$(r rev-parse HEAD)"
r checkout -q main

export GH_STUB_PR_LIST="[
  {\"number\": 3, \"state\": \"MERGED\", \"headRefName\": \"todo/shipped\", \"headRefOid\": \"0000000000000000000000000000000000000000\", \"url\": \"https://github.com/acme/demo/pull/3\"},
  {\"number\": 5, \"state\": \"OPEN\", \"headRefName\": \"todo/api-v2\", \"headRefOid\": \"1111111111111111111111111111111111111111\", \"url\": \"https://github.com/acme/demo/pull/5\"},
  {\"number\": 8, \"state\": \"MERGED\", \"headRefName\": \"todo/prmerged\", \"headRefOid\": \"$prmerged_oid\", \"url\": \"https://github.com/acme/demo/pull/8\"}
]"

names=(api api-v2 rebased squashy fresh parallel gone prmerged shipped ghost)

# A registry fixture so single-project calls can disambiguate prefixes with --hub.
hub="$work/hub"
mkdir -p "$hub"
{
  printf '# Project Index\n\n## Work\n\n'
  printf '| short-name | path | repo | status |\n|---|---|---|---|\n'
  for name in "${names[@]}"; do
    printf '| %s | projects/work/%s | %s | in-progress |\n' "$name" "$name" "$repo"
  done
} > "$hub/index.md"

# ---------------------------------------------------------------------------
# 1. Inputs are validated before anything runs.
# ---------------------------------------------------------------------------
: > "$GIT_LOG"
: > "$GH_STUB_LOG"
evidence "$with_gh" "$repo;touch $work/pwned" api
expect_equal "metacharacter repo path exits 2" 2 "$run_code"
expect_contains "metacharacter repo path is reported" "$run_out" "ERROR	INVALID_INPUT"
[ ! -e "$work/pwned" ] || fail "metacharacter repo path was executed"
evidence "$with_gh" "$repo" 'api;id'
expect_equal "invalid short-name exits 2" 2 "$run_code"
evidence "$with_gh" "$repo" API
expect_equal "uppercase short-name exits 2" 2 "$run_code"
evidence "$with_gh" - api
expect_equal "hub-only repo '-' exits 2" 2 "$run_code"
evidence "$with_gh" "$repo"
expect_equal "missing short-name exits 2" 2 "$run_code"
evidence "$with_gh" "$repo" api --bogus
expect_equal "unknown option exits 2" 2 "$run_code"
evidence "$with_gh" "$repo" api --hub "$hub;id"
expect_equal "metacharacter hub path exits 2" 2 "$run_code"
evidence "$with_gh" "$repo" api --hub
expect_equal "--hub without a directory exits 2" 2 "$run_code"
[ ! -s "$GIT_LOG" ] || fail "git ran before input validation passed"
[ ! -s "$GH_STUB_LOG" ] || fail "gh ran before input validation passed"

# ---------------------------------------------------------------------------
# 2. A repo that is not on disk is unknown, never absent.
# ---------------------------------------------------------------------------
evidence "$with_gh" "$work/nowhere" api api-v2
expect_equal "missing repo exits 3" 3 "$run_code"
expect_contains "missing repo is reported" "$run_out" "ERROR	REPO_UNAVAILABLE"
for name in api api-v2; do
  expect_equal "missing repo leaves $name unknown" \
    "branch=unknown pr=unknown worktree=unknown unshipped=unknown uncommitted=unknown" \
    "$(summary_of "$name")"
done

# ---------------------------------------------------------------------------
# 3. Full evidence, one call for every project on the repo, read-only.
# ---------------------------------------------------------------------------
: > "$GH_STUB_LOG"
: > "$GIT_LOG"
refs_before="$(git -C "$repo" for-each-ref --format='%(refname) %(objectname)')"
index_before="$(cksum < "$repo/.git/index")"
evidence "$with_gh" "$repo" "${names[@]}"
expect_equal "full evidence exits 0" 0 "$run_code"
expect_equal "refs unchanged without --fetch" "$refs_before" \
  "$(git -C "$repo" for-each-ref --format='%(refname) %(objectname)')"
expect_equal "index unchanged without --fetch" "$index_before" "$(cksum < "$repo/.git/index")"
grep -q ' fetch' "$GIT_LOG" && fail "helper fetched without --fetch"
expect_equal "one gh call per helper run" 1 "$(grep -c 'pr list' "$GH_STUB_LOG")"
expect_contains "gh queried the derived slug" "$(cat "$GH_STUB_LOG")" "--repo acme/demo"

repo_row="$(printf '%s\n' "$run_out" | awk -F '\t' '$1 == "REPO"')"
expect_contains "slug derived from origin" "$repo_row" "slug=acme/demo"
expect_contains "base derived from origin/HEAD" "$repo_row" "base=main"
expect_contains "no fetch requested" "$repo_row" "fetch=skipped"
expect_contains "gh consulted" "$repo_row" "gh=ok"

expect_equal "merge commit counts as merged" \
  "local=yes remote=no ahead=0 state=merged via=merge" "$(branch_row api todo/api)"
expect_equal "replayed patch counts as merged" \
  "local=yes remote=no ahead=1 state=merged via=rebase" "$(branch_row rebased todo/rebased)"
expect_equal "squash merge counts as merged" \
  "local=yes remote=no ahead=2 state=merged via=squash" "$(branch_row squashy todo/squashy)"
expect_equal "merged PR head counts as merged" \
  "local=yes remote=no ahead=1 state=merged via=pr" "$(branch_row prmerged todo/prmerged)"
expect_equal "unshipped branch is open" \
  "local=yes remote=no ahead=2 state=open via=-" "$(branch_row api-v2 todo/api-v2)"
expect_equal "prefix branch goes to the longest name" \
  "local=yes remote=no ahead=2 state=open via=-" "$(branch_row api-v2 feat/api-v2-extra)"
[ -z "$(branch_row api feat/api-v2-extra)" ] || fail "api collapsed into api-v2"
expect_equal "branch without own commits is empty" \
  "local=yes remote=no ahead=0 state=empty via=-" "$(branch_row fresh todo/fresh)"

expect_equal "api summary" \
  "branch=merged pr=none worktree=absent unshipped=0 uncommitted=0" "$(summary_of api)"
expect_equal "api-v2 summary" \
  "branch=open pr=open worktree=present unshipped=2 uncommitted=2" "$(summary_of api-v2)"
expect_equal "squashy summary" \
  "branch=merged pr=none worktree=absent unshipped=0 uncommitted=0" "$(summary_of squashy)"
expect_equal "rebased summary" \
  "branch=merged pr=none worktree=absent unshipped=0 uncommitted=0" "$(summary_of rebased)"
expect_equal "PR-merged summary" \
  "branch=merged pr=merged worktree=absent unshipped=0 uncommitted=0" "$(summary_of prmerged)"
expect_equal "fresh summary" \
  "branch=empty pr=none worktree=present unshipped=0 uncommitted=0" "$(summary_of fresh)"
expect_equal "parallel worktree attributed by branch" \
  "branch=open pr=none worktree=present unshipped=1 uncommitted=0" "$(summary_of parallel)"
expect_equal "deleted branch with merged PR" \
  "branch=merged pr=merged worktree=absent unshipped=0 uncommitted=0" "$(summary_of shipped)"
expect_equal "nothing anywhere is absent" \
  "branch=absent pr=none worktree=absent unshipped=0 uncommitted=0" "$(summary_of ghost)"
expect_contains "missing worktree folder is reported" "$run_out" \
  "WORKTREE	gone	$repo-wt/gone	branch=todo/gone	state=missing"
expect_equal "missing worktree folder is not present" \
  "branch=empty pr=none worktree=absent unshipped=0 uncommitted=0" "$(summary_of gone)"
expect_contains "open PR row" "$run_out" \
  "PR	api-v2	5	OPEN	todo/api-v2	https://github.com/acme/demo/pull/5"
expect_contains "uncommitted work row" "$run_out" \
  "WORKTREE	api-v2	$repo-wt/api-v2	branch=todo/api-v2	state=present	uncommitted=2	ahead=2"

# A single-project call still sees its own worktree and PR.
evidence "$with_gh" "$repo" api-v2
expect_equal "single-project api-v2 summary" \
  "branch=open pr=open worktree=present unshipped=2 uncommitted=2" "$(summary_of api-v2)"

# Alone, api would claim api-v2's prefix branches; --hub hands them to the longer name.
evidence "$with_gh" "$repo" api --hub "$hub"
expect_equal "single-project api summary with --hub" \
  "branch=merged pr=none worktree=absent unshipped=0 uncommitted=0" "$(summary_of api)"
expect_lacks "api-v2 rows stay out of an api-only call" "$run_out" "api-v2"

# ---------------------------------------------------------------------------
# 4. No gh, failing gh, non-GitHub origin: pr is unknown, never none.
# ---------------------------------------------------------------------------
evidence "$without_gh" "$repo" api shipped --hub "$hub"
expect_contains "missing gh is reported" "$run_out" "gh=unavailable"
expect_equal "missing gh leaves pr unknown" \
  "branch=merged pr=unknown worktree=absent unshipped=0 uncommitted=0" "$(summary_of api)"
expect_equal "no branch and no gh is absent, pr unknown" \
  "branch=absent pr=unknown worktree=absent unshipped=0 uncommitted=0" "$(summary_of shipped)"

GH_STUB_FAIL=yes evidence "$with_gh" "$repo" api --hub "$hub"
expect_contains "failing gh is reported" "$run_out" "gh=failed"
expect_contains "failing gh leaves pr unknown" "$(summary_of api)" "pr=unknown"

local_repo="$work/local-origin"
git clone -q "$work/remote.git" "$local_repo" 2> /dev/null
: > "$GH_STUB_LOG"
evidence "$with_gh" "$local_repo" api
expect_contains "non-GitHub origin has no slug" "$run_out" "slug=-"
expect_contains "non-GitHub origin skips gh" "$run_out" "gh=no-github-remote"
[ ! -s "$GH_STUB_LOG" ] || fail "gh ran for a non-GitHub origin"

# ---------------------------------------------------------------------------
# 5. --fetch runs once; a failed fetch makes the branch verdict unknown.
# ---------------------------------------------------------------------------
g pull -q --ff-only origin main
echo later > "$work/seed/later.txt"
g add later.txt
g commit -qm "later"
g push -q origin main
: > "$GIT_LOG"
evidence "$with_gh" "$repo" api api-v2 --fetch
expect_contains "fetch succeeded" "$run_out" "fetch=ok"
expect_equal "fetch runs once per call" 1 "$(grep -c '^-C .* fetch' "$GIT_LOG")"
expect_equal "fetched base is visible" "$(git -C "$work/seed" rev-parse HEAD)" \
  "$(git -C "$repo" rev-parse origin/main)"

r config "url.$work/missing.git.insteadOf" https://github.com/acme/demo.git
r config --unset "url.$work/remote.git.insteadOf"
evidence "$with_gh" "$repo" api --fetch --hub "$hub"
expect_contains "fetch failure is reported" "$run_out" "fetch=failed"
expect_contains "failed fetch leaves the branch unknown" "$(summary_of api)" "branch=unknown"
r config --unset "url.$work/missing.git.insteadOf"
r config "url.$work/remote.git.insteadOf" https://github.com/acme/demo.git

# ---------------------------------------------------------------------------
# 6. Base falls back to main/master when origin/HEAD is unset.
# ---------------------------------------------------------------------------
r remote set-head origin -d
evidence "$with_gh" "$repo" api --hub "$hub"
expect_contains "base falls back to origin/main" "$run_out" "base=main"
r remote set-head origin main

# ---------------------------------------------------------------------------
# 7. Skill text uses the shared helpers and runnable commands only.
# ---------------------------------------------------------------------------
list_skill="$repo_root/skills/todo-list/SKILL.md"
triage_skill="$repo_root/skills/todo-triage/SKILL.md"
state_skill="$repo_root/skills/todo-state/SKILL.md"
refer_skill="$repo_root/skills/todo-refer/SKILL.md"
for skill in "$list_skill" "$triage_skill" "$state_skill" "$refer_skill"; do
  text="$(cat "$skill")"
  label="${skill#"$repo_root"/}"
  expect_contains "$label counts through graph-report" "$text" "graph-report.py"
  expect_lacks "$label runs no per-project awk count" "$text" "awk '"
  expect_lacks "$label passes no registry owner" "$text" "<owner>/<repo>"
  expect_lacks "$label lists no repo-wide feat branches" "$text" "'feat/*'"
done
for skill in "$state_skill" "$refer_skill"; do
  expect_contains "${skill#"$repo_root"/} gathers repo evidence via the helper" \
    "$(cat "$skill")" "repo-evidence.sh"
done
triage_text="$(cat "$triage_skill")"
expect_contains "triage lists open tasks via graph-report tasks" "$triage_text" "tasks \"\$TODO_HUB\""
expect_lacks "triage greps no raw checkboxes" "$triage_text" "- \\[ \\])"
expect_lacks "triage never recommends a nonexistent effort" "$triage_text" "highest"
expect_lacks "triage never targets a revision by bare number" "$triage_text" "/todo-revise api-token-rotation 3"
expect_lacks "triage never truncates a short-name" "$triage_text" "rmq-vertical-scaler tasks"
if grep -Eq '/todo-execute [a-z0-9-]+ tasks [0-9]' "$triage_skill"; then :; else
  fail "triage session plan lacks a runnable /todo-execute <short> tasks <ids> line"
fi
grep -Eq '/todo-revise [a-z0-9-]+ R[0-9]' "$triage_skill" ||
  fail "triage session plan lacks a runnable /todo-revise <short> R<n> line"
refer_text="$(cat "$refer_skill")"
expect_lacks "refer prints no second count from the archive context helper" "$refer_text" "archive-report.sh context"
expect_contains "refer routes a finished project without a gate to done" "$refer_text" "| \`/todo-state <short-name> done\` |"
expect_contains "refer routes a planning project to todo-plan" "$refer_text" "| \`/todo-plan <short-name>\` |"
expect_contains "refer targets a revision by ID" "$refer_text" "| \`/todo-revise <short-name> R<n>\` |"

# ---------------------------------------------------------------------------
# 8. Revision tags route open, awaiting-verify, and advisory entries apart.
# ---------------------------------------------------------------------------
tag_pattern() {
  sed -n "s/.*grep -inE \(-A4 \)\{0,1\}'\([^']*awaiting verify[^']*\)'.*/\2/p" "$1"
}
triage_tags="$(tag_pattern "$triage_skill")"
refer_tags="$(tag_pattern "$refer_skill")"
[ -n "$triage_tags" ] || fail "triage has no live-revision grep"
expect_equal "triage and refer read revision tags the same way" "$triage_tags" "$refer_tags"
cat > "$work/tags.md" <<'TAGS'
## Revisions
### R1 ⟵ Task 4.5 — picker   [open]
### R2 ⟵ Task 4.6 — picker   [OPEN — needs creds]
### R3 ⟵ Task 4.7 — backoff  [fixed — awaiting verify]
### R4 ⟵ Task 4.8 — backoff  [Fixed — Awaiting Verify]
### R5 ⟵ Task 5.3 — rotate   [advisory]
### R6 — closed [done]
### R7 — closed [DONE 2026-07-13]
### R8 — replaced [superseded by R9]
### R10 — legacy [fixed]
## R11 — legacy level-2 [open]
### R12 [open] trailing prose, not a tag
TAGS
matched="$(grep -inE "$triage_tags" "$work/tags.md" | sed -E 's/^[0-9]+:#+ (R[0-9]+).*/\1/' | tr '\n' ' ')"
expect_equal "live revision grep matches open, awaiting-verify, and advisory only" "R1 R2 R3 R4 R5 R11 " "$matched"
state_text="$(cat "$state_skill")"
expect_contains "state done routes awaiting-verify entries to verify" "$state_text" "\`[fixed — awaiting verify]\` →
   \`/todo-verify <short-name>\`"
expect_contains "state done lets advisory entries through" "$state_text" "never block \`done\`"
expect_contains "triage routes awaiting-verify rows to verify" "$triage_text" "\`/todo-verify <short-name>\` for awaiting-verify rows"

printf 'ok - state contract\n'
