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
  # A bare origin for the kit, with main and its first release on it: a run
  # refuses a release that origin does not hold.
  git init -q --bare -b main "$kit.git"
  gq -C "$kit" remote add origin "$kit.git"
  gq -C "$kit" tag -a v1.0.0 -m "release v1.0.0"
  gq -C "$kit" push -q origin main refs/tags/v1.0.0
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
# Cut a release on the kit's current commit, and publish it to the kit's origin.
release() { gq -C "$kit" tag -a "$1" -m "release $1" && gq -C "$kit" push -q origin "refs/tags/$1"; }
m1() { grep -v -e '^#' -e '^!' -e '^[[:space:]]*$' "$kit/bin/managed-core.txt" | sed -n "${1}p"; }
bump() { printf '\n# %s\n' "$2" >> "$kit/payload/$1"; gq -C "$kit" commit -qam "payload: $2"; }
run() { PATH="$shim:$PATH" bash "$kit/bin/friday-propagate" "$@" > "$case_dir/run.log" 2>&1; }
on_branch() { git -C "$1" show "$2:$3"; }
lock_commit() { git -C "$1" show "$2:.friday-lock.json" | jq -r .friday.commit; }

# 1. An uncommitted edit under payload/ does not reach a consumer.
new_case; new_consumer c1
a=$(m1 1); b=$(m1 3)
bump "$a" v2; release v1.1.0; v2=$(git -C "$kit" rev-parse HEAD)
printf '\n# UNCOMMITTED\n' >> "$kit/payload/$a"
printf '\n# UNCOMMITTED\n' >> "$kit/payload/$b"
run "$case_dir/c1"
br="chore/sync-managed-core-v1.1.0"
check "uncommitted: the sync branch exists" git -C "$case_dir/c1" rev-parse -q --verify --quiet "$br"
check "uncommitted: the moved file carries the committed content" \
  bash -c "! git -C '$case_dir/c1' show '$br:$a' | grep -q UNCOMMITTED && git -C '$case_dir/c1' show '$br:$a' | grep -q 'v2'"
check "uncommitted: a file changed only in the working tree is not carried" \
  bash -c "! git -C '$case_dir/c1' show '$br:$b' | grep -q UNCOMMITTED"

# 2. A Friday commit made mid-run changes neither what a later consumer
#    receives nor what its lock records, and branch, lock and PR body agree.
new_case; new_consumer c1; new_consumer c2
a=$(m1 1)
bump "$a" v2; release v1.1.0; v2=$(git -C "$kit" rev-parse HEAD)
export GH_SHIM_ONCE="printf '\n# v3\n' >> '$kit/payload/$a' && git -C '$kit' -c user.name=t -c user.email=t@example.invalid commit -qam 'payload: v3'"
run "$case_dir/c1" "$case_dir/c2"
unset GH_SHIM_ONCE
br="chore/sync-managed-core-v1.1.0"
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
bump "$a" v2; release v1.1.0
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
bump .agents/githooks/pre-push v2; release v1.1.0
run "$case_dir/c1"
check "mode: a carried hook is 100755 on the sync branch" \
  bash -c "[ \"\$(git -C '$case_dir/c1' ls-tree 'chore/sync-managed-core-v1.1.0' -- .agents/githooks/pre-push | cut -d' ' -f1)\" = 100755 ]"

# 7. HEAD moved back to main after the branch was made -- by another run, or
#    here a post-checkout hook -- stops the run before anything is written.
new_case; new_consumer c1
bump "$(m1 1)" v2; release v1.1.0
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
bump "$a" v2; release v1.1.0
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
br="chore/sync-managed-core-v1.1.0"
check "unstaged edit: the sync branch was opened" git -C "$case_dir/c1" rev-parse -q --verify --quiet "$br"
check "unstaged edit: the edit really happened" grep -q 'UNSTAGED EDIT' "$case_dir/c1/$other"
lock_hash=$(git -C "$case_dir/c1" show "$br:.friday-lock.json" | jq -r --arg k "$other" '.managed_core[$k]')
committed_hash=$(git -C "$case_dir/c1" show "$br:$other" | sha)
check "unstaged edit: the lock records the committed content, not the edit" test "$lock_hash" = "$committed_hash"

