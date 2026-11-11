#!/usr/bin/env bash
# Live-payload installer regression check; preserve outputs for inspection.
# It installs this checkout's payload as it stands, so every install here is
# --working-tree; the release install is proven by tests/install-release.sh.
set -euo pipefail
[ "$#" -eq 1 ] || { echo "usage: $0 retained-output-directory" >&2; exit 2; }
source_root=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)
mkdir -p "$1"
# Absolute: GIT_CONFIG_GLOBAL below is read by git -C <target>, which resolves
# a relative path against the target, not against this directory.
out=$(CDPATH= cd "$1" && pwd)
run=$(mktemp -d "$out/run.XXXXXX")
kit="$source_root"
# A core.hooksPath in the global config of the machine running this would count
# as set; a global config of our own, empty unless a case fills it, keeps the
# targets alone.
export GIT_CONFIG_GLOBAL="$run/global.gitconfig"
: > "$GIT_CONFIG_GLOBAL"
expected='
AGENTS.md
CLAUDE.md
.agents/AGENTS.md
.agents/protected-paths.conf
.agents/bin/setup.sh
.agents/docs/agent-rules.md
.agents/docs/testing.md
.agents/docs/scratch-files.md
.agents/docs/git-guideline/git-commit.md
.agents/docs/git-guideline/pr-evidence.md
.agents/docs/git-guideline/safety-boundary.md
.agents/hooks/check-collaborative-git.sh
.agents/hooks/guard-collaborative-git.sh
.agents/hooks/guard-protected-paths.sh
.agents/githooks/pre-commit
.agents/githooks/commit-msg
.agents/githooks/pre-push
.agents/skills/git/commit/SKILL.md
.agents/skills/git/create-pr/SKILL.md
.agents/skills/git/github-pr-verify/SKILL.md
.agents/skills/git/push/SKILL.md
.gitignore
.claude/settings.json
.codex/hooks.json'
links='.claude/hooks/guard-collaborative-git.sh .claude/hooks/guard-protected-paths.sh .codex/hooks/guard-collaborative-git.sh'

# Compare `expected` with what the installer actually listed or wrote, and say
# which way it differs. Under set -e a bare comparison or a grep -q loop exits
# 1 with no message at all, which is what both a new payload file missing
# from this list and a removed one still in it used to look like.
inventory_check() {
  local label=$1 want have extra missing
  want=$(printf '%s\n' $expected $links | sort)
  have=$(printf '%s\n' "$2" | sort)
  [ "$want" = "$have" ] && return 0
  extra=$(comm -13 <(printf '%s\n' "$want") <(printf '%s\n' "$have"))
  missing=$(comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$have"))
  echo "FAIL: $label differs from 'expected' at the top of $0" >&2
  if [ -n "$extra" ]; then
    echo "  present but not listed -- a new payload file? add it to 'expected':" >&2
    printf '    %s\n' $extra >&2
  fi
  if [ -n "$missing" ]; then
    echo "  listed but not present -- a removed payload file? remove it from 'expected':" >&2
    printf '    %s\n' $missing >&2
  fi
  echo "  bin/managed-core.txt and this list must change the same way." >&2
  exit 1
}
target() { git init -q "$run/$1"; }
reject() {
  if bash "$kit/install.sh" --working-tree "$@" > "$run/rejection.log" 2>&1; then
    echo "FAIL: unexpectedly accepted $*" >&2; exit 1
  fi
}

target fresh
bash "$kit/install.sh" --working-tree --check "$run/fresh" > "$run/preview.log"
# The Skill links setup.sh will make are previewed too, but are not payload files.
# The preview lists the runtime links install.sh knows of, the protected-paths
# link included (install.sh previews and preflights it; setup.sh makes it).
inventory_check "the install preview" "$(sed -n 's/^NEW //p' "$run/preview.log" | grep -v '^\.claude/skills/')"
for name in git-commit git-create-pr git-push; do grep -q "^NEW \.claude/skills/$name\$" "$run/preview.log"; done
[ ! -e "$run/fresh/AGENTS.md" ] && [ ! -e "$run/fresh/.agents" ]
bash "$kit/install.sh" --working-tree "$run/fresh" > "$run/install.log"
for rel in $expected; do cmp "$kit/payload/$rel" "$run/fresh/$rel"; done
# The installed policy must still carry the three load-bearing parts of the
# boundary: that ordinary commits are the agent's own call, that integrating a
# change is a person's, and that deleting a ref is never the agent's.
boundary="$run/fresh/.agents/docs/git-guideline/safety-boundary.md"
grep -Fq '**Committing is at the agent'"'"'s discretion.**' "$boundary"
grep -Fq 'One commit carries one task'"'"'s context.' "$boundary"
grep -Fq 'Check for sensitive information before committing and pushing' "$boundary"
grep -Fq '| Merging a pull request |' "$boundary"
grep -Fq '| Pushing directly to the default branch |' "$boundary"
grep -Fq 'must not approve a pull request containing its own work' "$boundary"
grep -Fq '| Deleting refs |' "$boundary"
[ "$(readlink "$run/fresh/.claude/hooks/guard-collaborative-git.sh")" = ../../.agents/hooks/guard-collaborative-git.sh ]
[ "$(readlink "$run/fresh/.claude/hooks/guard-protected-paths.sh")" = ../../.agents/hooks/guard-protected-paths.sh ]
[ -L "$run/fresh/.codex/hooks/guard-collaborative-git.sh" ]
[ "$(readlink "$run/fresh/.codex/hooks/guard-collaborative-git.sh")" = ../../.agents/hooks/guard-collaborative-git.sh ]
run_installed_guard() {
  local payload=$1 output exit_code

  set +e
  output=$(printf '%s' "$payload" | "$run/fresh/.agents/hooks/guard-collaborative-git.sh" 2>&1)
  exit_code=$?
  set -e

  installed_guard_output=$output
  installed_guard_exit=$exit_code
}
require_installed_guard_allowed() {
  run_installed_guard "$1"
  [ "$installed_guard_exit" -eq 0 ] \
    || { echo "FAIL: installed guard blocked allowed payload: $installed_guard_output" >&2; exit 1; }
}
require_installed_guard_blocked() {
  run_installed_guard "$1"
  [ "$installed_guard_exit" -eq 2 ] \
    || { echo "FAIL: installed guard returned $installed_guard_exit, expected 2: $installed_guard_output" >&2; exit 1; }
}
require_installed_guard_allowed '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
require_installed_guard_allowed '{"tool_name":"Bash","tool_input":{"command":"gh api --method=GET /repos/o/r"}}'
require_installed_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease=origin/main"}}'
require_installed_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"git push --force=origin/main"}}'
require_installed_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"gh api --method=DELETE /repos/o/r"}}'
require_installed_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"gh api -X=DELETE /repos/o/r"}}'
require_installed_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"gh api -XDELETE /repos/o/r"}}'
jq -e '
  type == "object" and
  (keys | sort == ["hooks"]) and
  (.hooks | type == "object" and (keys | sort == ["PreToolUse"])) and
  (.hooks.PreToolUse | type == "array" and length == 1) and
  (.hooks.PreToolUse[0] |
    type == "object" and
    (keys | sort == ["hooks", "matcher"]) and
    .matcher == "^(Bash|apply_patch)$" and
    (.hooks | type == "array" and length == 1) and
    (.hooks[0] |
      type == "object" and
      (keys | sort == ["command", "statusMessage", "timeout", "type"]) and
      .type == "command" and
      (.command | startswith("PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")) and
      (.command | contains("command -v \"$required\"")) and
      (.command | contains("repo_root=\"$(git rev-parse --show-toplevel 2>/dev/null)\"")) and
      (.command | contains("guard_path=\"$repo_root/.codex/hooks/guard-collaborative-git.sh\"")) and
      (.command | contains("[ ! -f \"$guard_path\" ] || [ ! -r \"$guard_path\" ]")) and
      (.command | contains("exec bash \"$guard_path\"")) and
      .timeout == 30 and
      .statusMessage == "Checking collaborative Git safety boundary"
    )
  )
