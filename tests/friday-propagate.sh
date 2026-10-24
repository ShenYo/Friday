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
check "concurrent edit: the run refuses the consumer" grep -q 'REFUSED — changed in the consumer after it was checked' "$case_dir/run.log"
check "concurrent edit: the edit is still there" grep -q 'CONCURRENT EDIT' "$case_dir/c1/$a"
check "concurrent edit: no pull request was opened" bash -c "[ ! -e '$GH_SHIM_LOG/1.args' ]"

# 4. The run refuses a Friday checkout that is not on main.
new_case; new_consumer c1
bump "$(m1 1)" v2
git -C "$kit" switch -q -c feature
run "$case_dir/c1"; rc=$?
check "not on main: refused" bash -c "[ $rc != 0 ] && grep -q \"run from Friday's main\" '$case_dir/run.log'"

echo
if [ "$fails" -gt 0 ]; then echo "$fails of $total failed"; exit 1; fi
echo "all $total passed"
