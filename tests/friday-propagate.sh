#!/usr/bin/env bash
# End-to-end tests for bin/friday-propagate, against #29's acceptance list.
#
# A scratch kit (bin/ + payload/ in a Git repository of its own, on main) and
# scratch consumers, each with a local bare origin, run the real script. A
# shim `gh` on PATH records each pull request instead of opening one, and can
# run a command the first time it is called -- which is how a Friday commit
# "made while the run is going" is simulated between two consumers.
# Sandboxes are left in place under the printed directory.
set -uo pipefail
[ "$#" -le 1 ] || { echo "usage: $0 [retained-output-directory]" >&2; exit 2; }

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
base=${1:-${TMPDIR:-/tmp}}
mkdir -p "$base"
root=$(mktemp -d "$base/friday-propagate-test.XXXXXX")
echo "sandboxes: $root"

fails=0
total=0
ok()   { total=$((total + 1)); echo "ok   $1"; }
fail() { total=$((total + 1)); echo "FAIL $1"; fails=$((fails + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else fail "$name"; fi; }
gq() { git -c user.name=t -c user.email=t@example.invalid "$@"; }

# Hermetic: no global or system Git config, and a fixed identity, so the
# suite behaves the same on a CI runner with no user.name as on a laptop.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# The shim gh: logs the PR it was asked to open, prints a URL, and runs
# $GH_SHIM_ONCE the first time only.
shim="$root/shim"
mkdir -p "$shim"
cat > "$shim/gh" <<'EOF'
#!/usr/bin/env bash
log=${GH_SHIM_LOG:?}
n=$(( $(ls "$log" 2>/dev/null | wc -l) + 1 ))
mkdir -p "$log"
printf '%s\n' "$@" > "$log/$n.args"
if [ "$n" = 1 ] && [ -n "${GH_SHIM_ONCE:-}" ]; then bash -c "$GH_SHIM_ONCE" >/dev/null 2>&1; fi
echo "https://example.invalid/pull/$n"
EOF
chmod +x "$shim/gh"

n=0
new_case() {
  n=$((n + 1)); case_dir="$root/$n"; kit="$case_dir/kit"
  mkdir -p "$kit/bin"
  cp "${PROPAGATE_UNDER_TEST:-$source_root/bin/friday-propagate}" "$kit/bin/friday-propagate"
  cp "$source_root/bin/friday-lock" "$source_root/bin/managed-core.txt" "$kit/bin/"
  cp -R "$source_root/payload" "$kit/payload"
  git init -q -b main "$kit" && gq -C "$kit" add -A && gq -C "$kit" commit -q -m "payload v1"
  export GH_SHIM_LOG="$case_dir/gh"
  unset GH_SHIM_ONCE
}
# A consumer at the kit's current payload, committed, with a bare origin.
new_consumer() {
  local c="$case_dir/$1"
  git init -q --bare -b main "$c.git"
  git init -q -b main "$c"
  while IFS= read -r rel; do
    case "$rel" in ''|'#'*|'!'*) continue ;; esac
    mkdir -p "$c/$(dirname "$rel")"; cp -p "$kit/payload/$rel" "$c/$rel"
  done < "$kit/bin/managed-core.txt"
  bash "$kit/bin/friday-lock" write "$c" >/dev/null
  gq -C "$c" add -A && gq -C "$c" commit -q -m "chore: adopt v1"
  gq -C "$c" remote add origin "$c.git" && gq -C "$c" push -q origin main
}
m1() { grep -v -e '^#' -e '^!' -e '^[[:space:]]*$' "$kit/bin/managed-core.txt" | sed -n "${1}p"; }
bump() { printf '\n# %s\n' "$2" >> "$kit/payload/$1"; gq -C "$kit" commit -qam "payload: $2"; }
run() { PATH="$shim:$PATH" bash "$kit/bin/friday-propagate" "$@" > "$case_dir/run.log" 2>&1; }
on_branch() { git -C "$1" show "$2:$3"; }
lock_commit() { git -C "$1" show "$2:.friday-lock.json" | jq -r .friday.commit; }

# 1. An uncommitted edit under payload/ does not reach a consumer.
new_case; new_consumer c1
a=$(m1 1); b=$(m1 3)
bump "$a" v2; v2=$(git -C "$kit" rev-parse HEAD)
printf '\n# UNCOMMITTED\n' >> "$kit/payload/$a"
printf '\n# UNCOMMITTED\n' >> "$kit/payload/$b"
run "$case_dir/c1"
br="chore/sync-managed-core-${v2:0:7}"
check "uncommitted: the sync branch exists" git -C "$case_dir/c1" rev-parse -q --verify --quiet "$br"
check "uncommitted: the moved file carries the committed content" \
  bash -c "! git -C '$case_dir/c1' show '$br:$a' | grep -q UNCOMMITTED && git -C '$case_dir/c1' show '$br:$a' | grep -q 'v2'"
check "uncommitted: a file changed only in the working tree is not carried" \
  bash -c "! git -C '$case_dir/c1' show '$br:$b' | grep -q UNCOMMITTED"

# 2. A Friday commit made mid-run changes neither what a later consumer
#    receives nor what its lock records, and branch, lock and PR body agree.
new_case; new_consumer c1; new_consumer c2
a=$(m1 1)
bump "$a" v2; v2=$(git -C "$kit" rev-parse HEAD)
export GH_SHIM_ONCE="printf '\n# v3\n' >> '$kit/payload/$a' && git -C '$kit' -c user.name=t -c user.email=t@example.invalid commit -qam 'payload: v3'"
run "$case_dir/c1" "$case_dir/c2"
unset GH_SHIM_ONCE
br="chore/sync-managed-core-${v2:0:7}"
check "mid-run: the kit really did move during the run" bash -c "[ \"\$(git -C '$kit' rev-parse HEAD)\" != '$v2' ]"
check "mid-run: the second consumer gets the pinned content" \
  bash -c "git -C '$case_dir/c2' show '$br:$a' | grep -q v2 && ! git -C '$case_dir/c2' show '$br:$a' | grep -q v3"
check "mid-run: the second consumer's lock records the pinned commit" \
  bash -c "[ \"\$(git -C '$case_dir/c2' show '$br:.friday-lock.json' | jq -r .friday.commit)\" = '$v2' ]"
check "names agree: the first consumer's lock records the branch's commit" \
  bash -c "[ \"\$(git -C '$case_dir/c1' show '$br:.friday-lock.json' | jq -r .friday.commit)\" = '$v2' ]"
check "names agree: each PR body names the same commit" \
  bash -c "grep -q '$v2' '$GH_SHIM_LOG/1.args' && grep -q '$v2' '$GH_SHIM_LOG/2.args'"
check "after the run: both consumers are back on main" \
  bash -c "[ \"\$(git -C '$case_dir/c1' branch --show-current)\" = main ] && [ \"\$(git -C '$case_dir/c2' branch --show-current)\" = main ]"

# 3. A consumer file edited after the clean check is refused, not overwritten.
#    The edit lands the moment the sync branch is checked out, through the
#    consumer's own post-checkout hook.
new_case; new_consumer c1
a=$(m1 1)
bump "$a" v2; v2=$(git -C "$kit" rev-parse HEAD)
cat > "$case_dir/c1/.git/hooks/post-checkout" <<EOF
#!/bin/sh
case "\$(git symbolic-ref --short -q HEAD)" in chore/sync-managed-core-*)
  [ -e "$case_dir/edited" ] || { printf '\n# CONCURRENT EDIT\n' >> "$a"; touch "$case_dir/edited"; } ;;
