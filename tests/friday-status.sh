#!/usr/bin/env bash
# Tests for `friday-propagate --status` (#72): the read-only release status
# table, one row per consumer with the release tag, the friday-lock state read
# from origin/main, and the open sync pull request.
#
# Same fixtures as tests/friday-propagate.sh: a scratch kit with a bare origin,
# scratch consumers with bare origins, and a shim `gh`. Here the shim answers
# `gh pr list` from $GH_STATUS_DIR/<consumer directory name> (JSON, filtered
# by the script's own --jq program) and fails when
# $GH_STATUS_FAIL is set. FRIDAY_PROPAGATE_UNDER_TEST=<path> runs another copy of
# the script (a mutant), as PROPAGATE_UNDER_TEST does in the sibling suite.
# Sandboxes are left in place under the printed directory.
set -uo pipefail
[ "$#" -le 1 ] || { echo "usage: $0 [retained-output-directory]" >&2; exit 2; }

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
base=${1:-${TMPDIR:-/tmp}}
mkdir -p "$base"
root=$(mktemp -d "$base/friday-status-test.XXXXXX")
echo "sandboxes: $root"

fails=0
total=0
ok()   { total=$((total + 1)); echo "ok   $1"; }
fail() { total=$((total + 1)); echo "FAIL $1"; fails=$((fails + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else fail "$name"; fi; }
gq() { git -c user.name=t -c user.email=t@example.invalid "$@"; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

shim="$root/shim"
mkdir -p "$shim"
cat > "$shim/gh" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = pr ] && [ "${2:-}" = list ]; then
  [ -z "${GH_STATUS_FAIL:-}" ] || { echo "gh: HTTP 502" >&2; exit 1; }
  # Like gh: the JSON of the open PRs, with the --jq program applied.
  f="${GH_STATUS_DIR:-/nonexistent}/$(basename "$PWD")"
  prog=
  while [ $# -gt 0 ]; do [ "$1" = --jq ] && prog=$2; shift; done
  [ -f "$f" ] || echo '[]' > "$f.empty"
  jq -r "$prog" "$( [ -f "$f" ] && echo "$f" || echo "$f.empty" )"
  exit 0
fi
echo "unexpected gh call: $*" >&2
exit 99
SHIM
chmod +x "$shim/gh"

n=0
new_case() {
  n=$((n + 1)); case_dir="$root/$n"; kit="$case_dir/kit"
  mkdir -p "$kit/bin" "$case_dir/prs"
  cp "${FRIDAY_PROPAGATE_UNDER_TEST:-$source_root/bin/friday-propagate}" "$kit/bin/friday-propagate"
  cp "$source_root/bin/friday-lock" "$source_root/bin/managed-core.txt" "$kit/bin/"
  cp -R "$source_root/payload" "$kit/payload"
  git init -q -b main "$kit" && gq -C "$kit" add -A && gq -C "$kit" commit -q -m "payload v1"
  git init -q --bare -b main "$kit.git"
  gq -C "$kit" remote add origin "$kit.git"
  gq -C "$kit" tag -a v1.0.0 -m "release v1.0.0"
  gq -C "$kit" push -q origin main refs/tags/v1.0.0
  export GH_STATUS_DIR="$case_dir/prs"
  unset GH_STATUS_FAIL
}
new_consumer() {
  local c="$case_dir/$1"
  git init -q --bare -b main "$c.git"
  git init -q -b main "$c"
  while IFS= read -r rel; do
    case "$rel" in ''|'#'*|'!'*) continue ;; esac
    mkdir -p "$c/$(dirname "$rel")"; cp -p "$kit/payload/$rel" "$c/$rel"
  done < "$kit/bin/managed-core.txt"
  bash "$kit/bin/friday-lock" write "$c" >/dev/null
  gq -C "$c" add -A && gq -C "$c" commit -q -m "chore: adopt"
  gq -C "$c" remote add origin "$c.git" && gq -C "$c" push -q origin main
}
release() { gq -C "$kit" tag -a "$1" -m "release $1" && gq -C "$kit" push -q origin "refs/tags/$1"; }
m1() { grep -v -e '^#' -e '^!' -e '^[[:space:]]*$' "$kit/bin/managed-core.txt" | sed -n "${1}p"; }
bump() { printf '\n# %s\n' "$2" >> "$kit/payload/$1"; gq -C "$kit" commit -qam "payload: $2"; }
run() { PATH="$shim:$PATH" bash "$kit/bin/friday-propagate" --status "$@" > "$case_dir/run.log" 2>&1; }
# Everything a consumer's person would notice: tree, branches, HEAD, stash.
# The content of every file outside .git, tracked or not, is part of it.
snap() {
  { git -C "$1" status --porcelain; git -C "$1" branch; git -C "$1" rev-parse HEAD; git -C "$1" stash list
    (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do shasum "$f"; done)
  } 2>&1
}
row() { grep "^$1 " "$case_dir/run.log"; }

# 1. One table: in sync, behind, behind with an open PR, drifted, a feature
#    branch (dirty), and a missing path. Nothing in any consumer changes.
new_case
new_consumer behind; new_consumer pr; new_consumer drift; new_consumer feat
a=$(m1 1)
# drift: a managed file edited and committed in the consumer's own main
printf '\n# local edit\n' >> "$case_dir/drift/$a"; gq -C "$case_dir/drift" commit -qam "edit a managed file"
gq -C "$case_dir/drift" push -q origin main
# feat: on a feature branch whose own checkout has a managed edit, and a dirty tree
gq -C "$case_dir/feat" switch -q -c feature/x
printf '\n# on the branch\n' >> "$case_dir/feat/$a"; gq -C "$case_dir/feat" commit -qam "branch edit"
printf '\n# uncommitted\n' >> "$case_dir/feat/$(m1 2)"
printf 'scratch\n' > "$case_dir/feat/untracked.txt"
bump "$a" v2; release v1.1.0
new_consumer synced
echo '[{"headRefName":"chore/sync-managed-core-v1.0.5","url":"https://example.invalid/pr/7"},{"headRefName":"feature/unrelated","url":"https://example.invalid/pr/8"}]' > "$case_dir/prs/pr"
echo '[{"headRefName":"feature/unrelated","url":"https://example.invalid/pr/9"}]' > "$case_dir/prs/behind"
consumers=(synced behind pr drift feat)
for c in "${consumers[@]}"; do snap "$case_dir/$c" > "$case_dir/$c.before"; done
run "$case_dir/synced" "$case_dir/behind" "$case_dir/pr" "$case_dir/drift" "$case_dir/feat" "$case_dir/gone"; rc=$?
for c in "${consumers[@]}"; do snap "$case_dir/$c" > "$case_dir/$c.after"; done
cat "$case_dir/run.log"
check "table: the header names the three columns" \
  bash -c "head -1 '$case_dir/run.log' | grep -q '^CONSUMER *TAG *LOCK *SYNC PR'"
check "in sync: the row says in sync, names the tag, and has no PR" \
  bash -c "r=\$(grep '^synced ' '$case_dir/run.log'); echo \"\$r\" | grep -q 'v1.1.0 (on origin, same tag object)' && echo \"\$r\" | grep -q 'in sync' && echo \"\$r\" | grep -q 'none\$'"
check "behind: the row says behind, and a PR for another branch is not listed" \
  bash -c "r=\$(grep '^behind ' '$case_dir/run.log'); echo \"\$r\" | grep -q ' behind ' && echo \"\$r\" | grep -q 'none\$'"
check "behind with an open PR: the row lists the sync branch and its URL, not the other branch" \
  bash -c "r=\$(grep '^pr ' '$case_dir/run.log'); echo \"\$r\" | grep -q ' behind ' && echo \"\$r\" | grep -q 'chore/sync-managed-core-v1.0.5 https://example.invalid/pr/7' && ! echo \"\$r\" | grep -q 'unrelated'"
check "drifted: the row says drifted" \
  bash -c "grep '^drift ' '$case_dir/run.log' | grep -q ' drifted'"
check "feature branch: the row says on feature/x, not main, with the state from origin/main (behind, not drifted)" \
  bash -c "r=\$(grep '^feat ' '$case_dir/run.log'); echo \"\$r\" | grep -q 'behind; on feature/x, not main' && ! echo \"\$r\" | grep -q drifted"
check "feature branch: the table still lists every consumer" \
  bash -c "[ \$(grep -c -e '^synced ' -e '^behind ' -e '^pr ' -e '^drift ' -e '^feat ' -e '^gone ' '$case_dir/run.log') = 6 ]"
check "missing: a row with the reason, not an abort" \
  bash -c "grep '^gone ' '$case_dir/run.log' | grep -q 'unreadable: no such path'"
check "exit status: a missing path makes the table incomplete, so 2" test "$rc" = 2
for c in "${consumers[@]}"; do
  check "read-only: $c's git status, branches, HEAD and stash are unchanged" cmp -s "$case_dir/$c.before" "$case_dir/$c.after"
done
check "read-only: the comparison covers file contents, the dirty tracked file and the untracked one" \
  bash -c "grep -q 'untracked.txt' '$case_dir/feat.before' && grep -q ' \./$(m1 2)\$' '$case_dir/feat.before'"
check "read-only: the dirty tree on the feature branch is still dirty, still untracked" \
  bash -c "[ -f '$case_dir/feat/untracked.txt' ] && [ \"\$(git -C '$case_dir/feat' branch --show-current)\" = feature/x ]"
check "read-only: no sync branch was created in any consumer" \
  bash -c "for c in synced behind pr drift feat; do [ -z \"\$(git -C '$case_dir'/\$c branch --list 'chore/*')\" ] || exit 1; done"

# 2. Exit status: 3 when something is behind and every row was read; 0 when all
#    are in sync.
new_case; new_consumer behind
bump "$(m1 1)" v2; release v1.1.0; new_consumer synced
run "$case_dir/synced" "$case_dir/behind"; rc=$?
check "exit 3: a behind consumer and no unreadable row" test "$rc" = 3
check "exit 3: the summary line counts them" grep -q 'in-sync=1 not-in-sync=1 unreadable=0' "$case_dir/run.log"
run "$case_dir/synced"; rc=$?
check "exit 0: every consumer is in sync" test "$rc" = 0

# 3. A consumer with no lock on origin/main, and one that is not a repository,
#    are rows with the reason. A gh failure is a row too, exit 2.
new_case; new_consumer a
mkdir "$case_dir/plain"
git init -q -b main "$case_dir/nolock"; git init -q --bare -b main "$case_dir/nolock.git"
gq -C "$case_dir/nolock" remote add origin "$case_dir/nolock.git"
printf 'x\n' > "$case_dir/nolock/f"; gq -C "$case_dir/nolock" add f; gq -C "$case_dir/nolock" commit -q -m x; gq -C "$case_dir/nolock" push -q origin main
run "$case_dir/a" "$case_dir/plain" "$case_dir/nolock"; rc=$?
check "unreadable: not a git repository is a row with the reason" bash -c "grep '^plain ' '$case_dir/run.log' | grep -q 'unreadable: not a git repository'"
check "unreadable: a repository with no lock on origin/main is a row with the reason" \
  bash -c "grep '^nolock ' '$case_dir/run.log' | grep -q 'unreadable: no .friday-lock.json on origin/main'"
check "unreadable: the readable consumer is still listed, and the exit is 2" bash -c "grep -q '^a .*in sync' '$case_dir/run.log' && [ $rc = 2 ]"
export GH_STATUS_FAIL=1
run "$case_dir/a"; rc=$?
unset GH_STATUS_FAIL
check "gh failure: the row says unknown with gh's message, exit 2" \
  bash -c "grep '^a ' '$case_dir/run.log' | grep -q 'unknown: gh failed: gh: HTTP 502' && [ $rc = 2 ]"

# 4. The release tag is checked as a run checks it; --status and --dry-run
#    do not combine.
new_case; new_consumer a
gq -C "$kit" tag v1.1.0
run --tag v1.1.0 "$case_dir/a"; rc=$?
check "tag: a tag that is not on origin is refused (exit 2), no table" \
  bash -c "[ $rc = 2 ] && grep -q 'not an annotated tag\|not on origin' '$case_dir/run.log' && ! grep -q '^CONSUMER' '$case_dir/run.log'"
PATH="$shim:$PATH" bash "$kit/bin/friday-propagate" --status --dry-run "$case_dir/a" > "$case_dir/run.log" 2>&1; rc=$?
check "--status with --dry-run is a usage error (exit 2)" bash -c "[ $rc = 2 ] && grep -q 'do not go together' '$case_dir/run.log'"

# 5. The fetch: another clone advances a consumer's origin main after this
#    consumer last fetched. The row must show the state origin holds now.
new_case; new_consumer c
bump "$(m1 1)" v2; release v1.1.0
git -C "$case_dir" clone -q "$case_dir/c.git" "$case_dir/c2"
while IFS= read -r rel; do
  case "$rel" in ''|'#'*|'!'*) continue ;; esac
  mkdir -p "$case_dir/c2/$(dirname "$rel")"; cp -p "$kit/payload/$rel" "$case_dir/c2/$rel"
done < "$kit/bin/managed-core.txt"
bash "$kit/bin/friday-lock" write "$case_dir/c2" >/dev/null
gq -C "$case_dir/c2" add -A && gq -C "$case_dir/c2" commit -q -m "chore: sync" && gq -C "$case_dir/c2" push -q origin main
run "$case_dir/c"; rc=$?
check "fetch: a push from another clone after the last fetch shows (in sync, exit 0)" \
  bash -c "row() { grep '^c ' '$case_dir/run.log'; }; row | grep -q 'in sync' && [ $rc = 0 ]"

# 6. A feature branch with its own, different lock commit: the row reads the
#    lock origin/main holds (behind), not the branch's (in sync).
new_case; new_consumer f
bump "$(m1 1)" v2; release v1.1.0
gq -C "$case_dir/f" switch -q -c feature/y
while IFS= read -r rel; do
  case "$rel" in ''|'#'*|'!'*) continue ;; esac
  cp -p "$kit/payload/$rel" "$case_dir/f/$rel"