' "$run/fresh/.codex/hooks.json" >/dev/null
! grep -Fq 'guard-protected-paths' "$kit/payload/.codex/hooks.json"
# The installed protected-paths guard: the seed conf has no active entries, so
# CLAUDE.md is protected only once the consumer adds it.
run_protected() {
  printf '%s' "$1" | "$run/fresh/.agents/hooks/guard-protected-paths.sh" >/dev/null 2>&1
}
cp "$run/fresh/.agents/protected-paths.conf" "$run/protected-paths.conf.before"
printf '%s\n' CLAUDE.md >> "$run/fresh/.agents/protected-paths.conf"
set +e
run_protected '{"tool_name":"Write","cwd":"'"$run/fresh"'","tool_input":{"file_path":"'"$run/fresh"'/CLAUDE.md","content":"x"}}'
protected_exit=$?
run_protected '{"tool_name":"Write","cwd":"'"$run/fresh"'","tool_input":{"file_path":"'"$run/fresh"'/notes.md","content":"x"}}'
unprotected_exit=$?
set -e
cp "$run/protected-paths.conf.before" "$run/fresh/.agents/protected-paths.conf"
[ "$protected_exit" -eq 2 ] || { echo "FAIL: installed protected-paths guard returned $protected_exit for CLAUDE.md, expected 2" >&2; exit 1; }
[ "$unprotected_exit" -eq 0 ] || { echo "FAIL: installed protected-paths guard returned $unprotected_exit for notes.md, expected 0" >&2; exit 1; }
# Regression: a session started in one project whose cwd moved into an
# UNRELATED repository that does not ship the guard. The launcher must fall back
# to CLAUDE_PROJECT_DIR instead of refusing with "required guard unavailable".
other="$run/other-repo"
git init -q "$other"
protected_launcher=$(jq -r '
  .hooks.PreToolUse[] | select(.matcher == "Write|Edit|MultiEdit|NotebookEdit")
  | .hooks[] | select(.statusMessage == "Checking protected paths") | .command
' "$run/fresh/.claude/settings.json")
[ -n "$protected_launcher" ] || { echo "FAIL: protected-paths launcher not found in the fresh settings" >&2; exit 1; }
# run_launcher <cwd> <session project> <file>: sets launcher_output, launcher_exit.
run_launcher() {
  set +e
  launcher_output=$(cd "$1" && printf '%s' '{"tool_name":"Write","cwd":"'"$1"'","tool_input":{"file_path":"'"$3"'","content":"x"}}' \
    | env CLAUDE_PROJECT_DIR="$2" /bin/sh -c "$protected_launcher" 2>&1)
  launcher_exit=$?
  set -e
}
run_launcher "$other" "$run/fresh" "$other/note.md"
case "$launcher_output" in
  *'required guard unavailable'*) echo "FAIL: launcher in another repository could not find the guard: $launcher_output" >&2; exit 1 ;;
esac
[ "$launcher_exit" -eq 0 ] || { echo "FAIL: launcher in another repository returned $launcher_exit, expected 0: $launcher_output" >&2; exit 1; }
# From that unrelated cwd the session project's own list still applies to its files.
printf '%s\n' CLAUDE.md >> "$run/fresh/.agents/protected-paths.conf"
run_launcher "$other" "$run/fresh" "$run/fresh/CLAUDE.md"
cp "$run/protected-paths.conf.before" "$run/fresh/.agents/protected-paths.conf"
[ "$launcher_exit" -eq 2 ] || { echo "FAIL: launcher from another repository returned $launcher_exit for the session project's CLAUDE.md, expected 2: $launcher_output" >&2; exit 1; }
# A linked worktree of the SAME repository on a commit that predates the guard
# must still fail closed. The session project is a scratch repository that holds
# the guard uncommitted, so the worktree (cut from the bare commit) lacks it.
session="$run/wt-session"
git init -q "$session"
git -C "$session" -c user.name=smoke -c user.email=smoke@example.invalid commit -q --allow-empty -m base
git -C "$session" worktree add -q "$run/wt-linked" HEAD
mkdir -p "$session/.claude/hooks" "$session/.agents/hooks"
cp "$run/fresh/.agents/hooks/guard-protected-paths.sh" "$session/.agents/hooks/"
ln -s ../../.agents/hooks/guard-protected-paths.sh "$session/.claude/hooks/guard-protected-paths.sh"
run_launcher "$run/wt-linked" "$session" "$run/wt-linked/note.md"
[ "$launcher_exit" -eq 2 ] || { echo "FAIL: pre-guard linked worktree returned $launcher_exit, expected 2: $launcher_output" >&2; exit 1; }
case "$launcher_output" in
  *'required guard unavailable'*) ;;
  *) echo "FAIL: pre-guard linked worktree did not report the missing guard: $launcher_output" >&2; exit 1 ;;