esac
EOF
chmod +x "$case_dir/c1/.git/hooks/post-checkout"
run "$case_dir/c1"
check "concurrent edit: the run refuses the consumer" grep -q 'REFUSED' "$case_dir/run.log"
check "concurrent edit: the edit is still there" grep -q 'CONCURRENT EDIT' "$case_dir/c1/$a"
check "concurrent edit: no pull request was opened" bash -c "[ ! -e '$GH_SHIM_LOG/1.args' ]"

# 4. The run refuses a Friday checkout that is not on main.
new_case; new_consumer c1
bump "$(m1 1)" v2
git -C "$kit" switch -q -c feature
run "$case_dir/c1"; rc=$?
check "not on main: refused" bash -c "[ $rc != 0 ] && grep -q \"run from Friday's main\" '$case_dir/run.log'"

if command -v sha256sum >/dev/null; then sha() { sha256sum | cut -d' ' -f1; }; else sha() { shasum -a 256 | cut -d' ' -f1; }; fi

# 5. Detection reads the pinned tree too: a change only in Friday's working
#    tree is not a reason to call a consumer behind.
new_case; new_consumer c1
printf '\n# UNCOMMITTED\n' >> "$kit/payload/$(m1 1)"
run --dry-run "$case_dir/c1"
check "detection: an uncommitted Friday edit reads in sync" grep -q 'in sync — nothing to carry' "$case_dir/run.log"

