#!/usr/bin/env bash
# End-to-end tests for install.sh's release install and --managed-only.
#
#   bash tests/install-release.sh [retained-output-directory]
#
# What is proven: install.sh installs a release -- the newest, or the one named
# -- by exporting its tree and running that tree's own install.sh, so the
# checkout's branch and uncommitted edits cannot reach a target; it refuses a
# tag friday-propagate would refuse; --working-tree keeps the old behaviour with
# a warning; and --managed-only copies only the managed core and lists the seeds.
#
# Each case builds a scratch Friday (bin/ + payload/ + install.sh, in a Git
# repository of its own, on main, with a local bare origin) and scratch targets.
# The first release in it carries an installer that predates --working-tree,
# as v1.0.0 and v1.0.1 do. INSTALL_UNDER_TEST=<path> runs the suite against
# another install.sh, which is how a case is shown to fail on the old one.
# Sandboxes are left in place under the printed directory.
set -uo pipefail
[ "$#" -le 1 ] || { echo "usage: $0 [retained-output-directory]" >&2; exit 2; }

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
installer=${INSTALL_UNDER_TEST:-$source_root/install.sh}
base=${1:-${TMPDIR:-/tmp}}
mkdir -p "$base"
root=$(mktemp -d "$base/install-release-test.XXXXXX")
echo "sandboxes: $root"