esac
# From a subdirectory of the unrelated repository: a relative common dir would
# not resolve there, and "required guard unavailable" would return. (The
# launcher's `CDPATH=` has no probe: with absolute paths cd never reads it.)
mkdir -p "$other/sub"
run_launcher "$other/sub" "$run/fresh" "$other/sub/note.md"
[ "$launcher_exit" -eq 0 ] || { echo "FAIL: launcher in a subdirectory of another repository returned $launcher_exit, expected 0: $launcher_output" >&2; exit 1; }
# A session project that is not a repository, or that has no guard, gives
# nothing to compare or run: fail closed rather than fall back.
for session_dir in "$run/session-not-git" "$run/session-no-guard"; do
  mkdir -p "$session_dir"
  case "$session_dir" in *no-guard) git init -q "$session_dir" ;; esac
  run_launcher "$other" "$session_dir" "$other/note.md"
  case "$launcher_exit:$launcher_output" in
    2:*'required guard unavailable'*) ;;
    *) echo "FAIL: session project $session_dir returned $launcher_exit, expected 2 and a missing guard: $launcher_output" >&2; exit 1 ;;
  esac
done
# The Bash-matcher launcher is a separate copy of the command: run it too.
bash_launcher=$(jq -r '
  .hooks.PreToolUse[] | select(.matcher == "Bash")
  | .hooks[] | select(.statusMessage == "Checking protected paths") | .command
' "$run/fresh/.claude/settings.json")
[ -n "$bash_launcher" ] || { echo "FAIL: Bash protected-paths launcher not found in the fresh settings" >&2; exit 1; }
# run_bash_launcher <cwd> <session project> <command>: sets launcher_output, launcher_exit.
run_bash_launcher() {
  set +e
  launcher_output=$(cd "$1" && jq -n --arg c "$3" '{tool_name:"Bash",tool_input:{command:$c}}' \
    | env CLAUDE_PROJECT_DIR="$2" /bin/sh -c "$bash_launcher" 2>&1)
  launcher_exit=$?
  set -e
}
run_bash_launcher "$other" "$run/fresh" "echo x > $other/note.md"
[ "$launcher_exit" -eq 0 ] || { echo "FAIL: Bash launcher in another repository returned $launcher_exit, expected 0: $launcher_output" >&2; exit 1; }
run_bash_launcher "$run/wt-linked" "$session" "echo x > $run/wt-linked/note.md"
[ "$launcher_exit" -eq 2 ] || { echo "FAIL: Bash launcher in a pre-guard linked worktree returned $launcher_exit, expected 2: $launcher_output" >&2; exit 1; }
case "$launcher_output" in
  *'required guard unavailable'*) ;;
  *) echo "FAIL: Bash launcher in a pre-guard worktree did not report the missing guard: $launcher_output" >&2; exit 1 ;;
esac
# Each target is judged by the nearest ancestor holding .git, against that
# project's own list. Run the installed guard directly, from the fresh install.
fr=$(cd -P "$run/fresh" && pwd -P)
conf="$fr/.agents/protected-paths.conf"
run_guard() { # <payload>: sets guard_output, guard_exit
  set +e
  guard_output=$(cd "$fr" && printf '%s' "$1" | "$fr/.agents/hooks/guard-protected-paths.sh" 2>&1)
  guard_exit=$?
  set -e
}
expect_guard() { # <exit> <what> <payload>
  run_guard "$3"
  [ "$guard_exit" -eq "$1" ] || { echo "FAIL: $2 returned $guard_exit, expected $1: $guard_output" >&2; exit 1; }
}
write_payload() { printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s","content":"x"}}' "$fr" "$1"; }
printf '%s\n' CLAUDE.md '*only-outer.md' >> "$conf"
# An own-project refusal keeps its documented wording.
expect_guard 2 "own-project CLAUDE.md" "$(write_payload "$fr/CLAUDE.md")"
case "$guard_output" in
  *"is on this project's protected-paths list"*) ;;
  *) echo "FAIL: own-project refusal lost its wording: $guard_output" >&2; exit 1 ;;
esac
# A linked worktree nested in the install is its own project, with its own list.
nest_src="$run/nest-src"
git init -q "$nest_src"
git -C "$nest_src" -c user.name=smoke -c user.email=smoke@example.invalid commit -q --allow-empty -m base
git -C "$nest_src" worktree add -q "$fr/nested-wt" HEAD
[ -f "$fr/nested-wt/.git" ] || { echo "FAIL: nested worktree has no .git file" >&2; exit 1; }
mkdir -p "$fr/nested-wt/.agents"
printf '%s\n' only-nested.md > "$fr/nested-wt/.agents/protected-paths.conf"
expect_guard 2 "target listed only in the nested conf" "$(write_payload "$fr/nested-wt/only-nested.md")"
case "$guard_output" in
  *"the protected-paths list of the project at $fr/nested-wt"*) ;;
  *) echo "FAIL: nested refusal did not name the nested project: $guard_output" >&2; exit 1 ;;
esac
expect_guard 0 "target listed only in the outer conf but inside the nested repo" "$(write_payload "$fr/nested-wt/only-outer.md")"
# A first target in a project without a list must not end the run.
expect_guard 2 "MultiEdit with an unprotected first target" \
  '{"tool_name":"MultiEdit","cwd":"'"$fr"'","tool_input":{"file_path":"'"$other"'/a.md","edits":[{"file_path":"'"$fr"'/CLAUDE.md"}]}}'
