#!/usr/bin/env bash
# Cases for payload/.agents/bin/setup.sh.
#
# Each case clones a scratch consumer, runs the script in it, and asserts what
# it printed, what it exited with and what is on disk afterwards. A "left
# alone" assertion is always paired with one that the script said something,
# so a script that does nothing cannot pass a case by doing nothing. Run it
# against another script with SETUP_UNDER_TEST=<path>; an empty script must
# fail every case. Sandboxes are left in place under the printed directory.
set -uo pipefail
[ "$#" -le 1 ] || { echo "usage: $0 [retained-output-directory]" >&2; exit 2; }

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
setup_script=${SETUP_UNDER_TEST:-$source_root/payload/.agents/bin/setup.sh}
base=${1:-${TMPDIR:-/tmp}}
mkdir -p "$base"
root=$(cd "$(mktemp -d "$base/setup-test.XXXXXX")" && pwd -P)
echo "sandboxes: $root"
# Let "outside a work tree" be outside one even when $base is inside a repository.
export GIT_CEILING_DIRECTORIES="$root"
# A global core.hooksPath on the machine running this would count as set; a
# global config of our own, empty unless a case fills it, keeps the cases alone.
export GIT_CONFIG_GLOBAL="$root/global.gitconfig"
: > "$GIT_CONFIG_GLOBAL"

fails=0
total=0
n=0
gq() { git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }

# The payload as a repository: what a clone of a consumer that was never wired
# would hold. Every case clones it.
pristine="$root/pristine"
git init -q "$pristine"
cp -R "$source_root/payload/." "$pristine/"
gq -C "$pristine" add -A && gq -C "$pristine" commit -q -m "payload"

new_consumer() {
  n=$((n + 1))
  mkdir -p "$root/$n"
  consumer="$root/$n/consumer"
  git clone -q "$pristine" "$consumer"
}
# run [--dir <dir>] [args...] -> $out, $rc
run() {
  local dir=$consumer
  if [ "${1:-}" = --dir ]; then dir=$2; shift 2; fi
  out=$(cd "$dir" && bash "$setup_script" "$@" 2>&1)
  rc=$?
}
# Everything a run could change, so "writes nothing" is a comparison.
snap() {
  (cd "$1" && {
    find . -path ./.git -prune -o -print | sort
    find . -path ./.git -prune -o -type f -exec cksum {} + | sort
    find . -path ./.git -prune -o -type l -exec readlink {} \;
    git config --local --list
  })
}
mkskill() { # <dir under .agents/skills> [name]
  mkdir -p "$consumer/.agents/skills/$1"
  { printf -- '---\n'; [ -z "${2:-}" ] || printf 'name: %s\n' "$2"; printf 'description: test\n---\n\nbody\n'; } \
    > "$consumer/.agents/skills/$1/SKILL.md"
}
mkskillraw() { # <dir under .agents/skills> <the whole name: line>
  mkdir -p "$consumer/.agents/skills/$1"
  printf -- '---\n%s\ndescription: test\n---\n\nbody\n' "$2" > "$consumer/.agents/skills/$1/SKILL.md"
}
links() { (cd "$consumer/.claude/skills" 2>/dev/null && for f in *; do [ -L "$f" ] && printf '%s -> %s\n' "$f" "$(readlink "$f")"; done); }

cur=; cfails=0; notes=
begin() { cur=$1; cfails=0; notes=; total=$((total + 1)); }
a() { # description, then a shell expression that must be true
  if ! eval "$2"; then cfails=$((cfails + 1)); notes="$notes\n       - $1"; fi
}
end() {
  if [ "$cfails" -eq 0 ]; then echo "ok   $cur"; return; fi
  echo "FAIL $cur"
  printf '%b\n' "$notes"
  printf '%s\n' "$out" | sed 's/^/       | /' | head -14
  fails=$((fails + 1))
}
says() { printf '%s\n' "$out" | grep -qF -- "$1"; }
lacks() { ! says "$1"; }
hp() { git -C "$consumer" config --local --get core.hooksPath; }