done < "$kit/bin/managed-core.txt"
bash "$kit/bin/friday-lock" write "$case_dir/f" >/dev/null
gq -C "$case_dir/f" add -A && gq -C "$case_dir/f" commit -q -m "branch sync"
run "$case_dir/f"; rc=$?
check "feature branch with its own lock: the row reads origin/main's lock (behind), not the branch's" \
  bash -c "grep '^f ' '$case_dir/run.log' | grep -q 'behind; on feature/y, not main' && [ $rc = 3 ]"

# 7. Traversal keys in the lock on origin/main. Git itself refuses '../x' and
#    '/abs' as paths, so the guard is what stops 'a/../../b', which a crafted
#    tree (entries named '..') makes resolvable. Nothing may be written outside
#    the scratch directory, and the row is not in sync.
new_case; new_consumer t
t="$case_dir/t"
tmpd="$case_dir/tmp"; mkdir -p "$tmpd"
bl=$(printf 'pwned\n' | git -C "$t" hash-object -w --stdin)
t2=$(printf '100644 blob %s\tb\n' "$bl" | git -C "$t" mktree)
t1=$(printf '040000 tree %s\t..\n' "$t2" | git -C "$t" mktree)
ta=$(printf '040000 tree %s\t..\n' "$t1" | git -C "$t" mktree)
git -C "$t" show HEAD:.friday-lock.json \
  | jq '.managed_core += {"../../../escape":"x","a/../../b":"x","/abs/path":"x"}' > "$case_dir/lock.json"