# 9. main on the remote gained a commit that edits a managed file. The first
#    check saw the local main; the run pulls, and must notice the drift rather
#    than carry its change on top and launder the edit into the lock.
new_case; new_consumer c1
bump "$(m1 1)" v2; release v1.1.0
git clone -q "$case_dir/c1.git" "$case_dir/elsewhere"
printf '\n# EDITED ON THE REMOTE\n' >> "$case_dir/elsewhere/$(m1 3)"
gq -C "$case_dir/elsewhere" commit -qam "docs: edit a managed file" && gq -C "$case_dir/elsewhere" push -q origin main
run "$case_dir/c1"
check "remote drift: refused after the pull" grep -q "after pulling main the consumer reads 'drifted'" "$case_dir/run.log"
check "remote drift: no pull request was opened" bash -c "[ ! -e '$GH_SHIM_LOG/1.args' ]"
check "remote drift: the consumer is back on main" bash -c "[ \"\$(git -C '$case_dir/c1' branch --show-current)\" = main ]"

# 10. A file that joined the managed core: refused when the consumer has its
#     own version of it, and carried as a lock-only change when it matches.
reclassify() { sed -i.orig 's|^!\.agents/AGENTS\.md$|.agents/AGENTS.md|' "$kit/bin/managed-core.txt"; gq -C "$kit" commit -qam "payload: make .agents/AGENTS.md managed"; release v1.1.0; }
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
reclassify
run "$case_dir/c1"
check "joined, matching: a lock-only sync is opened" bash -c "[ -e '$GH_SHIM_LOG/1.args' ]"
check "joined, matching: the lock now records it" \
  bash -c "git -C '$case_dir/c1' show 'chore/sync-managed-core-v1.1.0:.friday-lock.json' | jq -e '.managed_core | has(\".agents/AGENTS.md\")' >/dev/null"

# 11. friday-lock itself comes from the pin: a commit that changes it mid-run
#     does not change what a later consumer's lock records.
new_case; new_consumer c1; new_consumer c2
bump "$(m1 1)" v2; release v1.1.0; v2=$(git -C "$kit" rev-parse HEAD)
export GH_SHIM_ONCE="sed -i.orig 's/^friday_commit() {\$/friday_commit() { echo 0000000000000000000000000000000000000000; return; /' '$kit/bin/friday-lock' && git -C '$kit' -c user.name=t -c user.email=t@example.invalid commit -qam 'tooling: change friday-lock'"
run "$case_dir/c1" "$case_dir/c2"
unset GH_SHIM_ONCE
check "pinned lock: the kit's friday-lock really changed mid-run" grep -q '0000000000000000000000000000000000000000' "$kit/bin/friday-lock"
check "pinned lock: the second consumer's lock still records the pin" \
  bash -c "[ \"\$(git -C '$case_dir/c2' show 'chore/sync-managed-core-v1.1.0:.friday-lock.json' | jq -r .friday.commit)\" = '$v2' ]"

# --- releases ----------------------------------------------------------------

# 12. The default pins the newest tag by version, not by name or by main's HEAD.
new_case; new_consumer c1
a=$(m1 1); b=$(m1 3)
bump "$a" v2; release v1.9.0
bump "$b" v3; release v1.10.0; v3=$(git -C "$kit" rev-parse HEAD)
run "$case_dir/c1"
check "default tag: the branch carries the newest release by version" \
  git -C "$case_dir/c1" rev-parse -q --verify --quiet chore/sync-managed-core-v1.10.0
check "default tag: the consumer's lock records that release" \
  bash -c "[ \"\$(git -C '$case_dir/c1' show chore/sync-managed-core-v1.10.0:.friday-lock.json | jq -r .friday.tag)\" = v1.10.0 ]"
check "default tag: the lock keeps the commit as the record" \
  test "$(lock_commit "$case_dir/c1" chore/sync-managed-core-v1.10.0)" = "$v3"
check "default tag: the pull request title names the release" \
  grep -qxF 'chore(agents): sync the managed core to Friday v1.10.0' "$GH_SHIM_LOG/1.args"