# ---------------------------------------------------------------------------
begin "a fresh clone has no core.hooksPath, and setup sets it and wires the rest"
new_consumer
a "precondition: the clone has none" '[ -z "$(hp)" ]'
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "core.hooksPath is .agents/githooks" '[ "$(hp)" = .agents/githooks ]'
a "says it created it" 'says "CREATED  core.hooksPath -> .agents/githooks"'
a "claude guard link" '[ "$(readlink "$consumer/.claude/hooks/guard-collaborative-git.sh")" = ../../.agents/hooks/guard-collaborative-git.sh ]'
a "codex guard link" '[ "$(readlink "$consumer/.codex/hooks/guard-collaborative-git.sh")" = ../../.agents/hooks/guard-collaborative-git.sh ]'
a "git-commit skill link" '[ "$(readlink "$consumer/.claude/skills/git-commit")" = ../../.agents/skills/git/commit ]'
a "git-create-pr skill link" '[ "$(readlink "$consumer/.claude/skills/git-create-pr")" = ../../.agents/skills/git/create-pr ]'
a "git-push skill link" '[ "$(readlink "$consumer/.claude/skills/git-push")" = ../../.agents/skills/git/push ]'
a "a link resolves" '[ -f "$consumer/.claude/skills/git-push/SKILL.md" ]'
end

begin "a second run changes nothing and says so"
new_consumer
run; first=$out
before=$(snap "$consumer")
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "says nothing to change" 'says "nothing to change"'
a "creates nothing" 'lacks "CREATED"'
a "the tree and config are identical" '[ "$(snap "$consumer")" = "$before" ]'
a "the first run did change something" 'printf "%s\n" "$first" | grep -q "^CREATED"'
end

begin "--check writes nothing and exits 1 when something would change"
new_consumer
before=$(snap "$consumer")
run --check
a "exits 1" '[ "$rc" -eq 1 ]'
a "names what it would do" 'says "WOULD CREATE core.hooksPath -> .agents/githooks"'
a "names a skill link it would make" 'says "WOULD CREATE .claude/skills/git-commit"'
a "writes nothing" '[ "$(snap "$consumer")" = "$before" ]'
a "core.hooksPath is still unset" '[ -z "$(hp)" ]'
end

begin "--check exits 0 when nothing would change"
new_consumer
run
run --check
a "exits 0" '[ "$rc" -eq 0 ]'
a "says nothing to change" 'says "nothing to change"'
end

begin "--check exits 1 on a conflict even when nothing would be created"
new_consumer
run
git -C "$consumer" config --local core.hooksPath .husky/_
run --check
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports the conflict" 'says "CONFLICT core.hooksPath "'
end

begin "an unknown argument is a usage error"
new_consumer
run --nope
a "exits 2" '[ "$rc" -eq 2 ]'
a "prints usage" 'says "usage:"'
end