# A pattern with * spans '/', so it matches a nested file.
printf '%s\n' 'docs/backup/*' > "$conf"
expect_guard 2 "glob pattern against a nested file" "$(write_payload "$fr/docs/backup/a/b.md")"
# A conf whose last line has no trailing newline still applies that line.
printf 'CLAUDE.md' > "$conf"
expect_guard 2 "conf without a trailing newline" "$(write_payload "$fr/CLAUDE.md")"
printf '%s\n' CLAUDE.md '*only-outer.md' > "$conf"
# Bash with several targets: an earlier target that needs no judgement must not
# end the run before a protected one.
bash_payload() { jq -n --arg c "$1" --arg d "$fr" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }
seed_repo="$run/seed-repo"
git init -q "$seed_repo"
mkdir -p "$seed_repo/.agents"
cp "$run/protected-paths.conf.before" "$seed_repo/.agents/protected-paths.conf"
expect_guard 2 "Bash: first target in a repository with only the seed conf" \
  "$(bash_payload "echo x > $seed_repo/a.md; echo y > $fr/CLAUDE.md")"
nonrepo=$(mktemp -d)
expect_guard 2 "Bash: first target outside any repository" \
  "$(bash_payload "echo x > $nonrepo/a.md; echo y > $fr/CLAUDE.md")"
rmdir "$nonrepo"
# A cd earlier in the command moves where a relative target lands (#61): from
# an unrelated repository, from a subdirectory, and inside a subshell.
other_payload() { jq -n --arg c "$1" --arg d "$2" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }
mkdir -p "$fr/sub"
expect_guard 2 "Bash: cd into the install, then a relative write" \
  "$(other_payload "cd $fr && printf x > CLAUDE.md" "$seed_repo")"
expect_guard 2 "Bash: cd .. from a subdirectory, then a relative write" \
  "$(other_payload "cd .. && printf x > CLAUDE.md" "$fr/sub")"
expect_guard 2 "Bash: a relative write after cd inside a subshell" \
  "$(other_payload "(cd $fr && printf x > CLAUDE.md)" "$seed_repo")"
expect_guard 0 "Bash: cd into the install, then an unprotected relative write" \
  "$(other_payload "cd $fr && printf x > notes.md" "$seed_repo")"
expect_guard 2 "Bash: if cd into the install, then a relative write" \
  "$(other_payload "if cd '$fr'; then printf x > CLAUDE.md; fi" "$seed_repo")"
expect_guard 2 "Bash: pushd into the install, then a relative write" \
  "$(other_payload "pushd $fr >/dev/null && printf x > CLAUDE.md" "$seed_repo")"
expect_guard 2 "Bash: cd into a subdirectory, then a write to ../" \
  "$(other_payload "cd $fr/sub && printf x > ../CLAUDE.md" "$seed_repo")"
# A long chain of relative cds stays fast (one base per cd, not a doubling).
chain="cd sub"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do chain="$chain && cd .. && cd sub"; done
# The alarm turns a regression into a FAIL rather than a hang.
set +e
chain_output=$(other_payload "$chain && printf x > notes.md" "$fr" \
  | (cd "$fr" && perl -e 'alarm 10; exec @ARGV' "$fr/.agents/hooks/guard-protected-paths.sh") 2>&1)
chain_exit=$?
set -e
[ "$chain_exit" -eq 0 ] || { echo "FAIL: a long chain of relative cds returned $chain_exit (142 is the 10s alarm): $chain_output" >&2; exit 1; }
# A cd after a subshell's cd may still start from the outer destination.
expect_guard 2 "Bash: cd after a subshell's cd, then a relative write" \
  "$(other_payload "cd $fr/sub && (cd x) && cd .. && printf x > CLAUDE.md" "$seed_repo")"
# Parentheses in an argument do not hide the target of cp or sed -i.
expect_guard 2 "Bash: sed -i with a regex group" \
  "$(bash_payload "sed -i -E 's/(a)/b/' CLAUDE.md")"
expect_guard 2 "Bash: cp from a command substitution" \
  "$(bash_payload "cp \"\$(pwd)/x\" CLAUDE.md")"
# A destination that is not literal leaves a relative target unjudgeable.
expect_guard 2 "Bash: a relative write after cd to a variable" \
  "$(other_payload 'cd "$X" && printf x > notes.md' "$seed_repo")"
case "$guard_output" in *'cannot be read literally'*) ;; *) echo "FAIL: non-literal cd refusal did not say why: $guard_output" >&2; exit 1 ;; esac
expect_guard 2 "Bash: a relative write after cd -" \
  "$(other_payload "cd - && printf x > notes.md" "$seed_repo")"
expect_guard 0 "Bash: cd to a variable, then no write" \
  "$(other_payload 'cd "$X" && git status' "$seed_repo")"
rmdir "$fr/sub"
# append-only: an existing file is refused, a new one is allowed, and a skipped
# (new-file) append-only entry must not hide a later entry that matches it.
mkdir -p "$fr/docs/snap"
: > "$fr/docs/snap/old.md"
printf '%s\n' 'append-only docs/snap/*' > "$conf"
expect_guard 2 "append-only glob, existing file" "$(write_payload "$fr/docs/snap/old.md")"
expect_guard 0 "append-only glob, new file" "$(write_payload "$fr/docs/snap/fresh.md")"
printf '%s\n' 'append-only docs/snap/*' 'docs/snap/new.md' > "$conf"
expect_guard 2 "new file matched by a later literal entry" "$(write_payload "$fr/docs/snap/new.md")"
printf '%s\n' CLAUDE.md '*only-outer.md' > "$conf"
# The Bash launcher's fallback must still judge a protected target: from an
# unrelated repository, a write to the session project's listed file is refused.
run_bash_launcher "$other" "$run/fresh" "echo y > $fr/CLAUDE.md"
case "$launcher_exit:$launcher_output" in
  2:*"is on this project's protected-paths list"*) ;;
  *) echo "FAIL: Bash launcher fallback let a protected write through ($launcher_exit): $launcher_output" >&2; exit 1 ;;