check "default tag: the commit subject names the release" \
  bash -c "[ \"\$(git -C '$case_dir/c1' log -1 --format=%s chore/sync-managed-core-v1.10.0)\" = 'chore(agents): sync the managed core to Friday v1.10.0' ]"

# 13. --tag pins the one named, and what main holds past it is left behind.
new_case; new_consumer c1
a=$(m1 1); b=$(m1 3)
bump "$a" v2; release v1.1.0
bump "$b" v3; release v1.2.0
run --tag v1.1.0 "$case_dir/c1"
br=chore/sync-managed-core-v1.1.0
check "--tag: the named release is carried, the newer one is not" \
  bash -c "git -C '$case_dir/c1' rev-parse -q --verify --quiet '$br' >/dev/null && ! git -C '$case_dir/c1' rev-parse -q --verify --quiet chore/sync-managed-core-v1.2.0 >/dev/null"
check "--tag: the content is the named release's" \
  bash -c "git -C '$case_dir/c1' show '$br:$a' | grep -q v2 && ! git -C '$case_dir/c1' show '$br:$b' | grep -q v3"
check "--tag: the lock records the named release" \
  bash -c "[ \"\$(git -C '$case_dir/c1' show '$br:.friday-lock.json' | jq -r .friday.tag)\" = v1.1.0 ]"

# 14. Nothing is carried without a release, or from one that is not there.
new_case; new_consumer c1
bump "$(m1 1)" v2
gq -C "$kit" tag -d v1.0.0 >/dev/null
run "$case_dir/c1"; rc=$?
check "no tag: refused" bash -c "[ $rc != 0 ] && grep -q 'no release tag' '$case_dir/run.log'"
check "no tag: nothing written to the consumer" \
  bash -c "[ -z \"\$(git -C '$case_dir/c1' branch --list 'chore/*')\" ] && [ -z \"\$(git -C '$case_dir/c1' status --porcelain)\" ] && [ ! -e '$GH_SHIM_LOG/1.args' ]"

new_case; new_consumer c1
bump "$(m1 1)" v2; release v1.1.0
run --tag v9.9.9 "$case_dir/c1"; rc=$?
check "missing --tag: refused" bash -c "[ $rc != 0 ] && grep -q 'no such release tag: v9.9.9' '$case_dir/run.log'"
check "missing --tag: nothing written to the consumer" \
  bash -c "[ -z \"\$(git -C '$case_dir/c1' branch --list 'chore/*')\" ] && [ ! -e '$GH_SHIM_LOG/1.args' ]"

# 15. A tag on a commit main does not contain is refused.
new_case; new_consumer c1
git -C "$kit" switch -q -c elsewhere
bump "$(m1 1)" v2; release v2.0.0
git -C "$kit" switch -q main
run --tag v2.0.0 "$case_dir/c1"; rc=$?
check "tag off main: refused, and nothing written to the consumer" \
  bash -c "[ $rc != 0 ] && grep -q 'is not on Friday.s main' '$case_dir/run.log' && [ -z \"\$(git -C '$case_dir/c1' branch --list 'chore/*')\" ] && [ ! -e '$GH_SHIM_LOG/1.args' ]"

# 16. A payload change on main with no tag is not carried, and the run says so.
new_case; new_consumer c1
a=$(m1 1); b=$(m1 3)
bump "$a" v2; release v1.1.0
bump "$b" UNRELEASED
run "$case_dir/c1"
br=chore/sync-managed-core-v1.1.0
check "unreleased: the note says main is ahead of the release" \
  grep -q 'main has payload changes not yet released; only v1.1.0 is carried' "$case_dir/run.log"
check "unreleased: the released change is carried and the unreleased one is not" \
  bash -c "git -C '$case_dir/c1' show '$br:$a' | grep -q v2 && ! git -C '$case_dir/c1' show '$br:$b' | grep -q UNRELEASED"
new_case; new_consumer c1
bump "$(m1 1)" v2; release v1.1.0
run "$case_dir/c1"
check "released: carried with no note when main holds nothing past the release" \
  bash -c "git -C '$case_dir/c1' rev-parse -q --verify --quiet chore/sync-managed-core-v1.1.0 >/dev/null && ! grep -q 'not yet released' '$case_dir/run.log'"