fails=0
total=0
ok()   { total=$((total + 1)); echo "ok   $1"; }
fail() { total=$((total + 1)); echo "FAIL $1"; fails=$((fails + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else fail "$name"; fi; }
gq() { git -c user.name=t -c user.email=t@example.invalid "$@"; }

# Hermetic: no global or system Git config, and a fixed identity. An empty
# global config of our own keeps a core.hooksPath on the machine out of targets.
export GIT_CONFIG_GLOBAL="$root/global.gitconfig" GIT_CONFIG_NOSYSTEM=1
# A scratch directory kept inside some other checkout must not make the copy of
# Friday that has no .git of its own look like part of it.
export GIT_CEILING_DIRECTORIES="$root"
: > "$GIT_CONFIG_GLOBAL"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset FRIDAY_KIT_ROOT FRIDAY_TREE FRIDAY_RELEASE FRIDAY_LOCK_FROM_INDEX

managed_rels() { grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' -e '^!' "$source_root/bin/managed-core.txt"; }
seed_rels() { grep -e '^!' "$source_root/bin/managed-core.txt" | sed 's/^!//'; }
testing_md=.agents/docs/testing.md

# --- fixtures -----------------------------------------------------------------
# A stand-in for the installer of a release that predates --working-tree: the
# old interface, [--check] [target], installing its own tree. It leaves a mark
# so a case can tell which installer ran.
write_old_installer() { # <path>
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
# A later installer takes --as-release; this one does not, whatever its text says.
set -euo pipefail
KIT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
check_only=false
if [ "${1:-}" = "--check" ]; then check_only=true; shift; fi
if [ "$#" -gt 1 ] || [[ "${1:-}" = -* ]]; then echo "usage: $0 [--check] [target-repo-path]" >&2; exit 2; fi
TARGET=$(cd "${1:-.}" && pwd)
echo "old-interface installer ran from $KIT_ROOT"
files=()
while IFS= read -r line; do
  line=${line%%#*}; line=${line//[[:space:]]/}
  [ -n "$line" ] && files+=("${line#!}")
done < "$KIT_ROOT/bin/managed-core.txt"
for rel in "${files[@]}"; do
  if $check_only; then echo "NEW $rel"; continue; fi
  mkdir -p "$TARGET/$(dirname "$rel")"
  cp "$KIT_ROOT/payload/$rel" "$TARGET/$rel"
done
if $check_only; then exit 0; fi
bash "$KIT_ROOT/bin/friday-lock" write "$TARGET"
EOF
}

n=0
bump() { printf '\n# %s\n' "$1" >> "$kit/payload/$testing_md"; gq -C "$kit" add -A; gq -C "$kit" commit -q -m "payload: $1"; }
# An annotated release tag on the kit's current commit, with main and the tag on origin.
release() {
  gq -C "$kit" tag -a "$1" -m "release $1"
  gq -C "$kit" push -q origin main "refs/tags/$1"
}
# A Friday checkout whose history is: release one (an old installer), then
# release two (the installer under test). Left on main, clean.
new_kit() {
  n=$((n + 1)); case_dir="$root/$n"; kit="$case_dir/kit"; tmp="$case_dir/tmp"
  mkdir -p "$kit/bin" "$tmp"
  cp "$source_root/bin/friday-lock" "$source_root/bin/managed-core.txt" "$kit/bin/"
  cp -R "$source_root/payload" "$kit/payload"
  git init -q -b main "$kit"
  git init -q --bare -b main "$kit.git"
  gq -C "$kit" remote add origin "$kit.git"
  write_old_installer "$kit/install.sh"
  bump "release one"; release v1.0.0
  cp "$installer" "$kit/install.sh"
  bump "release two"; release v1.1.0
}
# A Friday with no release at all.
new_unreleased_kit() {
  n=$((n + 1)); case_dir="$root/$n"; kit="$case_dir/kit"; tmp="$case_dir/tmp"
  mkdir -p "$kit/bin" "$tmp"
  cp "$installer" "$kit/install.sh"
  cp "$source_root/bin/friday-lock" "$source_root/bin/managed-core.txt" "$kit/bin/"
  cp -R "$source_root/payload" "$kit/payload"
  git init -q -b main "$kit"
  git init -q --bare -b main "$kit.git"
  gq -C "$kit" remote add origin "$kit.git"
  gq -C "$kit" add -A; gq -C "$kit" commit -q -m "payload"
  gq -C "$kit" push -q origin main
}
# What a developer's checkout looks like: a feature branch with an unreleased edit.
dirty_kit() {
  gq -C "$kit" switch -q -c feature/wip
  printf '\n# UNRELEASED\n' >> "$kit/payload/$testing_md"
}
new_target() { t="$case_dir/$1"; git init -q -b main "$t"; }
# A project that already has its own pointers, routing, ignore rules and wiring.
new_existing() {
  t="$case_dir/$1"; git init -q -b main "$t"
  mkdir -p "$t/.agents" "$t/.claude" "$t/.codex"
  printf '# My project\nRead .agents/AGENTS.md.\n' > "$t/AGENTS.md"
  printf 'my own claude pointer\n' > "$t/CLAUDE.md"
  printf '# My routing\n' > "$t/.agents/AGENTS.md"
  printf 'node_modules/\n' > "$t/.gitignore"
  jq '.hooks.PreToolUse += [{"matcher":"Write","hooks":[{"type":"command","command":"true"}]}]' \
    "$source_root/payload/.claude/settings.json" > "$t/.claude/settings.json"
  cp "$source_root/payload/.codex/hooks.json" "$t/.codex/hooks.json"
  gq -C "$t" add -A; gq -C "$t" commit -q -m "chore: our own agent files"
}
inst() { # <args...>: runs the kit's install.sh (or ${kit_dir}'s); sets rc, log
  log="$case_dir/out.log"
  TMPDIR="$tmp" bash "${kit_dir:-$kit}/install.sh" "$@" > "$log" 2>&1; rc=$?
}
# The same with the variables a release install hands to the exported copy.
inst_as() { # <kit root> <tree> <release> <args...>
  local kr=$1 tr=$2 rl=$3; shift 3
  log="$case_dir/out.log"
  FRIDAY_KIT_ROOT=$kr FRIDAY_TREE=$tr FRIDAY_RELEASE=$rl TMPDIR="$tmp" bash "$kit/install.sh" "$@" > "$log" 2>&1; rc=$?
}

# --- predicates ---------------------------------------------------------------
has() { grep -q -e "$1" "$2"; }
lacks() { ! grep -q -e "$1" "$2"; }
rc_is() { [ "$rc" -eq "$1" ]; }
rc_fails() { [ "$rc" -ne 0 ]; }
untouched() { [ ! -e "$1/.agents" ] && [ ! -e "$1/.friday-lock.json" ] && [ ! -e "$1/.claude/hooks" ]; }
# An existing project has its own .agents/AGENTS.md; none of the managed core, no lock.
untouched_existing() { [ ! -e "$1/.agents/docs" ] && [ ! -e "$1/.agents/githooks" ] && [ ! -e "$1/.friday-lock.json" ] && [ ! -e "$1/.claude/hooks" ]; }
lock_is() { [ "$(jq -r "$1" "$t/.friday-lock.json")" = "$2" ]; }
# Every managed file in the target holds the bytes <tag> carries.
managed_match() { # <tag> <target>
  local rel
  while IFS= read -r rel; do
    git -C "$kit" show "$1:payload/$rel" | cmp -s - "$2/$rel" || { echo "differs from $1: $rel" >&2; return 1; }
  done < <(managed_rels)
}
kit_state() { printf '%s|%s|%s\n' "$(git -C "$kit" symbolic-ref --short -q HEAD)" "$(git -C "$kit" rev-parse HEAD)" "$(git -C "$kit" status --porcelain)"; }
seed_sum() { (cd "$1" && cat AGENTS.md CLAUDE.md .agents/AGENTS.md .gitignore .claude/settings.json .codex/hooks.json | cksum); }
payload_commit() { git -C "$kit" log -1 --format=%H "$1" -- payload/; }
# Every line of the log is one the managed-only preview is allowed to print.
only_identical_and_seed() { ! grep -v -e '^IDENTICAL ' -e '^SEED ' -e '^release: ' "$1" | grep -q .; }
# What an install leaves in TMPDIR: its own export, and anything the payload's
# self-check creates. The bare origins are this suite's own fixtures.
leftovers() {
  local l
  l=$(ls -A "$tmp" | grep -vE '^origin(-[a-z]+)?\.git$')
  [ -z "$l" ] || { echo "left in TMPDIR: $l" >&2; false; }
}
# The run failed and said <pattern>; the run succeeded and said it.
refused_with() { rc_fails && has "$1" "$log"; }
ok_with() { rc_is 0 && has "$1" "$log"; }
# friday-lock, pinned to a release the way a propagation run pins it, reads the target in sync.
lock_in_sync() { FRIDAY_TREE=$(git -C "$kit" rev-parse "$1^{commit}") bash "$kit/bin/friday-lock" check "$2" | grep -q 'status: in sync'; }

# 1. The default is the newest release, however the checkout stands.
new_kit; new_target c1; dirty_kit
before=$(kit_state)
inst "$t"
check "default: exits 0" rc_is 0
check "default: names the release it installs" has '^release: v1.1.0 ' "$log"
check "default: every managed file has the release's bytes" managed_match v1.1.0 "$t"
check "default: the uncommitted edit is not carried" lacks UNRELEASED "$t/$testing_md"
check "default: the lock records the release's tag" lock_is .friday.tag v1.1.0
check "default: the lock records the release's payload commit" lock_is .friday.commit "$(payload_commit v1.1.0)"
check "default: friday-lock reads the target in sync with the release" lock_in_sync v1.1.0 "$t"
check "default: the self-check passed" has 'self-check passed' "$log"
check "default: the checkout is as it was (branch, HEAD, edits)" [ "$(kit_state)" = "$before" ]
check "default: the temporary export is removed" leftovers
check "default: the checkout's edit is still there" has UNRELEASED "$kit/payload/$testing_md"

# 2. --release names one, and a release older than the flags installs under its old interface.
new_kit; new_target c2; dirty_kit
inst --release v1.0.0 "$t"
check "--release: exits 0" rc_is 0
check "--release: the release's own (old) installer ran" has 'old-interface installer ran from' "$log"
check "--release: it ran from an export, not from the checkout" lacks "old-interface installer ran from $kit\$" "$log"
check "--release: the older release's bytes" managed_match v1.0.0 "$t"
check "--release: not the newer release's" lacks 'release two' "$t/$testing_md"
check "--release: the lock records the older tag" lock_is .friday.tag v1.0.0
check "--release: the lock records the older release's payload commit" lock_is .friday.commit "$(payload_commit v1.0.0)"
new_target c2b
inst --check --release v1.0.0 "$t"
check "--release --check on an old installer: exits 0 and lists files" ok_with '^NEW .agents/docs/testing.md'
check "--release --check on an old installer: writes nothing" untouched "$t"
new_target c2c
inst --release v1.1.0 "$t"
check "--release of the newest: exits 0 and names it" ok_with '^release: v1.1.0 '
check "--release of the newest: the new installer ran, not the old" lacks 'old-interface installer ran' "$log"

# 3. The newest means the newest by version order, of the exact form.
new_kit
git -C "$kit" tag -a v1.2.0-rc1 -m rc; git -C "$kit" tag -a v1x -m malformed
git -C "$kit" push -q origin refs/tags/v1.2.0-rc1 refs/tags/v1x
bump "release three"; release v1.9.0; git -C "$kit" tag -a v1.10.0 -m "release v1.10.0"; git -C "$kit" push -q origin refs/tags/v1.10.0
new_target c3; inst "$t"
check "newest: version order, not text order" has '^release: v1.10.0 ' "$log"
check "newest: a pre-release and a malformed tag are no release" lock_is .friday.tag v1.10.0
new_target c3b; inst --check "$t"
check "newest: --check names the release too" has '^release: v1.10.0 ' "$log"

# 4. No release: refused, saying how to cut or fetch one, writing nothing.
new_unreleased_kit; new_target c4; inst "$t"
check "no release: refused" rc_fails
check "no release: says there is none" has 'no release tag' "$log"
check "no release: says how to fetch or cut one" bash -c "grep -q 'fetch' '$log' && grep -q 'git tag -a' '$log'"
check "no release: nothing was written" untouched "$t"
inst --check "$t"
check "no release: --check refuses too" rc_fails
inst --working-tree "$t"
check "no release: --working-tree still installs" rc_is 0

# 5. A lightweight tag, one only here, one origin holds differently, one off main.
new_kit; new_target c5
git -C "$kit" tag v1.2.0; git -C "$kit" push -q origin refs/tags/v1.2.0
inst "$t"
check "lightweight: refused" rc_fails
check "lightweight: says it is not annotated" has 'not an annotated tag' "$log"
check "lightweight: nothing was written" untouched "$t"
inst --release v1.1.0 "$t"
check "lightweight: the named annotated release still installs" rc_is 0

new_kit; new_target c6
gq -C "$kit" tag -a v1.2.0 -m "only here"
inst "$t"
check "local only: refused, not on origin" refused_with 'not on origin'
check "local only: nothing was written" untouched "$t"

new_kit; new_target c7
gq -C "$kit" tag -a v1.2.0 -m "first"; git -C "$kit" push -q origin refs/tags/v1.2.0
gq -C "$kit" tag -f -a v1.2.0 -m "moved" >/dev/null 2>&1
inst "$t"
check "moved tag: refused, origin holds a different tag object" refused_with 'different tag object'
check "moved tag: nothing was written" untouched "$t"

new_kit; new_target c8
gq -C "$kit" switch -q -c unmerged; bump "unmerged work"
gq -C "$kit" tag -a v1.2.0 -m "unmerged"; git -C "$kit" push -q origin refs/tags/v1.2.0
gq -C "$kit" switch -q main
inst "$t"
check "off main: refused" refused_with "not on Friday's main"
check "off main: nothing was written" untouched "$t"
inst --release v1.2.0 "$t"
check "off main: --release refuses it too" refused_with "not on Friday's main"

# 6. What --release will not take.
new_kit; new_target c9
for bad in v1.1 v1.2.0-rc1 main 1.1.0 v9.9.9; do
  inst --release "$bad" "$t"
  check "--release $bad: refused as no release" refused_with 'release tag'
  check "--release $bad: nothing was written" untouched "$t"
done
inst --release v9.9.9 "$t"
check "--release of an unknown tag: says how to fetch" has 'no such release tag' "$log"
inst --release v1.1.0 --working-tree "$t"
check "--release with --working-tree: a usage error" bash -c "[ $rc -eq 2 ] && grep -q 'alternatives' '$log'"
inst --release
check "--release without a tag: a usage error" bash -c "[ $rc -eq 2 ] && grep -q 'usage:.*--release' '$log'"
inst --unknown "$t"
check "an unknown option: a usage error" rc_is 2
inst "$t" extra
check "two targets: a usage error" rc_is 2

# 7. --working-tree is the old behaviour, warned about, with an honest lock.
new_kit; new_target c10; dirty_kit
inst --working-tree "$t"
check "--working-tree: exits 0" rc_is 0
check "--working-tree: installs the checkout's edit" has UNRELEASED "$t/$testing_md"
check "--working-tree: says it is not a release" has 'not a release' "$log"
check "--working-tree: says the payload is uncommitted" has 'uncommitted changes' "$log"
check "--working-tree: the lock names no tag for an unreleased payload" lock_is '.friday.tag' null
check "--working-tree: no export, no release line" lacks '^release: ' "$log"
new_kit; new_target c10b
inst --working-tree "$t"
check "--working-tree on a clean checkout: still warns" has 'not a release' "$log"
check "--working-tree on a clean checkout: the lock names the release it matches" lock_is .friday.tag v1.1.0
new_kit; new_target c10c
inst_as /nonexistent 0000000000000000000000000000000000000000 v9.9.9 --working-tree "$t"
check "--working-tree: a caller's FRIDAY_TREE and FRIDAY_KIT_ROOT are ignored" bash -c "[ $rc -eq 0 ] && [ -f '$t/.friday-lock.json' ]"
check "--working-tree: and so is a caller's FRIDAY_RELEASE (a clean checkout names its own release)" lock_is .friday.tag v1.1.0

# 8. Prerequisites and the kit itself.
new_kit; new_target c11
mkdir -p "$case_dir/no-jq-bin"; ln -s /usr/bin/dirname "$case_dir/no-jq-bin/dirname"
PATH="$case_dir/no-jq-bin" /bin/bash "$kit/install.sh" "$t" > "$case_dir/out.log" 2>&1; rc=$?; log="$case_dir/out.log"
check "no jq: refused before anything is exported" refused_with "'jq' is required"
check "no jq: nothing was written" untouched "$t"
inst "$kit"
check "the kit is not a target" refused_with 'into itself'
mkdir -p "$case_dir/copy"
cp -R "$kit/install.sh" "$kit/bin" "$kit/payload" "$case_dir/copy/"
new_target c11b
TMPDIR="$tmp" bash "$case_dir/copy/install.sh" "$t" > "$case_dir/out.log" 2>&1; rc=$?; log="$case_dir/out.log"
check "no Git history: refused, pointing at --working-tree" refused_with '--working-tree'
TMPDIR="$tmp" bash "$case_dir/copy/install.sh" --working-tree "$t" > "$case_dir/out.log" 2>&1; rc=$?
check "no Git history: --working-tree installs the copy" rc_is 0

# 9. --managed-only on an existing project.
new_kit; new_existing e1
before=$(seed_sum "$t")
inst --managed-only --check "$t"
check "managed-only --check: exits 0 although the seeds differ" rc_is 0
check "managed-only --check: lists the differing seeds as SEED" \
  bash -c "grep -q '^SEED AGENTS.md (yours; not touched)' '$log' && grep -q '^SEED .agents/AGENTS.md (yours; not touched)' '$log' && grep -q '^SEED .gitignore (yours; not touched)' '$log' && grep -q '^SEED .claude/settings.json (yours; not touched)' '$log'"
check "managed-only --check: lists an identical seed as SEED too" has '^SEED .codex/hooks.json (identical' "$log"
check "managed-only --check: no CONFLICT" lacks '^CONFLICT' "$log"
check "managed-only --check: seeds are not offered as NEW" lacks '^NEW AGENTS.md' "$log"
check "managed-only --check: managed files are offered as NEW" has '^NEW .agents/docs/testing.md' "$log"
check "managed-only --check: writes nothing" bash -c "[ ! -e '$t/.agents/docs' ] && [ ! -e '$t/.friday-lock.json' ]"
inst --check "$t"
check "without --managed-only the same project is refused" refused_with '^CONFLICT AGENTS.md'

dirty_kit
inst --managed-only "$t"
check "managed-only: exits 0" rc_is 0
check "managed-only: the release's managed bytes" managed_match v1.1.0 "$t"
check "managed-only: not the checkout's edit" lacks UNRELEASED "$t/$testing_md"
check "managed-only: the seeds are byte for byte the project's" [ "$(seed_sum "$t")" = "$before" ]
check "managed-only: the project's own routing line survived" has '^# My routing' "$t/.agents/AGENTS.md"
check "managed-only: the lock names the release" lock_is .friday.tag v1.1.0
check "managed-only: the lock records only managed files" \
  bash -c "[ \"\$(jq -r '.managed_core | keys | length' '$t/.friday-lock.json')\" = \"$(managed_rels | wc -l | tr -d ' ')\" ] && ! jq -e '.managed_core | has(\"AGENTS.md\") or has(\".gitignore\")' '$t/.friday-lock.json' >/dev/null"
check "managed-only: setup.sh ran (hooksPath wired)" [ "$(git -C "$t" config --local core.hooksPath)" = .agents/githooks ]
check "managed-only: the self-check passed" has 'self-check passed' "$log"
inst --managed-only --check "$t"
check "managed-only, installed: --check exits 0" rc_is 0
check "managed-only, installed: nothing but IDENTICAL and SEED" only_identical_and_seed "$log"
check "managed-only, installed: every managed file reads IDENTICAL" \
  bash -c "while IFS= read -r rel; do grep -q \"^IDENTICAL \$rel\$\" '$log' || exit 1; done < <(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*\$' -e '^!' '$source_root/bin/managed-core.txt')"
check "managed-only, installed: the seeds read SEED" has '^SEED AGENTS.md ' "$log"

# 10. --managed-only against a release whose installer predates it.
new_kit; new_existing e2
before=$(seed_sum "$t")
inst --managed-only --release v1.0.0 "$t"
check "managed-only, old release: exits 0" rc_is 0
check "managed-only, old release: the release's own installer ran" has 'old-interface installer ran' "$log"
check "managed-only, old release: lists the seeds as SEED" has '^SEED AGENTS.md (yours; not touched)' "$log"
check "managed-only, old release: the seeds are untouched" [ "$(seed_sum "$t")" = "$before" ]
check "managed-only, old release: the managed core is that release's" managed_match v1.0.0 "$t"
check "managed-only, old release: the lock names that release" lock_is .friday.tag v1.0.0
check "managed-only, old release: the lock lists no seed" \
  bash -c "! jq -e '.managed_core | has(\"AGENTS.md\") or has(\".gitignore\") or has(\".claude/settings.json\")' '$t/.friday-lock.json' >/dev/null"
new_existing e2b
inst --managed-only --check --release v1.0.0 "$t"
check "managed-only --check, old release: writes nothing" bash -c "[ $rc -eq 0 ] && [ ! -e '$t/.agents/docs' ]"

# 11. --managed-only keeps the preflight for what it does write.
new_kit; new_existing e3
mkdir -p "$t/.agents/docs"; printf 'mine\n' > "$t/$testing_md"
inst --managed-only "$t"
check "managed-only: a differing managed file is a CONFLICT" refused_with '^CONFLICT .agents/docs/testing.md '
check "managed-only: and nothing was written" bash -c "[ ! -e '$t/.friday-lock.json' ] && [ ! -e '$t/.agents/githooks' ] && [ \"\$(cat '$t/$testing_md')\" = mine ]"
check "managed-only: the seeds are still not conflicts" lacks '^CONFLICT AGENTS.md' "$log"
git -C "$kit" show v1.1.0:payload/$testing_md > "$t/$testing_md"
inst --managed-only "$t"
check "managed-only: an identical managed file is no conflict" rc_is 0

new_kit; new_existing e4
git -C "$t" config core.hooksPath .husky/_
inst --managed-only "$t"
check "managed-only: another hook manager is still a CONFLICT" refused_with '^CONFLICT core.hooksPath '
check "managed-only: and nothing was written" untouched_existing "$t"

new_kit; new_existing e5
mkdir -p "$t/.claude/skills/git-push"; printf 'mine\n' > "$t/.claude/skills/git-push/notes.txt"
inst --managed-only "$t"
check "managed-only: a Skill link in the way is still a CONFLICT" refused_with '^CONFLICT .claude/skills/git-push '
check "managed-only: and nothing was written" untouched_existing "$t"

new_kit; new_target e6
inst --managed-only "$t"
check "managed-only on a bare project: lists every seed as missing" bash -c "grep -q '^SEED .claude/settings.json (missing; not created)' '$log' && grep -q '^SEED .gitignore (missing; not created)' '$log'"
check "managed-only on a bare project: fails the self-check, naming the seeds" bash -c "[ $rc -ne 0 ] && grep -q 'self-check FAILED' '$log' && grep -q 'left the seeds' '$log'"
check "managed-only on a bare project: says setup.sh creates the pointers" \
  bash -c "grep -q \"^SEED AGENTS.md (missing; setup.sh creates it\" '$log' && grep -q \"^SEED CLAUDE.md (missing; setup.sh creates it\" '$log'"
check "managed-only on a bare project: and it does" bash -c "[ -f '$t/AGENTS.md' ] && [ -f '$t/CLAUDE.md' ]"
check "managed-only on a bare project: did not create .claude/settings.json" bash -c "[ ! -e '$t/.claude/settings.json' ] && [ ! -e '$t/.codex/hooks.json' ] && [ ! -e '$t/.gitignore' ]"

# A release whose installer does not run setup.sh creates no pointer: the line says so.
new_kit; new_target e8
inst --managed-only --release v1.0.0 "$t"
check "managed-only, old release, bare project: AGENTS.md is not created, and says so" \
  bash -c "grep -q '^SEED AGENTS.md (missing; not created)' '$log' && [ ! -e '$t/AGENTS.md' ]"

# 12. --managed-only with --working-tree.
new_kit; new_existing e7; dirty_kit
before=$(seed_sum "$t")
inst --managed-only --working-tree "$t"
check "managed-only --working-tree: exits 0" rc_is 0
check "managed-only --working-tree: installs the checkout's edit" has UNRELEASED "$t/$testing_md"
check "managed-only --working-tree: the seeds are untouched" [ "$(seed_sum "$t")" = "$before" ]
check "managed-only --working-tree: lists the seeds" has '^SEED AGENTS.md (yours; not touched)' "$log"
check "managed-only --working-tree: warns it is not a release" has 'not a release' "$log"

# 13. Origin unreadable: the reason is printed, nothing is written, the exit is 1 (not git's 128).
new_kit; new_target o1
git -C "$kit" remote set-url origin "$case_dir/nonexistent.git"
inst "$t"
check "origin unreachable: refused with exit 1" rc_is 1
check "origin unreachable: says origin cannot be read" has 'origin' "$log"
check "origin unreachable: nothing was written" untouched "$t"
inst --release v1.1.0 "$t"
check "origin unreachable: --release is refused the same way" bash -c "[ $rc -eq 1 ] && grep -q 'origin' '$log'"
new_kit; new_target o2
git -C "$kit" remote remove origin
inst "$t"
check "no origin: refused with exit 1 and a reason" bash -c "[ $rc -eq 1 ] && grep -q 'origin' '$log'"
check "no origin: nothing was written" untouched "$t"

# 14. --as-release is the exported copy's flag. Misused, it must not label what it installs as a release.
new_kit; new_target a1; dirty_kit
tc=$(git -C "$kit" rev-parse 'v1.1.0^{commit}'); oc=$(git -C "$kit" rev-parse 'v1.0.0^{commit}')
inst --as-release v1.1.0 "$t"
check "--as-release without the variables: refused" refused_with 'FRIDAY_'
check "--as-release without the variables: nothing was written" untouched "$t"
inst_as "$kit" "$tc" v1.0.0 --as-release v1.1.0 "$t"
check "--as-release naming another release than FRIDAY_RELEASE: refused" refused_with 'FRIDAY_RELEASE'
check "--as-release naming another release: nothing was written" untouched "$t"
inst_as "$kit" "$oc" v1.1.0 --as-release v1.1.0 "$t"
check "--as-release whose tag is not FRIDAY_TREE: refused" refused_with 'FRIDAY_TREE'
check "--as-release whose tag is not FRIDAY_TREE: nothing was written" untouched "$t"
inst_as "$kit" "$tc" v1.1.0 --as-release v1.1.0 "$t"
check "--as-release from a dirty checkout, variables set: refused, not labelled v1.1.0" refused_with 'does not match'
check "--as-release from a dirty checkout: nothing was written" untouched "$t"
check "--as-release from a dirty checkout: no lock says a release" bash -c "[ ! -e '$t/.friday-lock.json' ]"

new_kit; new_target a2
tc=$(git -C "$kit" rev-parse 'v1.1.0^{commit}')
printf '\n# local change\n' >> "$kit/bin/managed-core.txt"
inst_as "$kit" "$tc" v1.1.0 --as-release v1.1.0 "$t"
check "--as-release with a different managed-core.txt: refused" refused_with 'does not match'
check "--as-release with a different managed-core.txt: nothing was written" untouched "$t"
new_kit; new_target a3
tc=$(git -C "$kit" rev-parse 'v1.1.0^{commit}')
printf 'extra\n' > "$kit/payload/extra.txt"
inst_as "$kit" "$tc" v1.1.0 --as-release v1.1.0 "$t"
check "--as-release with a payload file the release lacks: refused" refused_with 'does not match'
check "--as-release with a payload file the release lacks: nothing was written" untouched "$t"
new_kit; new_target a4
tc=$(git -C "$kit" rev-parse 'v1.1.0^{commit}')
inst_as "$kit" "$tc" v1.1.0 --as-release v1.1.0 "$t"
check "--as-release over the release's own bytes: installs" rc_is 0
check "--as-release over the release's own bytes: the lock names the release" lock_is .friday.tag v1.1.0

# 15. Two tags on one commit: the lock keeps the one that was asked for.
new_kit; new_target s1
gq -C "$kit" tag -a v1.1.1 -m "release v1.1.1"; git -C "$kit" push -q origin refs/tags/v1.1.1
inst --release v1.1.0 "$t"
check "two tags, one commit: --release of the older records the older" lock_is .friday.tag v1.1.0
new_target s2; inst "$t"
check "two tags, one commit: the default records the newer" lock_is .friday.tag v1.1.1
new_target s3; inst --release v1.1.1 "$t"
check "two tags, one commit: --release of the newer records the newer" lock_is .friday.tag v1.1.1

# 16. A caller's FRIDAY_LOCK_FROM_INDEX must not turn the lock into a record of an empty index.
new_kit; new_target x1
export FRIDAY_LOCK_FROM_INDEX=1
inst "$t"
check "FRIDAY_LOCK_FROM_INDEX set: a release install still writes its lock" bash -c "[ $rc -eq 0 ] && [ -f '$t/.friday-lock.json' ]"
new_target x2; inst --working-tree "$t"
check "FRIDAY_LOCK_FROM_INDEX set: so does --working-tree" bash -c "[ $rc -eq 0 ] && [ -f '$t/.friday-lock.json' ]"
new_target x3; inst --release v1.0.0 "$t"
check "FRIDAY_LOCK_FROM_INDEX set: so does an old release" bash -c "[ $rc -eq 0 ] && [ -f '$t/.friday-lock.json' ]"
unset FRIDAY_LOCK_FROM_INDEX

# 17. A shallow clone, or one with no main, is told what to do about it.
new_kit; new_target h1
git clone -q --depth 1 "file://$kit.git" "$case_dir/shallow"
git -C "$case_dir/shallow" fetch -q --tags
kit_dir="$case_dir/shallow" inst --release v1.0.0 "$t"
check "shallow clone: refused, told to unshallow" refused_with 'unshallow'
check "shallow clone: nothing was written" untouched "$t"
new_target h2
git clone -q "file://$kit.git" "$case_dir/nomain"
git -C "$case_dir/nomain" switch -q --detach
git -C "$case_dir/nomain" update-ref -d refs/heads/main
kit_dir="$case_dir/nomain" inst "$t"
check "no local main: refused, told to create it" refused_with 'no local main'
check "no local main: nothing was written" untouched "$t"
kit_dir=

echo ""
if [ "$fails" -eq 0 ]; then
  echo "all $total passed"
else
  echo "$fails of $total FAILED"
  exit 1
fi