nl=$(git -C "$t" hash-object -w "$case_dir/lock.json")
tr=$({ git -C "$t" ls-tree HEAD | awk -F'\t' '$2 != ".friday-lock.json"'
       printf '040000 tree %s\ta\n100644 blob %s\t.friday-lock.json\n' "$ta" "$nl"; } | git -C "$t" mktree)
cm=$(git -C "$t" commit-tree "$tr" -p HEAD -m "crafted")
git -C "$t" push -q origin "$cm:refs/heads/main"
TMPDIR="$tmpd" run "$case_dir/t"; rc=$?
check "traversal keys: nothing is written outside the scratch directory" \
  bash -c "[ ! -e '$tmpd/b' ] && [ ! -e '$tmpd/../escape' ] && [ ! -e /abs/path ]"
check "traversal keys: the row is not in sync" \
  bash -c "! grep '^t ' '$case_dir/run.log' | grep -q 'in sync' && [ $rc != 0 ]"

# 8. No temporary-directory path in a row: a lock that records no files makes
#    friday-lock name the directory it was given. TMPDIR is a symlink, so the
#    raw and the physical (pwd -P) forms differ on every platform.
new_case; new_consumer n
mkdir "$case_dir/tmpreal"; ln -s "$case_dir/tmpreal" "$case_dir/tmplink"
git -C "$case_dir/n" show HEAD:.friday-lock.json | jq '.managed_core = {}' > "$case_dir/n/.friday-lock.json"
gq -C "$case_dir/n" commit -qam "empty lock" && gq -C "$case_dir/n" push -q origin main
TMPDIR="$case_dir/tmplink" run "$case_dir/n"; rc=$?
check "no temp path: the row is unreadable with friday-lock's reason" \
  bash -c "grep '^n ' '$case_dir/run.log' | grep -q 'unreadable: .*records no files' && [ $rc = 2 ]"
check "no temp path: the row has neither TMPDIR nor its physical form" \
  bash -c "! grep -q -e '$case_dir/tmplink' -e '$case_dir/tmpreal' -e 'friday-status\\.' '$case_dir/run.log'"

# 9. Cleanup: the scratch directory is removed.
new_case; new_consumer k
mkdir "$case_dir/emptytmp"
TMPDIR="$case_dir/emptytmp" run "$case_dir/k"
check "cleanup: the temporary directory is empty after a run" \
  bash -c "[ -z \"\$(ls -A '$case_dir/emptytmp')\" ]"

# 10. An annotated tag that is not on origin is refused as not on origin.
new_case; new_consumer a
gq -C "$kit" tag -a v1.1.0 -m "release v1.1.0"
run --tag v1.1.0 "$case_dir/a"; rc=$?
check "tag: an annotated tag that is not pushed is refused as not on origin (exit 2)" \
  bash -c "[ $rc = 2 ] && grep -q 'is not on origin' '$case_dir/run.log' && ! grep -q 'not an annotated tag' '$case_dir/run.log'"

echo
if [ "$fails" -gt 0 ]; then echo "$fails of $total failed"; exit 1; fi
echo "all $total passed"