# 17. The pull request lists the payload commits between the old release and
#     the new one -- and only those.
new_case; new_consumer c1
a=$(m1 1)
bump "$a" first; release v1.1.0; first=$(git -C "$kit" log -1 --format=%h)
printf 'notes\n' > "$kit/NOTES"; gq -C "$kit" add NOTES; gq -C "$kit" commit -qm "docs: not a payload commit"
bump "$a" second; release v1.2.0; second=$(git -C "$kit" log -1 --format=%h)
run "$case_dir/c1"
body="$GH_SHIM_LOG/1.args"
check "pr body: lists the first payload commit since the old release" grep -qxF -- "- $first payload: first" "$body"
check "pr body: lists the second, and leaves out a commit that moved no payload" \
  bash -c "grep -qxF -- '- $second payload: second' '$body' && ! grep -q 'not a payload commit' '$body'"
check "pr body: names the release it was listed from" grep -q 'since `v1.0.0`' "$body"

# ... from the consumer's commit when its lock has no tag, and says so when
# neither can be found.
new_case; new_consumer c1
jq 'del(.friday.tag)' "$case_dir/c1/.friday-lock.json" > "$case_dir/lock" && cp "$case_dir/lock" "$case_dir/c1/.friday-lock.json"
gq -C "$case_dir/c1" commit -qam "chore: an old-style lock" && gq -C "$case_dir/c1" push -q origin main
bump "$(m1 1)" only; release v1.1.0; only=$(git -C "$kit" log -1 --format=%h)
run "$case_dir/c1"
check "pr body: a lock with no tag lists from its commit" grep -qxF -- "- $only payload: only" "$GH_SHIM_LOG/1.args"

new_case; new_consumer c1
jq '.friday.tag = null | .friday.commit = "0000000000000000000000000000000000000000"' "$case_dir/c1/.friday-lock.json" > "$case_dir/lock" \
  && cp "$case_dir/lock" "$case_dir/c1/.friday-lock.json"
gq -C "$case_dir/c1" commit -qam "chore: an unknown commit" && gq -C "$case_dir/c1" push -q origin main
bump "$(m1 1)" only; release v1.1.0
run "$case_dir/c1"
check "pr body: an unresolvable starting point is said, not guessed" \
  grep -q 'could not be found in Friday, so what changed since is not listed' "$GH_SHIM_LOG/1.args"

# 18. --tag the older of two releases with equal payload: the lock records the
#     one that was named, not the newer one that merely carries the same content.
new_case; new_consumer c1
bump "$(m1 1)" v2; release v1.1.0
printf 'notes\n' > "$kit/NOTES"; gq -C "$kit" add NOTES; gq -C "$kit" commit -qm "docs: notes"; release v1.1.1
run --tag v1.1.0 "$case_dir/c1"
check "equal-content tags: the lock records the tag that was named" \
  bash -c "[ \"\$(git -C '$case_dir/c1' show chore/sync-managed-core-v1.1.0:.friday-lock.json | jq -r .friday.tag)\" = v1.1.0 ]"

# 19. A consumer whose lock records a tag that has since moved is not touched.
new_case; new_consumer c1
a=$(m1 1)
bump "$a" v2; release v1.1.0
gq -C "$kit" tag -f -a v1.0.0 -m "moved" >/dev/null
run "$case_dir/c1"; rc=$?
check "tag moved: reported by name, and the run is not clean" \
  bash -c "[ $rc != 0 ] && grep -q 'TAG MOVED — this lock records release v1.0.0' '$case_dir/run.log' && grep -q 'refused=1' '$case_dir/run.log'"
check "tag moved: nothing was written to the consumer" \
  bash -c "[ -z \"\$(git -C '$case_dir/c1' branch --list 'chore/*')\" ] && [ -z \"\$(git -C '$case_dir/c1' status --porcelain)\" ] && [ ! -e '$GH_SHIM_LOG/1.args' ]"

# 20. Two tags on one commit: the one named is the one the lock records.
new_case; new_consumer c1
bump "$(m1 1)" v2; release v1.1.0; release v1.1.1
run --tag v1.1.0 "$case_dir/c1"
check "one commit, two tags: the lock records the tag that was named" \
  bash -c "[ \"\$(git -C '$case_dir/c1' show chore/sync-managed-core-v1.1.0:.friday-lock.json | jq -r .friday.tag)\" = v1.1.0 ]"