esac
# The launcher with neither a repository nor CLAUDE_PROJECT_DIR refuses.
nonrepo=$(mktemp -d)
run_launcher "$nonrepo" "" "$nonrepo/note.md"
rmdir "$nonrepo"
case "$launcher_exit:$launcher_output" in
  2:*'unable to resolve the Git repository root'*) ;;
  *) echo "FAIL: launcher without a repository or project dir returned $launcher_exit: $launcher_output" >&2; exit 1 ;;
esac
# A list the guard cannot read is a refusal, not an unprotected project.
if [ -r "$conf" ]; then
  chmod 000 "$conf"
  if [ ! -r "$conf" ]; then
    expect_guard 2 "unreadable conf" "$(write_payload "$fr/notes.md")"
    case "$guard_output" in *protected-paths.conf*) ;; *) chmod 644 "$conf"; echo "FAIL: unreadable-conf refusal did not name the conf: $guard_output" >&2; exit 1 ;; esac
  fi
  chmod 644 "$conf"
fi
# A list replaced by something that is not a regular file is a refusal too.
mv "$conf" "$run/conf.before-dir"
mkdir "$conf"
expect_guard 2 "conf that is a directory" "$(write_payload "$fr/notes.md")"
case "$guard_output" in *'not a regular file'*) ;; *) echo "FAIL: directory conf refusal did not say why: $guard_output" >&2; exit 1 ;; esac
rmdir "$conf"
mv "$run/conf.before-dir" "$conf"
cp "$run/protected-paths.conf.before" "$conf"
cp "$run/fresh/AGENTS.md" "$run/consumer-seed.before"
printf '%s\n' '# Agent Instructions' 'Consumer-specific routing lives here.' > "$run/fresh/AGENTS.md"
(cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh)
cp "$run/consumer-seed.before" "$run/fresh/AGENTS.md"
cmp "$run/consumer-seed.before" "$run/fresh/AGENTS.md"
claude_hook="$run/fresh/.claude/hooks/guard-collaborative-git.sh"
mv "$claude_hook" "$run/claude-guard-link.before"
ln -s /bin/true "$claude_hook"
if (cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh) > "$run/claude-link-failure.log" 2>&1; then
  echo 'FAIL: repointed Claude guard link was accepted' >&2; exit 1
fi
grep -q 'Claude guard link target is wrong' "$run/claude-link-failure.log"
mv "$run/claude-guard-link.before" "$claude_hook"
[ "$(readlink "$claude_hook")" = ../../.agents/hooks/guard-collaborative-git.sh ]
cp "$run/fresh/.claude/settings.json" "$run/claude-settings.before"
jq '.hooks.PreToolUse[0].hooks[0].command = "bash .claude/hooks/guard-collaborative-git.sh && true"' \
  "$run/fresh/.claude/settings.json" > "$run/fresh/.claude/settings.json.mutated"
mv "$run/fresh/.claude/settings.json.mutated" "$run/fresh/.claude/settings.json"
if (cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh) > "$run/claude-settings-failure.log" 2>&1; then
  echo 'FAIL: malformed Claude guard command was accepted' >&2; exit 1
fi
grep -q 'Claude PreToolUse guard is not wired' "$run/claude-settings-failure.log"
cp "$run/claude-settings.before" "$run/fresh/.claude/settings.json"
cmp "$run/claude-settings.before" "$run/fresh/.claude/settings.json"
mkdir -p "$run/fresh/docs/history"
printf '%s\n' 'Historical note: .agents/docs/git-commit.md' > "$run/fresh/docs/history/legacy-agent-paths.md"
(cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh)
cp "$run/fresh/.codex/hooks.json" "$run/codex-hooks.before"
jq '.hooks.PreToolUse[0].hooks += [{"type":"command","command":"\"$(git rev-parse --show-toplevel)/.agents/hooks/guard-protected-paths.sh\"","timeout":30,"statusMessage":"Checking protected paths"}]' \
  "$run/fresh/.codex/hooks.json" > "$run/fresh/.codex/hooks.json.mutated"
mv "$run/fresh/.codex/hooks.json.mutated" "$run/fresh/.codex/hooks.json"
(cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh)
jq '.hooks.PreToolUse[0].hooks += [.hooks.PreToolUse[0].hooks[0]]' \
  "$run/fresh/.codex/hooks.json" > "$run/fresh/.codex/hooks.json.mutated"
mv "$run/fresh/.codex/hooks.json.mutated" "$run/fresh/.codex/hooks.json"
if (cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh) > "$run/codex-hooks-failure.log" 2>&1; then
  echo 'FAIL: duplicate Codex guard handler was accepted' >&2; exit 1
fi
grep -q 'Codex PreToolUse guard is not wired' "$run/codex-hooks-failure.log"
cp "$run/codex-hooks.before" "$run/fresh/.codex/hooks.json"
cmp "$run/codex-hooks.before" "$run/fresh/.codex/hooks.json"
jq '.hooks.PreToolUse[0].hooks[0].command |= sub("guard-collaborative-git.sh"; "missing-guard.sh")' \
  "$run/fresh/.codex/hooks.json" > "$run/fresh/.codex/hooks.json.mutated"
mv "$run/fresh/.codex/hooks.json.mutated" "$run/fresh/.codex/hooks.json"
if (cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh) > "$run/codex-launcher-failure.log" 2>&1; then
  echo 'FAIL: malformed Codex launcher was accepted' >&2; exit 1
fi
grep -q 'Codex PreToolUse guard is not wired' "$run/codex-launcher-failure.log"
cp "$run/codex-hooks.before" "$run/fresh/.codex/hooks.json"
cmp "$run/codex-hooks.before" "$run/fresh/.codex/hooks.json"
cp "$run/fresh/.agents/AGENTS.md" "$run/active-router.before"
printf '%s\n' 'Legacy route: .agents/docs/git-commit.md' >> "$run/fresh/.agents/AGENTS.md"
if (cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh) > "$run/active-router-failure.log" 2>&1; then
  echo 'FAIL: active legacy reference was accepted' >&2; exit 1