# 6. A hook is carried with its executable mode.
new_case; new_consumer c1
bump .agents/githooks/pre-push v2; v2=$(git -C "$kit" rev-parse HEAD)
run "$case_dir/c1"
check "mode: a carried hook is 100755 on the sync branch" \
  bash -c "[ \"\$(git -C '$case_dir/c1' ls-tree 'chore/sync-managed-core-${v2:0:7}' -- .agents/githooks/pre-push | cut -d' ' -f1)\" = 100755 ]"

# 7. HEAD moved back to main after the branch was made -- by another run, or
#    here a post-checkout hook -- stops the run before anything is written.
new_case; new_consumer c1
bump "$(m1 1)" v2
cat > "$case_dir/c1/.git/hooks/post-checkout" <<EOF
#!/bin/sh
case "\$(git symbolic-ref --short -q HEAD)" in chore/sync-managed-core-*)
  [ -e "$case_dir/moved" ] || { touch "$case_dir/moved"; git checkout -q main; } ;;
esac
EOF
chmod +x "$case_dir/c1/.git/hooks/post-checkout"
main_before=$(git -C "$case_dir/c1" rev-parse main)
run "$case_dir/c1"
check "HEAD moved: refused" grep -q "REFUSED — HEAD is 'main'" "$case_dir/run.log"
check "HEAD moved: main gained no commit" bash -c "[ \"\$(git -C '$case_dir/c1' rev-parse main)\" = '$main_before' ]"
check "HEAD moved: nothing was written to main's tree" bash -c "[ -z \"\$(git -C '$case_dir/c1' status --porcelain)\" ]"

# 8. An edit to a managed file that is not being carried, landing after the
#    checks (here from post-index-change, fired by propagate's own `git add`),
#    is not written into the lock: the lock records what the commit holds.
new_case; new_consumer c1
a=$(m1 1); other=$(m1 3)
bump "$a" v2; v2=$(git -C "$kit" rev-parse HEAD)
# The hook fires on every index write, the first at `checkout -b`. It edits
# only once propagate has staged the carried file -- past every check, before
# the lock is written.
cat > "$case_dir/c1/.git/hooks/post-index-change" <<EOF
#!/bin/sh
[ -e "$case_dir/edited" ] && exit 0
git diff --cached --quiet -- "$a" && exit 0
touch "$case_dir/edited"; printf '\n# UNSTAGED EDIT\n' >> "$other"
EOF
chmod +x "$case_dir/c1/.git/hooks/post-index-change"
run "$case_dir/c1"
br="chore/sync-managed-core-${v2:0:7}"
check "unstaged edit: the sync branch was opened" git -C "$case_dir/c1" rev-parse -q --verify --quiet "$br"
check "unstaged edit: the edit really happened" grep -q 'UNSTAGED EDIT' "$case_dir/c1/$other"
lock_hash=$(git -C "$case_dir/c1" show "$br:.friday-lock.json" | jq -r --arg k "$other" '.managed_core[$k]')
committed_hash=$(git -C "$case_dir/c1" show "$br:$other" | sha)
check "unstaged edit: the lock records the committed content, not the edit" test "$lock_hash" = "$committed_hash"