# 21. A release is exactly vMAJOR.MINOR.PATCH.
new_case; new_consumer c1
bump "$(m1 1)" v2; release v1.1.0
bump "$(m1 3)" v3; release v1.2.0-rc1
run "$case_dir/c1"
check "pre-release: the default skips a newer pre-release tag" \
  git -C "$case_dir/c1" rev-parse -q --verify --quiet chore/sync-managed-core-v1.1.0
new_case; new_consumer c1
bump "$(m1 1)" v2; release v1.2.0-rc1; release v1x
run --tag v1.2.0-rc1 "$case_dir/c1"; rc=$?
check "pre-release: --tag naming one is refused, nothing written" \
  bash -c "[ $rc != 0 ] && grep -q 'not a release tag' '$case_dir/run.log' && [ -z \"\$(git -C '$case_dir/c1' branch --list 'chore/*')\" ] && [ ! -e '$GH_SHIM_LOG/1.args' ]"
run --tag v1x "$case_dir/c1"; rc=$?
check "malformed: --tag naming one is refused" bash -c "[ $rc != 0 ] && grep -q 'not a release tag' '$case_dir/run.log'"
new_case; new_consumer c1
bump "$(m1 1)" v2; release v1.2.0-rc1
gq -C "$kit" tag -d v1.0.0 >/dev/null
run "$case_dir/c1"; rc=$?
check "pre-release only: counts as no release" bash -c "[ $rc != 0 ] && grep -q 'no release tag' '$case_dir/run.log'"

# 22. The pinned tag must be annotated, and origin must hold that very tag.
new_case; new_consumer c1
bump "$(m1 1)" v2
gq -C "$kit" tag v1.1.0 && gq -C "$kit" push -q origin refs/tags/v1.1.0
run "$case_dir/c1"; rc=$?
check "lightweight tag: refused, nothing written" \
  bash -c "[ $rc != 0 ] && grep -q 'not an annotated tag' '$case_dir/run.log' && [ -z \"\$(git -C '$case_dir/c1' branch --list 'chore/*')\" ] && [ ! -e '$GH_SHIM_LOG/1.args' ]"
new_case; new_consumer c1
bump "$(m1 1)" v2
gq -C "$kit" tag -a v1.1.0 -m "local only"
run "$case_dir/c1"; rc=$?
check "tag not on origin: refused, nothing written" \
  bash -c "[ $rc != 0 ] && grep -q 'is not on origin' '$case_dir/run.log' && [ -z \"\$(git -C '$case_dir/c1' branch --list 'chore/*')\" ] && [ ! -e '$GH_SHIM_LOG/1.args' ]"
new_case; new_consumer c1
bump "$(m1 1)" v2; release v1.1.0
bump "$(m1 1)" v3
gq -C "$kit" tag -f -a v1.1.0 -m "moved locally" >/dev/null
run "$case_dir/c1"; rc=$?
check "origin's tag elsewhere: refused, nothing written" \
  bash -c "[ $rc != 0 ] && grep -q \"origin's v1.1.0 points at a different tag object\" '$case_dir/run.log' && [ -z \"\$(git -C '$case_dir/c1' branch --list 'chore/*')\" ] && [ ! -e '$GH_SHIM_LOG/1.args' ]"

# 23. --tag needs a value.
new_case; new_consumer c1
bump "$(m1 1)" v2; release v1.1.0
run --tag "" "$case_dir/c1"; rc1=$?
l1=$(cat "$case_dir/run.log")
run --tag; rc2=$?
check "--tag with no value dies with usage" \
  bash -c "[ $rc1 = 2 ] && [ $rc2 = 2 ] && printf '%s' '$l1' | grep -q 'usage:' && grep -q 'usage:' '$case_dir/run.log' && [ -z \"\$(git -C '$case_dir/c1' branch --list 'chore/*')\" ]"

echo
if [ "$fails" -gt 0 ]; then echo "$fails of $total failed"; exit 1; fi
echo "all $total passed"