begin "core.hooksPath set elsewhere is a CONFLICT and is left alone"
new_consumer
git -C "$consumer" config --local core.hooksPath .husky/_
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports it" 'says "CONFLICT core.hooksPath (set to '"'"'.husky/_'"'"'"'
a "left it" '[ "$(hp)" = .husky/_ ]'
a "the rest still ran" '[ -L "$consumer/.claude/skills/git-push" ] && [ -L "$consumer/.codex/hooks/guard-collaborative-git.sh" ]'
a "does not also report .git/hooks" 'lacks "CONFLICT .git/hooks"'
end

begin "active hooks in .git/hooks are reported; samples are not"
new_consumer
printf '#!/bin/sh\nexit 0\n' > "$consumer/.git/hooks/pre-commit.sample"
run
a "a sample alone is not a conflict" '[ "$rc" -eq 0 ] && lacks "CONFLICT .git/hooks" && says "CREATED  core.hooksPath"'
printf '#!/bin/sh\nexit 0\n' > "$consumer/.git/hooks/pre-commit"; chmod +x "$consumer/.git/hooks/pre-commit"
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports it" 'says "CONFLICT .git/hooks ("'
a "left the hook" '[ -f "$consumer/.git/hooks/pre-commit" ]'
end

begin "a Git hook that is not executable is reported and not changed"
new_consumer
chmod -x "$consumer/.agents/githooks/pre-push"
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "names the hook" 'says "CONFLICT .agents/githooks/pre-push (not executable"'
a "did not chmod it" '[ ! -x "$consumer/.agents/githooks/pre-push" ]'
end

begin "a missing Git hook is reported"
new_consumer
rm "$consumer/.agents/githooks/commit-msg"
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "names the hook" 'says "CONFLICT .agents/githooks/commit-msg (missing)"'
end

begin "a missing runtime link is created"
new_consumer
run
rm "$consumer/.claude/hooks/guard-collaborative-git.sh"
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "says so" 'says "CREATED  .claude/hooks/guard-collaborative-git.sh"'
a "the link is back" '[ "$(readlink "$consumer/.claude/hooks/guard-collaborative-git.sh")" = ../../.agents/hooks/guard-collaborative-git.sh ]'
end

begin "a correct runtime link is OK"
new_consumer
run
run
a "reports both OK" 'says "OK       .claude/hooks/guard-collaborative-git.sh" && says "OK       .codex/hooks/guard-collaborative-git.sh"'
end

begin "a runtime link to somewhere else is a CONFLICT and is left alone"
new_consumer
mkdir -p "$consumer/.claude/hooks"
ln -s "$root" "$consumer/.claude/hooks/guard-collaborative-git.sh"
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports it" 'says "CONFLICT .claude/hooks/guard-collaborative-git.sh (points to $root,"'
a "left it" '[ "$(readlink "$consumer/.claude/hooks/guard-collaborative-git.sh")" = "$root" ]'
end

begin "a dangling runtime link is a CONFLICT and is left alone"
new_consumer
mkdir -p "$consumer/.codex/hooks"
ln -s ../../.agents/hooks/absent.sh "$consumer/.codex/hooks/guard-collaborative-git.sh"
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports it" 'says "CONFLICT .codex/hooks/guard-collaborative-git.sh ("'
a "left it" '[ "$(readlink "$consumer/.codex/hooks/guard-collaborative-git.sh")" = ../../.agents/hooks/absent.sh ]'
end

begin "a regular file where a runtime link belongs is a CONFLICT and is left alone"
new_consumer
mkdir -p "$consumer/.claude/hooks"
printf 'mine\n' > "$consumer/.claude/hooks/guard-collaborative-git.sh"
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports it" 'says "CONFLICT .claude/hooks/guard-collaborative-git.sh (exists and is not a symlink)"'
a "left it" '[ "$(cat "$consumer/.claude/hooks/guard-collaborative-git.sh")" = mine ]'
end

begin "AGENTS.md and CLAUDE.md are created when missing, byte for byte as the payload seeds"
new_consumer
rm "$consumer/AGENTS.md" "$consumer/CLAUDE.md"
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "says so" 'says "CREATED  AGENTS.md" && says "CREATED  CLAUDE.md"'
a "AGENTS.md equals payload/AGENTS.md" 'cmp -s "$source_root/payload/AGENTS.md" "$consumer/AGENTS.md"'
a "CLAUDE.md equals payload/CLAUDE.md" 'cmp -s "$source_root/payload/CLAUDE.md" "$consumer/CLAUDE.md"'
end

begin "AGENTS.md and CLAUDE.md are left untouched when present with other content"
new_consumer
printf 'my agents\n' > "$consumer/AGENTS.md"
printf 'my claude\n' > "$consumer/CLAUDE.md"
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "reports both OK" 'says "OK       AGENTS.md" && says "OK       CLAUDE.md"'
a "AGENTS.md untouched" '[ "$(cat "$consumer/AGENTS.md")" = "my agents" ]'
a "CLAUDE.md untouched" '[ "$(cat "$consumer/CLAUDE.md")" = "my claude" ]'
end

begin "a grouped Skill is linked under its own name: frontmatter"
new_consumer
mkskill grp/inner custom-name
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "linked as custom-name" '[ "$(readlink "$consumer/.claude/skills/custom-name")" = ../../.agents/skills/grp/inner ]'
a "not linked under the directory name" '[ ! -e "$consumer/.claude/skills/inner" ]'
end

begin "a top-level Skill is linked, by directory name when it declares none"
new_consumer
mkskill mytool
printf 'name: bogus\n' >> "$consumer/.agents/skills/mytool/SKILL.md"
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "linked as mytool" '[ "$(readlink "$consumer/.claude/skills/mytool")" = ../../.agents/skills/mytool ]'
a "a name: line in the body is not the Skill name" '[ ! -e "$consumer/.claude/skills/bogus" ]'
end

begin "a grouping directory without its own SKILL.md is never linked"
new_consumer
run
a "the Skills inside were linked" '[ -L "$consumer/.claude/skills/git-commit" ]'
a "git/ itself was not" '[ ! -e "$consumer/.claude/skills/git" ]'
a "and is not reported as stale" 'lacks "STALE"'
end

begin "a dangling .claude/skills link is replaced"
new_consumer
mkdir -p "$consumer/.claude/skills"
ln -s ../../.agents/skills/old/push "$consumer/.claude/skills/git-push"
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "says it replaced it" 'says "CREATED  .claude/skills/git-push -> ../../.agents/skills/git/push (replacing a dangling link"'
a "now correct" '[ "$(readlink "$consumer/.claude/skills/git-push")" = ../../.agents/skills/git/push ]'
end

begin "a real directory in the way is a CONFLICT and is left alone"
new_consumer
mkdir -p "$consumer/.claude/skills/git-push"
printf 'mine\n' > "$consumer/.claude/skills/git-push/notes.txt"
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports it" 'says "CONFLICT .claude/skills/git-push (exists and is not a symlink)"'
a "left the directory and its file" '[ "$(cat "$consumer/.claude/skills/git-push/notes.txt")" = mine ] && [ ! -L "$consumer/.claude/skills/git-push" ]'
a "the other Skills were still linked" '[ -L "$consumer/.claude/skills/git-commit" ]'
end

begin "a live link elsewhere is a CONFLICT and is left alone"
new_consumer
mkdir -p "$consumer/.claude/skills"
ln -s ../../.agents/skills/git/commit "$consumer/.claude/skills/git-push"
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports it" 'says "CONFLICT .claude/skills/git-push (points to ../../.agents/skills/git/commit, expected ../../.agents/skills/git/push)"'
a "left it" '[ "$(readlink "$consumer/.claude/skills/git-push")" = ../../.agents/skills/git/commit ]'
end

begin "a stale entry is reported as STALE and not removed, and does not fail the run"
new_consumer
mkdir -p "$consumer/.claude/skills"
ln -s ../../.agents/skills/gone "$consumer/.claude/skills/removed-skill"
ln -s ../../.agents/docs "$consumer/.claude/skills/orphan"
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "reports the dangling one" 'says "STALE    .claude/skills/removed-skill (dangling link to ../../.agents/skills/gone)"'
a "reports the one matching no Skill" 'says "STALE    .claude/skills/orphan ("'
a "counts them" 'says "stale 2"'
a "removed neither" '[ -L "$consumer/.claude/skills/removed-skill" ] && [ -L "$consumer/.claude/skills/orphan" ]'
end

begin "dot entries in .claude/skills are not Skills: neither reported nor touched"
new_consumer
mkdir -p "$consumer/.claude/skills"
printf 'junk\n' > "$consumer/.claude/skills/.DS_Store"
ln -s ../../.agents/skills/gone "$consumer/.claude/skills/.hidden-dangling"
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "the Skills were linked" 'says "CREATED  .claude/skills/git-commit"'
a "reports no STALE" 'lacks "STALE" && says "stale 0"'
a "left the file" '[ "$(cat "$consumer/.claude/skills/.DS_Store")" = junk ]'
a "left the dangling dot link" '[ "$(readlink "$consumer/.claude/skills/.hidden-dangling")" = ../../.agents/skills/gone ]'
end

begin "two Skills declaring the same name are a CONFLICT and neither is linked"
new_consumer
mkskill one/a twin
mkskill two/b twin
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports it, naming both" 'says "CONFLICT .claude/skills/twin (declared by more than one Skill: .agents/skills/one/a, .agents/skills/two/b"'
a "linked neither" '[ ! -e "$consumer/.claude/skills/twin" ] && [ ! -L "$consumer/.claude/skills/twin" ]'
a "the other Skills were still linked" '[ -L "$consumer/.claude/skills/git-commit" ]'
end

begin "a symlinked .claude/skills is not written through"
new_consumer
mkdir -p "$root/$n/elsewhere" "$consumer/.claude"
ln -s "$root/$n/elsewhere" "$consumer/.claude/skills"
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports it" 'says "CONFLICT .claude/skills/git-commit (unsafe parent: .claude/skills)"'
a "wrote nothing through it" '[ -z "$(ls -A "$root/$n/elsewhere")" ]'
end

begin "it works from a subdirectory, and acts on the repository root"
new_consumer
run --dir "$consumer/.agents/docs"
a "exits 0" '[ "$rc" -eq 0 ]'
a "wired the root" '[ "$(hp)" = .agents/githooks ] && [ -L "$consumer/.claude/skills/git-commit" ]'
a "wrote nothing in the subdirectory" '[ ! -e "$consumer/.agents/docs/.claude" ] && [ ! -e "$consumer/.agents/docs/CLAUDE.md" ]'
end

begin "outside a Git work tree it refuses"
new_consumer
mkdir -p "$root/$n/outside"
run --dir "$root/$n/outside"
a "exits 1" '[ "$rc" -eq 1 ]'
a "says why" 'says "not inside a Git work tree"'
a "wrote nothing" '[ -z "$(ls -A "$root/$n/outside")" ]'
end

begin "inside .git, which is not a work tree, it refuses"
new_consumer
run --dir "$consumer/.git"
a "exits 1" '[ "$rc" -eq 1 ]'
a "says why" 'says "not inside a Git work tree"'
end

begin "in a linked worktree it refuses"
new_consumer
git -C "$consumer" worktree add -q "$root/$n/linked" -b wt
run --dir "$root/$n/linked"
a "exits 1" '[ "$rc" -eq 1 ]'
a "says why" 'says "is a linked worktree"'
a "wrote nothing in it" '[ ! -e "$root/$n/linked/.claude/skills" ] && [ ! -e "$root/$n/linked/.claude/hooks" ]'
a "did not set core.hooksPath" '[ -z "$(hp)" ]'
end

begin "a dangling link that setup did not write is a CONFLICT, not replaced"
new_consumer
mkdir -p "$consumer/.claude/skills"
ln -s ../../elsewhere/push "$consumer/.claude/skills/git-push"
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports it" 'says "CONFLICT .claude/skills/git-push (a dangling link to ../../elsewhere/push, which is not one setup wrote"'
a "left it" '[ "$(readlink "$consumer/.claude/skills/git-push")" = ../../elsewhere/push ]'
a "the other Skills were still linked" '[ -L "$consumer/.claude/skills/git-commit" ]'
end

begin "a Skill name that cannot be a link name is a CONFLICT and nothing is made"
new_consumer
mkskillraw bad1 'name: a/b'
mkskillraw bad2 'name: ..'
mkskillraw bad3 'name: .'
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports a/b" 'says "CONFLICT .agents/skills/bad1 (its name '"'"'a/b'"'"' is not usable as a link name)"'
a "reports .." 'says "CONFLICT .agents/skills/bad2 (its name '"'"'..'"'"' is not usable as a link name)"'
a "reports ." 'says "CONFLICT .agents/skills/bad3 (its name '"'"'.'"'"' is not usable as a link name)"'
a "made nothing for them" '[ ! -e "$consumer/.claude/skills/a" ] && [ ! -L "$consumer/.claude/skills/bad1" ]'
end

begin "a quoted name: is linked without its quotes"
new_consumer
mkskillraw dq 'name: "double"'
mkskillraw sq "name: 'single'"
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "double quotes stripped" '[ "$(readlink "$consumer/.claude/skills/double")" = ../../.agents/skills/dq ]'
a "single quotes stripped" '[ "$(readlink "$consumer/.claude/skills/single")" = ../../.agents/skills/sq ]'
end

begin "an inline YAML comment is not part of the name; a # inside quotes is"
new_consumer
mkskillraw c1 'name: plain # a comment'
mkskillraw c2 'name: "has # inside"'
mkskillraw c3 "name: 'quoted' # then a comment"
mkskillraw c4 'name: no#space'
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "comment stripped" '[ "$(readlink "$consumer/.claude/skills/plain")" = ../../.agents/skills/c1 ]'
a "# inside quotes kept" '[ "$(readlink "$consumer/.claude/skills/has # inside")" = ../../.agents/skills/c2 ]'
a "quoted then comment" '[ "$(readlink "$consumer/.claude/skills/quoted")" = ../../.agents/skills/c3 ]'
a "# without a space before it is part of the name" '[ "$(readlink "$consumer/.claude/skills/no#space")" = ../../.agents/skills/c4 ]'
end

begin "two Skills whose name holds a backslash are still seen as duplicates"
new_consumer
mkskillraw bs1 'name: x\ny'
mkskillraw bs2 'name: x\ny'
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports it, naming both" 'says "CONFLICT .claude/skills/x\ny (declared by more than one Skill: .agents/skills/bs1, .agents/skills/bs2"'
a "linked neither" '[ ! -L "$consumer/.claude/skills/x\ny" ] && [ ! -L "$consumer/.claude/skills/x
y" ]'
end

begin "a runtime link is not made to a guard that is missing"
new_consumer
rm "$consumer/.agents/hooks/guard-collaborative-git.sh"
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports the claude link" 'says "CONFLICT .claude/hooks/guard-collaborative-git.sh (cannot link to .agents/hooks/guard-collaborative-git.sh, which is missing)"'
a "reports the codex link" 'says "CONFLICT .codex/hooks/guard-collaborative-git.sh (cannot link to"'
a "made neither" '[ ! -L "$consumer/.claude/hooks/guard-collaborative-git.sh" ] && [ ! -L "$consumer/.codex/hooks/guard-collaborative-git.sh" ]'
end

begin "it works in a submodule, whose .git is a file but which is not a linked worktree"
n=$((n + 1)); mkdir -p "$root/$n"
git init -q "$root/$n/super"
gq -C "$root/$n/super" -c protocol.file.allow=always submodule add -q "$pristine" sub >/dev/null 2>&1
consumer="$root/$n/super/sub"
a "precondition: .git is a file" '[ -f "$consumer/.git" ]'
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "wired the submodule" '[ "$(hp)" = .agents/githooks ] && [ -L "$consumer/.claude/skills/git-commit" ]'
end

begin "it works in a repository whose path, and a Skill whose directory, contain spaces"
n=$((n + 1)); mkdir -p "$root/$n/with space"
consumer="$root/$n/with space/the consumer"
git clone -q "$pristine" "$consumer"
mkskillraw "spaced dir" 'name: spaced name'
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "wired it" '[ "$(hp)" = .agents/githooks ] && [ -L "$consumer/.claude/hooks/guard-collaborative-git.sh" ]'
a "linked the Skill with spaces" '[ "$(readlink "$consumer/.claude/skills/spaced name")" = "../../.agents/skills/spaced dir" ]'
a "linked the others" '[ -L "$consumer/.claude/skills/git-push" ]'
run
a "and a second run has nothing to change" 'says "nothing to change"'
end

begin "a Skill directory that is a symlink outside .agents/skills is reported SKIPPED, not followed"
new_consumer
mkdir -p "$consumer/outside-skill"
printf -- '---\nname: outside\n---\n' > "$consumer/outside-skill/SKILL.md"
ln -s ../../outside-skill "$consumer/.agents/skills/ext"
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "says it was skipped" 'says "SKIPPED  .agents/skills/ext (a symlink outside .agents/skills; not followed)"'
a "did not link it" '[ ! -e "$consumer/.claude/skills/outside" ] && [ ! -e "$consumer/.claude/skills/ext" ]'
a "the others were linked" '[ -L "$consumer/.claude/skills/git-commit" ]'
end

begin "a Skill directory that is a symlink inside .agents/skills is an alias, and silent"
new_consumer
ln -s git/commit "$consumer/.agents/skills/git-commit"
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "the real Skill is linked" 'says "CREATED  .claude/skills/git-commit"'
a "says nothing about the alias" 'lacks "SKIPPED" && lacks "STALE"'
end

begin "a core.hooksPath at another scope that is not ours is a CONFLICT and is not overridden"
new_consumer
git config --file "$GIT_CONFIG_GLOBAL" core.hooksPath .husky/_
run
git config --file "$GIT_CONFIG_GLOBAL" --unset core.hooksPath
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports it" 'says "CONFLICT core.hooksPath (set to '"'"'.husky/_'"'"'"'
a "set nothing locally" '[ -z "$(hp)" ]'
a "the rest still ran" '[ -L "$consumer/.claude/skills/git-push" ]'
end

begin "a core.hooksPath at another scope that is ours is accepted"
new_consumer
git config --file "$GIT_CONFIG_GLOBAL" core.hooksPath .agents/githooks
run
git config --file "$GIT_CONFIG_GLOBAL" --unset core.hooksPath
a "exits 0" '[ "$rc" -eq 0 ]'
a "says OK" 'says "OK       core.hooksPath -> .agents/githooks"'
a "set nothing locally" '[ -z "$(hp)" ]'
end

begin "a symlink in .git/hooks counts as an active hook"
new_consumer
ln -s "$root" "$consumer/.git/hooks/pre-commit"
run
a "exits 1" '[ "$rc" -eq 1 ]'
a "reports it" 'says "CONFLICT .git/hooks ("'
end

begin "a fresh clone of an installed consumer gets the one thing it lacks"
n=$((n + 1)); mkdir -p "$root/$n"
git init -q "$root/$n/origin"
bash "$source_root/install.sh" "$root/$n/origin" > "$root/$n/install.log" 2>&1
# Install wired core.hooksPath in the origin, as it would on the installing
# machine; drop it to commit, so the payload's own message rules do not judge
# this fixture. A clone never receives it either way.
git -C "$root/$n/origin" config --local --unset core.hooksPath
gq -C "$root/$n/origin" add -A && gq -C "$root/$n/origin" commit -q -m "install the payload"
consumer="$root/$n/clone"
git clone -q "$root/$n/origin" "$consumer"
a "precondition: the clone has the links but no core.hooksPath" '[ -z "$(hp)" ] && [ -L "$consumer/.claude/skills/git-commit" ]'
run
a "exits 0" '[ "$rc" -eq 0 ]'
a "sets core.hooksPath" '[ "$(hp)" = .agents/githooks ] && says "CREATED  core.hooksPath"'
a "created only that" 'says "created 1,"'
end

echo
if [ "$fails" -gt 0 ]; then echo "$fails of $total failed"; exit 1; fi
echo "all $total passed"