# 9. main on the remote gained a commit that edits a managed file. The first
#    check saw the local main; the run pulls, and must notice the drift rather
#    than carry its change on top and launder the edit into the lock.
new_case; new_consumer c1
bump "$(m1 1)" v2
git clone -q "$case_dir/c1.git" "$case_dir/elsewhere"
printf '\n# EDITED ON THE REMOTE\n' >> "$case_dir/elsewhere/$(m1 3)"
gq -C "$case_dir/elsewhere" commit -qam "docs: edit a managed file" && gq -C "$case_dir/elsewhere" push -q origin main
run "$case_dir/c1"
check "remote drift: refused after the pull" grep -q "after pulling main the consumer reads 'drifted'" "$case_dir/run.log"
check "remote drift: no pull request was opened" bash -c "[ ! -e '$GH_SHIM_LOG/1.args' ]"
check "remote drift: the consumer is back on main" bash -c "[ \"\$(git -C '$case_dir/c1' branch --show-current)\" = main ]"

# 10. A file that joined the managed core: refused when the consumer has its
#     own version of it, and carried as a lock-only change when it matches.
reclassify() { sed -i.orig 's|^!\.agents/AGENTS\.md$|.agents/AGENTS.md|' "$kit/bin/managed-core.txt"; gq -C "$kit" commit -qam "payload: make .agents/AGENTS.md managed"; }
new_case; new_consumer c1
cp "$kit/payload/.agents/AGENTS.md" "$case_dir/c1/.agents/AGENTS.md"
printf '# Our own routing table\n' > "$case_dir/c1/.agents/AGENTS.md"
gq -C "$case_dir/c1" commit -qam "docs: our own routing" && gq -C "$case_dir/c1" push -q origin main
reclassify
run "$case_dir/c1"
check "joined, own version: refused" grep -q 'REFUSED — joined the managed core, and this repository has its own version: .agents/AGENTS.md' "$case_dir/run.log"
check "joined, own version: kept" grep -q 'Our own routing table' "$case_dir/c1/.agents/AGENTS.md"
new_case; new_consumer c1
cp "$kit/payload/.agents/AGENTS.md" "$case_dir/c1/.agents/AGENTS.md"
gq -C "$case_dir/c1" add -A && gq -C "$case_dir/c1" commit -qm "docs: take the seed as is" && gq -C "$case_dir/c1" push -q origin main
reclassify; v2=$(git -C "$kit" log -1 --format=%H -- payload/)
run "$case_dir/c1"
check "joined, matching: a lock-only sync is opened" bash -c "[ -e '$GH_SHIM_LOG/1.args' ]"
check "joined, matching: the lock now records it" \
  bash -c "git -C '$case_dir/c1' show 'chore/sync-managed-core-${v2:0:7}:.friday-lock.json' | jq -e '.managed_core | has(\".agents/AGENTS.md\")' >/dev/null"

# 11. friday-lock itself comes from the pin: a commit that changes it mid-run
#     does not change what a later consumer's lock records.
new_case; new_consumer c1; new_consumer c2
bump "$(m1 1)" v2; v2=$(git -C "$kit" rev-parse HEAD)
export GH_SHIM_ONCE="sed -i.orig 's/^friday_commit() {\$/friday_commit() { echo 0000000000000000000000000000000000000000; return; /' '$kit/bin/friday-lock' && git -C '$kit' -c user.name=t -c user.email=t@example.invalid commit -qam 'tooling: change friday-lock'"
run "$case_dir/c1" "$case_dir/c2"
unset GH_SHIM_ONCE
check "pinned lock: the kit's friday-lock really changed mid-run" grep -q '0000000000000000000000000000000000000000' "$kit/bin/friday-lock"
check "pinned lock: the second consumer's lock still records the pin" \
  bash -c "[ \"\$(git -C '$case_dir/c2' show 'chore/sync-managed-core-${v2:0:7}:.friday-lock.json' | jq -r .friday.commit)\" = '$v2' ]"

echo
if [ "$fails" -gt 0 ]; then echo "$fails of $total failed"; exit 1; fi
echo "all $total passed"