fi
grep -q 'stale reference to .agents/docs/git-commit.md' "$run/active-router-failure.log"
cp "$run/active-router.before" "$run/fresh/.agents/AGENTS.md"
cmp "$run/active-router.before" "$run/fresh/.agents/AGENTS.md"
project_check="$run/fresh/.agents/hooks/check-project-agent-integration.sh"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'touch .project-check-ran' > "$project_check"
chmod +x "$project_check"
(cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh)
[ -f "$run/fresh/.project-check-ran" ]
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$project_check"
chmod +x "$project_check"
if (cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh) > "$run/project-check-failure.log" 2>&1; then
  echo 'FAIL: failing project integration check was accepted' >&2; exit 1
fi
grep -q 'project integration check failed' "$run/project-check-failure.log"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$project_check"
chmod +x "$project_check"
(cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh)
unlink "$project_check"
mkdir -p "$run/fresh/docs/temp/probe"
touch "$run/fresh/docs/temp/probe/file.md"
git -C "$run/fresh" check-ignore -v docs/temp/probe/file.md > "$run/ignore.log"
grep -q 'docs/temp/' "$run/ignore.log"
# The Skill links setup.sh makes are not payload files; they are asserted below.
actual=$(cd "$run/fresh" && { printf '%s\n' AGENTS.md CLAUDE.md .gitignore; find .agents .claude .codex -path .claude/skills -prune -o \( -type f -o -type l \) -print; })
inventory_check "the installed tree" "$actual"
printf 'local overlay\n' > "$run/fresh/local.txt"
printf '# local hook\n' > "$run/fresh/.agents/hooks/local.sh"
chmod 600 "$run/fresh/.agents/hooks/local.sh"
chmod 600 "$run/fresh/.agents/hooks/guard-collaborative-git.sh"
bash "$kit/install.sh" --working-tree --check "$run/fresh" > "$run/second-preview.log"
for rel in $expected; do grep -q "^IDENTICAL $rel$" "$run/second-preview.log"; done
[ ! -x "$run/fresh/.agents/hooks/guard-collaborative-git.sh" ]
bash "$kit/install.sh" --working-tree "$run/fresh" > "$run/reinstall.log"
[ -x "$run/fresh/.agents/hooks/guard-collaborative-git.sh" ]
[ ! -x "$run/fresh/.agents/hooks/local.sh" ]
[ "$(< "$run/fresh/local.txt")" = 'local overlay' ]
# The install ends by running the setup script the payload ships, so a fresh
# install already has the root CLAUDE.md pointer and the Claude Code Skill
# links, and running the script again has nothing left to do.
cmp "$kit/payload/CLAUDE.md" "$run/fresh/CLAUDE.md"
[ -x "$run/fresh/.agents/bin/setup.sh" ]
[ "$(git -C "$run/fresh" config --local core.hooksPath)" = .agents/githooks ]
[ "$(readlink "$run/fresh/.claude/skills/git-commit")" = ../../.agents/skills/git/commit ]
[ "$(readlink "$run/fresh/.claude/skills/git-create-pr")" = ../../.agents/skills/git/create-pr ]
[ "$(readlink "$run/fresh/.claude/skills/git-push")" = ../../.agents/skills/git/push ]
[ -f "$run/fresh/.claude/skills/git-commit/SKILL.md" ]
(cd "$run/fresh" && bash .agents/bin/setup.sh) > "$run/second-setup.log" 2>&1 \
  || { echo 'FAIL: a second setup run failed' >&2; cat "$run/second-setup.log" >&2; exit 1; }
grep -q 'nothing to change' "$run/second-setup.log" \
  || { echo 'FAIL: a second setup run did not say nothing to change' >&2; cat "$run/second-setup.log" >&2; exit 1; }

target self-check-failure
mkdir -p "$run/self-check-failure/.agents/hooks"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$run/self-check-failure/.agents/hooks/check-project-agent-integration.sh"
chmod +x "$run/self-check-failure/.agents/hooks/check-project-agent-integration.sh"
reject "$run/self-check-failure"
grep -q 'project integration check failed' "$run/rejection.log"
grep -q 'self-check FAILED' "$run/rejection.log"
for rel in $expected; do cmp "$kit/payload/$rel" "$run/self-check-failure/$rel"; done
[ "$(readlink "$run/self-check-failure/.claude/hooks/guard-collaborative-git.sh")" = ../../.agents/hooks/guard-collaborative-git.sh ]

target conflict
mkdir -p "$run/conflict/.claude"
printf 'local settings\n' > "$run/conflict/.claude/settings.json"
reject --check "$run/conflict"
grep -q '^CONFLICT .claude/settings.json ' "$run/rejection.log"
reject "$run/conflict"
[ ! -e "$run/conflict/AGENTS.md" ] && [ ! -e "$run/conflict/.agents" ]
[ "$(cat "$run/conflict/.claude/settings.json")" = 'local settings' ]

target codex-config-conflict
mkdir -p "$run/codex-config-conflict/.codex"
printf '%s\n' '[[hooks.PreToolUse]]' > "$run/codex-config-conflict/.codex/config.toml"
reject --check "$run/codex-config-conflict"
grep -q '^CONFLICT .codex/config.toml ' "$run/rejection.log"
reject "$run/codex-config-conflict"
[ ! -e "$run/codex-config-conflict/AGENTS.md" ] && [ ! -e "$run/codex-config-conflict/.agents" ]
[ ! -e "$run/codex-config-conflict/.codex/hooks.json" ]
[ ! -e "$run/codex-config-conflict/.codex/hooks/guard-collaborative-git.sh" ]
[ "$(cat "$run/codex-config-conflict/.codex/config.toml")" = '[[hooks.PreToolUse]]' ]

# A hook manager already in place is a conflict like any other: --check must
# report it, and a real install must refuse before it writes a single file.
# The installer used to find these only after copying the payload, while
# still printing "nothing was changed".
target hooks-path-conflict
git -C "$run/hooks-path-conflict" config core.hooksPath .husky/_
reject --check "$run/hooks-path-conflict"
grep -q '^CONFLICT core.hooksPath ' "$run/rejection.log"
reject "$run/hooks-path-conflict"
[ ! -e "$run/hooks-path-conflict/AGENTS.md" ] && [ ! -e "$run/hooks-path-conflict/.agents" ]
[ ! -e "$run/hooks-path-conflict/.friday-lock.json" ]
[ "$(git -C "$run/hooks-path-conflict" config core.hooksPath)" = .husky/_ ]

