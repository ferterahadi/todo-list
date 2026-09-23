# Shared by preflight.sh and land.sh — sourced, never run. Keeps the two scripts reading
# `git status` and choosing a merge strategy the same way.

# Paths out of `git status`, one per line, sorted, relative to the repo root. Parsed from the
# NUL-separated form, so a rename comes out as two usable paths, never one "old -> new" string.
#   changed    every uncommitted path — staged, unstaged, untracked, both sides of a rename
#   staged     paths whose index entry differs from HEAD, both sides of a staged rename
#   untracked  untracked paths, listed individually rather than as a collapsed "dir/"
#   renames    "old<TAB>new" for each rename
status_paths() {
  git status --porcelain -z --untracked-files=all | python3 -c '
import sys

mode = sys.argv[1]
fields = sys.stdin.buffer.read().split(b"\0")
out = set()
i = 0
while i < len(fields):
    record = fields[i]
    i += 1
    if len(record) < 4:
        continue
    x, y, path = record[0:1], record[1:2], record[3:]
    orig = None
    if x in b"RC" or y in b"RC":
        orig = fields[i]
        i += 1
    renamed = orig is not None and b"R" in (x, y)
    if mode == "changed":
        out.add(path)
        if renamed:
            out.add(orig)
    elif mode == "staged" and x not in b" ?!":
        out.add(path)
        if renamed and x == b"R":
            out.add(orig)
    elif mode == "untracked" and x == b"?":
        out.add(path)
    elif mode == "renames" and renamed:
        out.add(orig + b"\t" + path)
for line in sorted(out):
    sys.stdout.buffer.write(line + b"\n")
' "$1"
}

# "<pattern> <merge-commits> <sampled>" over the last ten first-parent commits of <ref>. The
# pattern is `merge` when most of them are merge commits and `linear` otherwise — a repo can
# permit merge commits and still squash every PR.
merge_history() {
  local ref="$1" total=0 merges=0
  if [ -n "$ref" ] && git rev-parse --verify --quiet "$ref^{commit}" > /dev/null; then
    read -r total merges <<< "$(
      git log --first-parent --max-count=10 --format=%p "$ref" 2> /dev/null |
        awk 'NF>1{m++} {t++} END{printf "%d %d", t+0, m+0}'
    )"
  fi
  if [ "$total" -gt 0 ] && [ $((merges * 2)) -gt "$total" ]; then
    printf 'merge %s %s\n' "$merges" "$total"
  else
    printf 'linear %s %s\n' "$merges" "$total"
  fi
}

# Allowed strategies, one per line, from `gh repo view --json` output on stdin.
allowed_strategies() {
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
'
}

# The strategy to hand `gh pr merge`: what the repo does, limited to what it allows.
#   pick_merge_strategy <pattern> <allowed strategies, newline-separated>
pick_merge_strategy() {
  local pattern="$1"
  local allowed=$'\n'"$2"$'\n'
  if [ "$pattern" = merge ] && [[ "$allowed" == *$'\n'merge$'\n'* ]]; then
    printf 'merge\n'
  elif [[ "$allowed" == *$'\n'squash$'\n'* ]]; then
    printf 'squash\n'
  elif [[ "$allowed" == *$'\n'rebase$'\n'* ]]; then
    printf 'rebase\n'
  else
    printf 'merge\n'
  fi
}