target git-hooks-conflict
printf '%s\n' '#!/bin/sh' 'exit 0' > "$run/git-hooks-conflict/.git/hooks/pre-commit"
reject --check "$run/git-hooks-conflict"
grep -q '^CONFLICT .git/hooks ' "$run/rejection.log"
reject "$run/git-hooks-conflict"
[ ! -e "$run/git-hooks-conflict/AGENTS.md" ] && [ ! -e "$run/git-hooks-conflict/.agents" ]
[ -z "$(git -C "$run/git-hooks-conflict" config core.hooksPath || true)" ]

target gitignore-conflict
printf 'local ignore rule\n' > "$run/gitignore-conflict/.gitignore"
reject --check "$run/gitignore-conflict"
grep -q '^CONFLICT .gitignore ' "$run/rejection.log"
reject "$run/gitignore-conflict"
[ ! -e "$run/gitignore-conflict/AGENTS.md" ] && [ ! -e "$run/gitignore-conflict/.agents" ]
[ "$(cat "$run/gitignore-conflict/.gitignore")" = 'local ignore rule' ]

# The Skill links setup.sh makes are checked by the same preflight: whatever
# setup would stop on is refused before a single file is written.
target skill-dir-conflict
mkdir -p "$run/skill-dir-conflict/.claude/skills/git-push"
printf 'mine\n' > "$run/skill-dir-conflict/.claude/skills/git-push/notes.txt"
reject --check "$run/skill-dir-conflict"
grep -q '^CONFLICT .claude/skills/git-push ' "$run/rejection.log"
reject "$run/skill-dir-conflict"
grep -q '^CONFLICT .claude/skills/git-push ' "$run/rejection.log"
[ ! -e "$run/skill-dir-conflict/AGENTS.md" ] && [ ! -e "$run/skill-dir-conflict/.agents" ]
[ ! -e "$run/skill-dir-conflict/.friday-lock.json" ]
[ -z "$(git -C "$run/skill-dir-conflict" config core.hooksPath || true)" ]
[ "$(cat "$run/skill-dir-conflict/.claude/skills/git-push/notes.txt")" = mine ]

target skill-link-elsewhere
mkdir -p "$run/skill-link-elsewhere/.claude/skills" "$run/skill-link-elsewhere/mine"
ln -s ../../mine "$run/skill-link-elsewhere/.claude/skills/git-commit"
reject --check "$run/skill-link-elsewhere"
grep -q '^CONFLICT .claude/skills/git-commit ' "$run/rejection.log"
reject "$run/skill-link-elsewhere"
[ ! -e "$run/skill-link-elsewhere/AGENTS.md" ] && [ ! -e "$run/skill-link-elsewhere/.agents" ]

target skill-parent-link
mkdir -p "$run/skill-parent-link/.claude" "$run/skill-parent-elsewhere"
ln -s "$run/skill-parent-elsewhere" "$run/skill-parent-link/.claude/skills"
reject --check "$run/skill-parent-link"
grep -q '^CONFLICT .claude/skills/git-commit (unsafe parent' "$run/rejection.log"
reject "$run/skill-parent-link"
[ ! -e "$run/skill-parent-link/AGENTS.md" ] && [ -z "$(ls -A "$run/skill-parent-elsewhere")" ]

# A correct link may already be there (it dangles until the install copies the
# Skill), and so may a dangling one pointing nowhere useful; neither blocks.
target skill-link-ok
mkdir -p "$run/skill-link-ok/.claude/skills"
ln -s ../../.agents/skills/git/push "$run/skill-link-ok/.claude/skills/git-push"
ln -s ../../.agents/skills/old/commit "$run/skill-link-ok/.claude/skills/git-commit"
bash "$kit/install.sh" --working-tree --check "$run/skill-link-ok" > "$run/skill-link-ok-preview.log"
grep -q '^IDENTICAL .claude/skills/git-push$' "$run/skill-link-ok-preview.log"
grep -q '^NEW .claude/skills/git-commit (replaces a dangling link' "$run/skill-link-ok-preview.log"
bash "$kit/install.sh" --working-tree "$run/skill-link-ok" > "$run/skill-link-ok.log"
[ "$(readlink "$run/skill-link-ok/.claude/skills/git-push")" = ../../.agents/skills/git/push ]
[ "$(readlink "$run/skill-link-ok/.claude/skills/git-commit")" = ../../.agents/skills/git/commit ]
[ -f "$run/skill-link-ok/.claude/skills/git-push/SKILL.md" ]
[ -f "$run/skill-link-ok/.claude/skills/git-commit/SKILL.md" ]

# Install must refuse every conflict setup would later stop on, including the
# ones that depend on what the copy itself will put there. Both modes refuse and
# neither writes a file.
refused() { # <target> <CONFLICT line prefix>
  reject --check "$run/$1"
  grep -q "^CONFLICT $2" "$run/rejection.log" || { echo "FAIL: --check did not report CONFLICT $2" >&2; exit 1; }
  reject "$run/$1"
  grep -q "^CONFLICT $2" "$run/rejection.log" || { echo "FAIL: install did not report CONFLICT $2" >&2; exit 1; }
  [ ! -e "$run/$1/AGENTS.md" ] && [ ! -e "$run/$1/CLAUDE.md" ] && [ ! -e "$run/$1/.agents/AGENTS.md" ] \
    && [ ! -e "$run/$1/.agents/skills/git" ] && [ ! -e "$run/$1/.friday-lock.json" ] \
    || { echo "FAIL: a refused install wrote into $1" >&2; exit 1; }
  [ -z "$(git -C "$run/$1" config --local core.hooksPath || true)" ]
}

target skill-own-dir
mkdir -p "$run/skill-own-dir/.agents/skills/mine" "$run/skill-own-dir/.claude/skills/mine"
printf -- '---\ndescription: theirs\n---\n' > "$run/skill-own-dir/.agents/skills/mine/SKILL.md"
refused skill-own-dir '.claude/skills/mine (exists and is not a symlink)'

target skill-own-name
mkdir -p "$run/skill-own-name/.agents/skills/mine"
printf -- '---\nname: git-commit\n---\n' > "$run/skill-own-name/.agents/skills/mine/SKILL.md"
refused skill-own-name '.claude/skills/git-commit (declared by more than one Skill: .agents/skills/git/commit, .agents/skills/mine'

# A dangling link becomes live once the install creates what it points at.
target skill-dangling-becomes-live
mkdir -p "$run/skill-dangling-becomes-live/.claude/skills"
ln -s ../../.agents/docs "$run/skill-dangling-becomes-live/.claude/skills/git-push"
refused skill-dangling-becomes-live '.claude/skills/git-push (points to ../../.agents/docs'

# A dangling link of a form setup never writes is not setup's to replace.
target skill-dangling-foreign
mkdir -p "$run/skill-dangling-foreign/.claude/skills"
ln -s ../../nowhere "$run/skill-dangling-foreign/.claude/skills/git-push"
refused skill-dangling-foreign '.claude/skills/git-push (a dangling link to ../../nowhere'

# The effective core.hooksPath counts, from whichever scope it comes.
target hooks-path-global
printf '[core]\n\thooksPath = .husky/_\n' > "$run/global-husky.gitconfig"
( export GIT_CONFIG_GLOBAL="$run/global-husky.gitconfig"; refused hooks-path-global 'core.hooksPath (already set to '"'"'.husky/_'"'"'' )

target git-hooks-symlink
ln -s "$run" "$run/git-hooks-symlink/.git/hooks/pre-commit"
refused git-hooks-symlink '.git/hooks '

target parent-link
mkdir -p "$run/outside"
ln -s "$run/outside" "$run/parent-link/.agents"
reject "$run/parent-link"
[ ! -e "$run/outside/hooks" ] && [ ! -e "$run/parent-link/AGENTS.md" ]

target file-link
mkdir -p "$run/file-link/.claude"
printf 'outside content\n' > "$run/outside/settings.json"
ln -s "$run/outside/settings.json" "$run/file-link/.claude/settings.json"
reject "$run/file-link"
[ ! -e "$run/file-link/AGENTS.md" ]
[ "$(cat "$run/outside/settings.json")" = 'outside content' ]

target dangling
mkdir -p "$run/dangling/.claude/hooks"
ln -s "$run/absent" "$run/dangling/.claude/hooks/guard-collaborative-git.sh"
reject "$run/dangling"
[ -L "$run/dangling/.claude/hooks/guard-collaborative-git.sh" ]
[ ! -e "$run/dangling/AGENTS.md" ]

target type-conflict
mkdir -p "$run/type-conflict/AGENTS.md"
reject "$run/type-conflict"
[ ! -e "$run/type-conflict/.agents" ]

target linked-worktree-main
git -C "$run/linked-worktree-main" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
git -C "$run/linked-worktree-main" worktree add -q "$run/linked-worktree" -b wt
reject --check "$run/linked-worktree"
grep -q 'is a linked worktree' "$run/rejection.log"
reject "$run/linked-worktree"
grep -q 'is a linked worktree' "$run/rejection.log"
[ ! -e "$run/linked-worktree/AGENTS.md" ]
[ ! -e "$run/linked-worktree/.agents" ]
[ -z "$(git -C "$run/linked-worktree-main" config core.hooksPath || true)" ]

reject --unknown
reject "$run/fresh" extra
reject "$kit"
reject "$run/outside"

# Keep dirname available so this fails at the jq preflight, not earlier.
target missing-jq
mkdir -p "$run/no-jq-bin"
ln -s /usr/bin/dirname "$run/no-jq-bin/dirname"
if PATH="$run/no-jq-bin" /bin/bash "$kit/install.sh" --working-tree "$run/missing-jq" > "$run/missing-jq.log" 2>&1; then
  echo 'FAIL: missing prerequisite accepted' >&2; exit 1
fi
grep -q "'jq' is required" "$run/missing-jq.log"
[ ! -e "$run/missing-jq/AGENTS.md" ] && [ ! -e "$run/missing-jq/.agents" ]
# --- the lock the install writes ---------------------------------------------
# Assert all three states, not only the happy one. Three plainly wrong
# implementations have passed a suite here before, each time because the suite
# only ever checked that the right thing reported right.
target lock
/bin/bash "$kit/install.sh" --working-tree "$run/lock" > "$run/lock.log" 2>&1
[ -f "$run/lock/.friday-lock.json" ] || { echo 'FAIL: install wrote no lock' >&2; exit 1; }
jq -e . "$run/lock/.friday-lock.json" >/dev/null || { echo 'FAIL: lock is not valid JSON' >&2; exit 1; }
/bin/bash "$kit/bin/friday-lock" check "$run/lock" | grep -q 'status: in sync' \
  || { echo 'FAIL: a fresh install does not check in sync' >&2; exit 1; }

printf '\n# drift\n' >> "$run/lock/.agents/docs/testing.md"
if /bin/bash "$kit/bin/friday-lock" check "$run/lock" > "$run/lock-drift.log" 2>&1; then
  echo 'FAIL: an edited managed-core file still reported success' >&2; exit 1
fi
grep -q 'status: drifted' "$run/lock-drift.log" || { echo 'FAIL: edit not reported as drifted' >&2; exit 1; }
grep -q 'agents/docs/testing.md' "$run/lock-drift.log" || { echo 'FAIL: drift did not name the file' >&2; exit 1; }
cp "$kit/payload/.agents/docs/testing.md" "$run/lock/.agents/docs/testing.md"

rm "$run/lock/.agents/githooks/commit-msg"
if /bin/bash "$kit/bin/friday-lock" check "$run/lock" > "$run/lock-missing.log" 2>&1; then
  echo 'FAIL: a missing managed-core file still reported success' >&2; exit 1
fi
grep -q 'missing' "$run/lock-missing.log" || { echo 'FAIL: missing file not reported as missing' >&2; exit 1; }
echo "PASS: lock written on install; drift and deletion are both refused"

echo "PASS: live payload, preview states, self-check, idempotence, conflict/type/symlink gates, arguments and prerequisites"
echo "Retained fixture evidence: $run"
