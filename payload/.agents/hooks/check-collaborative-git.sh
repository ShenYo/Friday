#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

fail() {
  echo "Agent workflow guardrail failed: $1" >&2
  exit 1
}

guard=".agents/hooks/guard-collaborative-git.sh"
test -x "$guard" || fail "shared guard is not executable"

claude_hook=.claude/hooks/guard-collaborative-git.sh
test -L "$claude_hook" || fail "Claude guard link missing"
[ "$(readlink "$claude_hook")" = ../../.agents/hooks/guard-collaborative-git.sh ] \
  || fail "Claude guard link target is wrong"
test -f .claude/settings.json || fail "Claude settings missing"
# The Claude launcher must resolve the guard by absolute path. A hook's working
# directory is not pinned to the project root, so a relative launcher path can
# exit 127 — a non-blocking error that lets the tool call proceed. Hence the
# repository of the working directory first, the session root only as a
# fallback, a pinned PATH, dependency and readability checks that exit 2, and
# onFailure=block so a residual non-2 failure or a timeout still blocks
# instead of failing open.
claude_path_prefix='PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"'
jq -e '
  def claude_guard:
    type == "object" and
    .type == "command" and
    (.command | startswith($prefix)) and
    (.command | contains("command -v \"$required\"")) and
    (.command | contains("git_root=\"$(git rev-parse --show-toplevel 2>/dev/null)\"")) and
    (.command | contains("env_root=\"${CLAUDE_PROJECT_DIR:-}\"")) and
    # Precedence is the whole point: the repository the hook is actually
    # operating in must be tried first. CLAUDE_PROJECT_DIR stays pinned to the
    # checkout where the session started, while the hook working directory and
    # the payload cwd follow Claude Code into a worktree. Assert the literal
    # order, because a substring set alone passes on either order.
    #
    # The fallback to the environment root is safe HERE and only here: this
    # guard judges the requested command and ignores the repository root, so
    # either root yields the same verdict, and keeping the fallback means a
    # checkout that does not carry the guard still gets the boundary instead of
    # refusing every command. A root-SENSITIVE guard must not use this shape --
    # see the protected-paths launcher, which takes the repository of the
    # working directory as its only source.
    (.command | contains("for candidate_root in \"$git_root\" \"$env_root\"")) and
    (.command | contains("BLOCKED: unable to resolve the Git repository root.")) and
    (.command | contains("guard_rel=\".claude/hooks/guard-collaborative-git.sh\"")) and
    (.command | contains("[ -f \"$candidate_root/$guard_rel\" ] && [ -r \"$candidate_root/$guard_rel\" ]")) and
    (.command | contains("exec bash \"$guard_path\"")) and
    .timeout == 30 and
    .onFailure == "block" and
    .statusMessage == "Checking collaborative Git safety boundary";
  any(.hooks.PreToolUse[];
    .matcher == "Bash" and any(.hooks[]; claude_guard)
  )
' --arg prefix "$claude_path_prefix" .claude/settings.json >/dev/null \
  || fail "Claude PreToolUse guard is not wired (note: the onFailure=block
assertion certifies configuration only; Claude Code below v2.1.295 ignores
that field, so a residual non-2 exit or a timeout would not block there)"

codex_hook=.codex/hooks/guard-collaborative-git.sh
test -L "$codex_hook" || fail "Codex guard link missing"
[ "$(readlink "$codex_hook")" = ../../.agents/hooks/guard-collaborative-git.sh ] \
  || fail "Codex guard link target is wrong"
test -f .codex/hooks.json || fail "Codex hooks configuration missing"
codex_path_prefix='PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"'
jq -e '
  def generic:
    type == "object" and
    .type == "command" and
    (.command | startswith($prefix)) and
    (.command | contains("command -v \"$required\"")) and
    (.command | contains("repo_root=\"$(git rev-parse --show-toplevel 2>/dev/null)\"")) and
    (.command | contains("guard_path=\"$repo_root/.codex/hooks/guard-collaborative-git.sh\"")) and
    (.command | contains("[ ! -f \"$guard_path\" ] || [ ! -r \"$guard_path\" ]")) and
    (.command | contains("exec bash \"$guard_path\"")) and
    .timeout == 30 and
    .statusMessage == "Checking collaborative Git safety boundary";
  type == "object" and
  (.hooks | type == "object") and
  (.hooks.PreToolUse | type == "array") and
  ([.hooks.PreToolUse[] | select(type == "object" and .matcher == "^(Bash|apply_patch)$")] | length == 1) and
  (.hooks.PreToolUse[] | select(type == "object" and .matcher == "^(Bash|apply_patch)$") | (.hooks | type == "array")) and
  ([.hooks.PreToolUse[] | select(type == "object" and .matcher == "^(Bash|apply_patch)$") | .hooks[] | select(generic)] | length == 1) and
  ([.hooks.PreToolUse[] | select(type == "object" and (.hooks | type == "array")) | .hooks[] | select(generic)] | length == 1)
' --arg prefix "$codex_path_prefix" .codex/hooks.json >/dev/null || fail "Codex PreToolUse guard is not wired"
if [ -f .codex/config.toml ] \
  && grep -Eq '^[[:space:]]*\[\[hooks\.' .codex/config.toml; then
  fail "Codex config contains inline hooks"
fi

run_codex_command() {
  local launcher=$1 payload=$2 expected=$3 path=$4 cwd=$5 output exit_code

  set +e
  output=$(cd "$cwd" && printf '%s' "$payload" | env PATH="$path" /bin/sh -c "$launcher" 2>&1)
  exit_code=$?
  set -e

  [ "$exit_code" -eq "$expected" ] \
    || fail "Codex launcher returned $exit_code, expected $expected (PATH=$path, cwd=$cwd): $output"
  codex_command_output=$output
}

collaborative_launcher=$(jq -r '
  .hooks.PreToolUse[] | select(.matcher == "^(Bash|apply_patch)$")
  | .hooks[] | select(.statusMessage == "Checking collaborative Git safety boundary") | .command
' .codex/hooks.json)
[ -n "$collaborative_launcher" ] && [ "$collaborative_launcher" != null ] \
  || fail "Codex collaborative launcher command is missing"

harmless_bash='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
for restricted_path in /bin /usr/bin; do
  run_codex_command "$collaborative_launcher" "$harmless_bash" 0 "$restricted_path" "$repo_root"
  run_codex_command "$collaborative_launcher" "$harmless_bash" 0 "$restricted_path" "$repo_root/.agents"
  run_codex_command "$collaborative_launcher" \
    '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' \
    2 "$restricted_path" "$repo_root"
  run_codex_command "$collaborative_launcher" \
    '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' \
    2 "$restricted_path" "$repo_root/.agents"
done

run_codex_command "$collaborative_launcher" "$harmless_bash" 2 /bin /
case "$codex_command_output" in
  *'BLOCKED: unable to resolve the Git repository root.'*) ;;
  *) fail "unresolved Git root did not produce a concise BLOCKED message: $codex_command_output" ;;
esac
case "$codex_command_output" in
  *fatal:*) fail "unresolved Git root leaked Git diagnostics: $codex_command_output" ;;
esac

# Fixture cleanup. A single EXIT trap replaces any earlier one, so every
# fixture registers its root here and one handler removes them all, including
# when a fail() aborts partway. It is set up before the first fixture: set up
# after them, it emptied the list and left the first two behind on every run. Files go individually with rm -f and
# directories with rmdir, never recursively.
fixture_roots=()
cleanup_fixtures() {
  local root file dir
  for root in ${fixture_roots[@]+"${fixture_roots[@]}"}; do
    [ -n "$root" ] || continue
    while IFS= read -r file; do rm -f "$file"; done \
      < <(find "$root" \( -type f -o -type l \) 2>/dev/null)
    while IFS= read -r dir; do rmdir "$dir" 2>/dev/null || true; done \
      < <(find "$root" -depth -type d 2>/dev/null)
  done
}
trap cleanup_fixtures EXIT

# The launcher appends the inherited PATH to its pinned list, so naming a
# missing directory is only half the condition: the caller's PATH has to lack
# the tool as well. Passing /bin for that worked on macOS, where /bin is
# sparse, and did nothing on Linux, where /bin is a symlink to /usr/bin and
# carries the whole toolset -- the launcher ran normally and the probe failed
# in CI while passing locally. Use an empty directory on both sides instead.
toolless_dir=$(mktemp -d)
fixture_roots+=("$toolless_dir")
missing_path_launcher=$(printf '%s' "$collaborative_launcher" \
  | sed "s@/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin@$toolless_dir@g")
run_codex_command "$missing_path_launcher" "$harmless_bash" 2 "$toolless_dir" "$repo_root"
case "$codex_command_output" in
  *'BLOCKED: required executable unavailable: git'*) ;;
  *) fail "missing Git dependency did not produce a concise BLOCKED message: $codex_command_output" ;;
esac

# Simulating a missing bash by naming a real directory is not portable: it
# assumed bash lives in /bin and not /usr/bin, which holds on macOS and is
# false on Linux, where /usr/bin/bash exists and the substitution simulates
# nothing. The launcher then ran normally and the probe failed in CI while
# passing locally. Build a directory that definitely has git and definitely
# has no bash instead, so the condition is real on any platform.
bashless_dir=$(mktemp -d)
fixture_roots+=("$bashless_dir")
ln -s "$(command -v git)" "$bashless_dir/git"
missing_bash_launcher=$(printf '%s' "$collaborative_launcher" \
  | sed "s@PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin\${PATH:+:\$PATH}\"@PATH=\"$bashless_dir\"@")
run_codex_command "$missing_bash_launcher" "$harmless_bash" 2 "$bashless_dir" "$repo_root"
case "$codex_command_output" in
  *'BLOCKED: required executable unavailable: bash'*) ;;
  *) fail "missing Bash dependency did not produce a concise BLOCKED message: $codex_command_output" ;;
esac

broken_guard_launcher=$(printf '%s' "$collaborative_launcher" \
  | sed 's@guard-collaborative-git.sh@missing-guard.sh@g')
run_codex_command "$broken_guard_launcher" "$harmless_bash" 2 /bin "$repo_root"
case "$codex_command_output" in
  *'BLOCKED: required guard unavailable:'*) ;;
  *) fail "missing guard did not produce a concise BLOCKED message: $codex_command_output" ;;
esac


# --- Claude launcher: execute it, do not only match its text -----------------
# Static wiring proved the launcher string. These probes prove the string the
# runtime is configured with actually blocks from the working directories a
# hook can really run in. Native callback delivery and exit-code consumption
# are a separate claim, established for this launcher on Claude Code 2.1.306
# and recorded by the project; re-establish it on a version change.
run_claude_command() {
  local payload=$1 expected=$2 expected_msg=$3 path=$4 cwd=$5 output exit_code
  shift 5

  # -u comes before the assignments so a caller-supplied CLAUDE_PROJECT_DIR
  # still wins, while the default is genuinely unset even if this checker is
  # itself running inside a hook. /bin/sh is absolute because "$path" is not
  # required to contain env or sh.
  set +e
  output=$(cd "$cwd" && printf '%s' "$payload" \
    | env -u CLAUDE_PROJECT_DIR PATH="$path" "$@" /bin/sh -c "$claude_launcher" 2>&1)
  exit_code=$?
  set -e

  [ "$exit_code" -eq "$expected" ] \
    || fail "Claude launcher returned $exit_code, expected $expected (PATH=$path, cwd=$cwd): $output"
  # Status alone is not enough: exit 2 is reachable for several different
  # reasons, so a probe that checks only the status can pass for the wrong one.
  if [ -n "$expected_msg" ]; then
    case "$output" in
      *"$expected_msg"*) ;;
      *) fail "Claude launcher exited $exit_code but not for the expected reason (PATH=$path, cwd=$cwd); wanted '$expected_msg', got: $output" ;;
    esac
  fi
  claude_command_output=$output
}

claude_launcher=$(jq -r '
  .hooks.PreToolUse[] | select(.matcher == "Bash")
  | .hooks[] | select(.statusMessage == "Checking collaborative Git safety boundary")
  | .command
' .claude/settings.json)
[ -n "$claude_launcher" ] && [ "$claude_launcher" != null ] \
  || fail "Claude collaborative launcher command is missing"

force_push='{"tool_name":"Bash","tool_input":{"command":"git push --force"}}'
for restricted_path in /bin /usr/bin; do
  # The repository root, and a subdirectory of it: a relative launcher path
  # would exit 127 from the subdirectory instead of blocking.
  run_claude_command "$harmless_bash" 0 "" "$restricted_path" "$repo_root"
  run_claude_command "$harmless_bash" 0 "" "$restricted_path" "$repo_root/.agents"
  run_claude_command "$force_push" 2 "permanently agent-prohibited" "$restricted_path" "$repo_root"
  run_claude_command "$force_push" 2 "permanently agent-prohibited" "$restricted_path" "$repo_root/.agents"
done

# Outside the repository, CLAUDE_PROJECT_DIR is what makes resolution work.
run_claude_command "$force_push" 2 "permanently agent-prohibited" /bin / CLAUDE_PROJECT_DIR="$repo_root"
run_claude_command "$harmless_bash" 0 "" /bin / CLAUDE_PROJECT_DIR="$repo_root"

# With neither a usable working directory nor CLAUDE_PROJECT_DIR, fail closed.
run_claude_command "$harmless_bash" 2 "unable to resolve the Git repository root." /bin /
case "$claude_command_output" in
  *'BLOCKED: unable to resolve the Git repository root.'*) ;;
  *) fail "Claude launcher did not fail closed on an unresolved Git root: $claude_command_output" ;;
esac
case "$claude_command_output" in
  *fatal:*) fail "Claude launcher leaked Git diagnostics: $claude_command_output" ;;
esac

claude_missing_path_launcher=$claude_launcher
claude_launcher=$(printf '%s' "$claude_missing_path_launcher" \
  | sed "s@/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin@$toolless_dir@g")
run_claude_command "$harmless_bash" 2 "BLOCKED: required" "$toolless_dir" "$repo_root"
case "$claude_command_output" in
  *'BLOCKED: required executable unavailable: git'*) ;;
  *) fail "Claude launcher did not fail closed on a missing Git dependency: $claude_command_output" ;;
esac

claude_launcher=$(printf '%s' "$claude_missing_path_launcher" \
  | sed 's@guard-collaborative-git.sh@missing-guard.sh@g')
run_claude_command "$harmless_bash" 2 "BLOCKED: required" /bin "$repo_root"
case "$claude_command_output" in
  *'BLOCKED: required guard unavailable:'*) ;;
  *) fail "Claude launcher did not fail closed on a missing guard: $claude_command_output" ;;
esac
claude_launcher=$claude_missing_path_launcher

# A decoy guard reached only through CLAUDE_PROJECT_DIR. The launcher must
# ignore it while the working directory resolves a real repository, otherwise a
# worktree or second checkout would be guarded by the wrong root. Neither a
# substring assertion nor a probe that keeps every root equal can see this.
claude_decoy_root=$(mktemp -d)
fixture_roots+=("$claude_decoy_root")
mkdir -p "$claude_decoy_root/.claude/hooks"
printf '#!/bin/bash\nexit 0\n' > "$claude_decoy_root/.claude/hooks/guard-collaborative-git.sh"
chmod +x "$claude_decoy_root/.claude/hooks/guard-collaborative-git.sh"
run_claude_command "$force_push" 2 "permanently agent-prohibited" /bin "$repo_root" CLAUDE_PROJECT_DIR="$claude_decoy_root"
case "$claude_command_output" in
  *'permanently agent-prohibited'*) ;;
  *) fail "Claude launcher preferred CLAUDE_PROJECT_DIR over the working directory's repository: $claude_command_output" ;;
esac
run_claude_command "$force_push" 2 "permanently agent-prohibited" /bin "$repo_root/.agents" CLAUDE_PROJECT_DIR="$claude_decoy_root"
# Only when the working directory resolves no usable guard may the environment
# root be used as a fallback.
run_claude_command "$harmless_bash" 0 "" /bin / CLAUDE_PROJECT_DIR="$claude_decoy_root"

set +e
# This probe is specifically about jq, so the directory must carry the guard's
# other dependencies and lack only that one. An entirely empty directory makes
# the guard report the first missing tool instead, which is cat.
jqless_dir=$(mktemp -d)
fixture_roots+=("$jqless_dir")
for dependency in cat grep; do
  ln -s "$(command -v "$dependency")" "$jqless_dir/$dependency"
done
missing_jq_output=$(sed "s@/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin@$jqless_dir@g" "$guard" \
  | env PATH="$jqless_dir" /bin/bash 2>&1)
missing_jq_exit=$?
set -e
[ "$missing_jq_exit" -eq 2 ] \
  || fail "missing jq dependency returned $missing_jq_exit, expected 2: $missing_jq_output"
case "$missing_jq_output" in
  *'BLOCKED: required executable unavailable: jq'*) ;;
  *) fail "missing jq dependency did not produce a concise BLOCKED message: $missing_jq_output" ;;
esac
case "$missing_jq_output" in
  *jq:*) fail "missing jq dependency leaked jq diagnostics: $missing_jq_output" ;;
esac

for path in \
  AGENTS.md \
  .agents/AGENTS.md \
  .agents/docs/agent-rules.md \
  .agents/docs/testing.md \
  .agents/docs/scratch-files.md \
  .agents/docs/git-guideline/git-commit.md \
  .agents/docs/git-guideline/pr-evidence.md \
  .agents/docs/git-guideline/safety-boundary.md; do
  test -f "$path" || fail "canonical document missing: $path"
done

# Search active instruction surfaces only. Historical product documentation,
# evidence, and scratch artifacts may accurately record old paths without
# directing an agent to use them.
search_active_instructions() {
  for path in \
    AGENTS.md \
    .agents/AGENTS.md \
    .agents/docs/agent-rules.md \
    .agents/docs/testing.md \
    .agents/docs/scratch-files.md \
    .agents/docs/git-guideline \
    .agents/skills \
    .claude/settings.json \
    .codex/hooks.json; do
    [ -e "$path" ] || continue
    grep -r --fixed-strings --quiet -e "$1" "$path" && return 0
  done
  return 1
}

# Prove the scoped search works before trusting any negative result. This text
# is part of the managed core's active safety instructions, so success proves
# both grep and the instruction-surface selection are usable without relying
# on a consumer-specific seed heading.
search_active_instructions 'Collaborative Git Safety Boundary' \
  || fail "active instruction search is not working — its negative results cannot be trusted"
grep -Fq '[`testing.md`](testing.md)' .agents/docs/agent-rules.md \
  || fail "agent rules do not route testing work to the scenario-driven contract"
search_active_instructions 'Scenario-Driven Testing' \
  || fail "scenario-driven testing contract is not on an active instruction surface"

for legacy_path in \
  .agents/docs/git-commit.md \
  .agents/docs/issue-tracker.md \
  .agents/docs/pr-evidence.md \
  .agents/docs/safety-boundary.md; do
  if search_active_instructions "$legacy_path"; then
    fail "stale reference to $legacy_path"
  fi
done

run_guard() {
  local payload=$1 output exit_code

  set +e
  output=$(printf '%s' "$payload" | "$guard" 2>&1)
  exit_code=$?
  set -e

  guard_output=$output
  guard_exit=$exit_code
}

require_guard_blocked() {
  run_guard "$1"
  [ "$guard_exit" -eq 2 ] \
    || fail "guard returned $guard_exit, expected 2: $guard_output"
  case "$guard_output" in
    BLOCKED:*) ;;
    *) fail "guard did not produce a concise BLOCKED message: $guard_output" ;;
  esac
  case "$guard_output" in
    *jq:*) fail "guard leaked jq diagnostics: $guard_output" ;;
  esac
}

run_guard '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
[ "$guard_exit" -eq 0 ] || fail "guard blocked an allowed Bash payload: $guard_output"
# Deliberately NOT asserted here: whether `git push origin main` is allowed.
# safety-boundary.md reserves a direct push to the default branch for a human,
# and the guard does not enforce that today. An earlier revision of this file
# asserted the push must be ALLOWED, calling it "an allowed normal push", which
# certified the gap as intended behavior and would have failed the suite for
# anyone who fixed it. The row is unenforced and the document says so.
run_guard '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/topic"}}'
[ "$guard_exit" -eq 0 ] || fail "guard blocked a feature-branch push: $guard_output"
run_guard '{"tool_name":"Bash","tool_input":{"command":"gh api --method=GET /repos/o/r"}}'
[ "$guard_exit" -eq 0 ] || fail "guard blocked an allowed GET probe: $guard_output"
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease=origin/main"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"git push --force=origin/main"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"gh api --method=DELETE /repos/o/r"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"gh api -X=DELETE /repos/o/r"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"gh api -XDELETE /repos/o/r"}}'
# Deleting a ref destroys work that may live nowhere else. Both spellings, both
# local and remote, and tags as well as branches.
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"git branch -d feat/x"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"git branch -D feat/x"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"git branch --delete feat/x"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"git tag -d v1"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"git push origin --delete feat/x"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"git push origin :feat/x"}}'
# Human-review checkpoints: integrating a change, delegating that decision to
# CI, and altering a shared review artifact.
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 12"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"gh pr merge --auto --squash 12"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"gh pr close 12"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":"gh pr reopen 12"}}'

# Ordinary version control is agent discretion now, so these must stay allowed;
# a guard that blocks them would make the policy unusable rather than safe.
for allowed_command in \
  'git commit -m x' \
  'git push origin feat/x' \
  'git push -u origin feat/x' \
  'git push origin HEAD:refs/heads/feat/x' \
  'git push --dry-run origin feat/x' \
  'git tag v1' \
  'git branch feat/new' \
  'gh pr create --fill' \
  'gh pr view 12' \
  'gh pr review --approve 12'; do
  run_guard "$(jq -cn --arg c "$allowed_command" \
    '{tool_name:"Bash", tool_input:{command:$c}}')"
  [ "$guard_exit" -eq 0 ] \
    || fail "guard blocked an agent-discretion command '$allowed_command': $guard_output"
done

# Disabling the commit-time hooks, in every spelling that reaches it. The flag
# may follow a quoted message, the config key is case-insensitive, the
# assignment may be quoted, and the persistent and environment forms count too.
# A quoted message used to void these rules entirely, which made the whole
# commit-time layer skippable.
for bypass_command in \
  'git commit --no-verify -m x' \
  'git commit -m "feat: add a thing" --no-verify' \
  "git commit -m 'feat: add a thing' -n" \
  'git commit -m "feat: add a thing" -nm y' \
  'git -c core.hooksPath=/dev/null commit -m x' \
  'git -c "core.hooksPath=/dev/null" commit -m x' \
  'git -c core.hookspath=/dev/null commit -m x' \
  'git config core.hooksPath /dev/null' \
  'git config --local core.hookspath /tmp/x' \
  'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git commit -m x'; do
  run_guard "$(jq -cn --arg c "$bypass_command" \
    '{tool_name:"Bash", tool_input:{command:$c}}')"
  [ "$guard_exit" -eq 2 ] \
    || fail "guard allowed a command that disables the commit-time hooks: $bypass_command"
done

# A dangerous word inside a commit message is not the operation it names.
# Both quote styles, because the rules key on the quote position.
for message_command in \
  'git commit -m "fix: clean up the parser"' \
  "git commit -m 'fix: clean up the parser'" \
  'git commit -m "chore: document reset --hard"' \
  'git commit -m "docs: explain branch -D"' \
  'git commit -m "fix: drop the stale worktree remove note"' \
  'git commit -m "docs: soften the rm -r wording"' \
  'git log --grep=clean' \
  'git add scripts/clean'; do
  run_guard "$(jq -cn --arg c "$message_command" \
    '{tool_name:"Bash", tool_input:{command:$c}}')"
  [ "$guard_exit" -eq 0 ] \
    || fail "guard mistook a commit message for the operation it names: $message_command -> $guard_output"
done
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":""}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":" \t\n"}}'

run_guard '{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: README.md\n@@\n-old\n+new\n*** End Patch"}}'
[ "$guard_exit" -eq 0 ] || fail "guard blocked an allowed apply_patch payload: $guard_output"
require_guard_blocked '{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Delete File: README.md\n*** End Patch"}}'
require_guard_blocked '{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: README.md\n*** End Patch"}}'
require_guard_blocked '{"tool_name":"Bash","tool_input":null}'
require_guard_blocked '{"tool_name":"Bash","tool_input":{"command":[]}}'
require_guard_blocked '{"tool_name":"apply_patch","tool_input":""}'
require_guard_blocked '{"tool_name":"apply_patch","tool_input":"*** Begin Patch\n*** Update File: README.md\n*** End Patch"}'
require_guard_blocked '{"tool_name":"apply_patch","tool_input":["*** Begin Patch\n*** Update File: README.md\n*** End Patch"]}'
require_guard_blocked '{"tool_name":"apply_patch","tool_input":{"other":"*** Begin Patch\n*** Update File: README.md\n*** End Patch"}}'
require_guard_blocked '{"tool_name":"apply_patch","tool_input":{"command":"JUNK\n*** Begin Patch\n*** Update File: README.md\n*** End Patch\nJUNK"}}'
require_guard_blocked '{"tool_name":"apply_patch","tool_input":{"command":"not a patch"}}'
require_guard_blocked '{"tool_name":"apply_patch","tool_input":{"command":"*** Update File: README.md"}}'

project_check=".agents/hooks/check-project-agent-integration.sh"
if [ -e "$project_check" ] || [ -L "$project_check" ]; then
  test -f "$project_check" && test ! -L "$project_check" \
    && test -x "$project_check" \
    || fail "project integration check must be a regular executable file"
  "$project_check" || fail "project integration check failed"
fi

# --- commit-time Git hooks ---------------------------------------------------
# The secret scan and the message checks live in Git hooks because a runtime
# tool hook cannot see a staged diff, and `git commit -F -` hides the message
# from it entirely. Static presence is not enough, so both are executed.
for githook in pre-commit commit-msg pre-push; do
  test -f ".agents/githooks/$githook" || fail "commit-time hook missing: $githook"
  test -x ".agents/githooks/$githook" || fail "commit-time hook is not executable: $githook"
done
# core.hooksPath is per-clone local config written by the installer, not
# repository content, so a fresh clone and every CI checkout legitimately lack
# it. Asserting it outright made this checker impossible to pass in CI, which
# is exactly where it most needs to run. Distinguish the two cases: an unset
# value is an unwired clone and is reported, while a value pointing somewhere
# else is a real misconfiguration that would silently run the wrong hooks.
hooks_path=$(git config --local core.hooksPath 2>/dev/null || true)
if [ -z "$hooks_path" ]; then
  echo "note: core.hooksPath is unset in this clone, so the commit-time hooks" >&2
  echo "      are present but inactive here. Run Friday's install.sh, or" >&2
  echo "      'git config core.hooksPath .agents/githooks', to wire them." >&2
elif [ "$hooks_path" != .agents/githooks ]; then
  fail "core.hooksPath is '$hooks_path', not .agents/githooks — the commit-time hooks in this repository would not run, and something else would"
fi

githook_lab=$(mktemp -d)
fixture_roots+=("$githook_lab")
git init -q "$githook_lab"
git -C "$githook_lab" config user.email agent@local
git -C "$githook_lab" config user.name agent

run_githook() {
  local hook=$1 expected=$2 expected_msg=$3 output exit_code
  shift 3
  set +e
  output=$(cd "$githook_lab" && "$repo_root/.agents/githooks/$hook" "$@" 2>&1)
  exit_code=$?
  set -e
  [ "$exit_code" -eq "$expected" ] \
    || fail "$hook returned $exit_code, expected $expected: $output"
  if [ -n "$expected_msg" ]; then
    case "$output" in
      *"$expected_msg"*) ;;
      *) fail "$hook exited $exit_code but not for the expected reason; wanted '$expected_msg', got: $output" ;;
    esac
  fi
  githook_output=$output
}

# Every rule in the hook's table must have a fixture here, and every fixture
# must be refused. The count is asserted too, so a new rule cannot ship without
# a probe. An earlier revision tested three hand-picked fixtures, and a stub
# implementing one rule out of eleven passed it -- the probes proved the
# fixtures, not the rules.
#
# All values are fabricated. Each line carries the per-line scanner exemption,
# because this file is itself scanned when it is committed.
rule_fixtures=(
  "private key block:-----BEGIN RSA PRIVATE KEY-----"                                   # secret-scan:allow
  "OpenSSH private key:-----BEGIN OPENSSH PRIVATE KEY-----"                             # secret-scan:allow
  "AWS access key id:aws_access_key_id = AKIAIOSFODNN7EXAMPLE"                          # secret-scan:allow
  "GitHub token:token: ghp_0123456789abcdefghijklmnopqrstuvwxyz"                        # secret-scan:allow
  "Slack token:SLACK=xoxb-123456789012-abcdefghijkl"                                    # secret-scan:allow
  "Google API key:key=AIzaSyA1234567890abcdefghijklmnopqrstuv"                          # secret-scan:allow
  "Stripe secret key:stripe = sk_live_0123456789abcdefghij"                             # secret-scan:allow
  "Anthropic API key:ANTHROPIC_API_KEY=sk-ant-api03-abcdefghij1234567890"               # secret-scan:allow
  "OpenAI API key:OPENAI_API_KEY=sk-proj-abcdefghij1234567890abcdefghij1234567890ab"   # secret-scan:allow
  "GitLab token:GITLAB_TOKEN=glpat-abcdefghij1234567890"                                # secret-scan:allow
  "Hugging Face token:HF_TOKEN=hf_abcdefghij1234567890abcdefghij1234"                   # secret-scan:allow
  "SendGrid key:SENDGRID=SG.abcdefghij1234567890.abcdefghij1234567890abcdefghij12345"   # secret-scan:allow
  "npm token:NPM_TOKEN=npm_abcdefghij1234567890abcdefghij123456"                        # secret-scan:allow
  "Square token:SQUARE=sq0atp-abcdefghij1234567890"                                     # secret-scan:allow
  "PyPI token:PYPI_TOKEN=pypi-AgEIcHlwaS5vcmcabcdefghij1234567890abcdefghij1234567890"  # secret-scan:allow
  "JSON Web Token:auth = eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVP" # secret-scan:allow
  "assigned secret literal:AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMIK7MDENGbPxRfi"            # secret-scan:allow
  "credentials in a URL:DATABASE_URL=postgres://admin:hunter2pass@db.internal/app"      # secret-scan:allow
)

rule_count=$(awk "/^RULES\$/{exit} f && NF; /<<'RULES'\$/{f=1}" \
  "$repo_root/.agents/githooks/pre-commit" | wc -l | tr -d ' ')
[ "$rule_count" -eq "${#rule_fixtures[@]}" ] \
  || fail "the scanner has $rule_count rules but ${#rule_fixtures[@]} fixtures; every rule needs one"

# Rotate the path and push the secret off the first line. Every probe used to
# stage a single-line *.txt file, so a hook scanning only .txt, or only the
# first added line of each file, passed the entire suite.
probe_paths=(rule-probe.py config/rule-probe.json deploy/rule-probe.yml Makefile-probe)
probe_index=0
for fixture in "${rule_fixtures[@]}"; do
  fixture_label=${fixture%%:*}
  fixture_value=${fixture#*:}
  probe_path=${probe_paths[probe_index % ${#probe_paths[@]}]}
  probe_index=$((probe_index + 1))
  mkdir -p "$githook_lab/$(dirname "$probe_path")"
  printf 'first line is ordinary\nsecond line is ordinary\n%s\n' "$fixture_value" \
    > "$githook_lab/$probe_path"
  git -C "$githook_lab" add "$probe_path"
  run_githook pre-commit 1 "look like they carry a secret"
  case "$githook_output" in
    *"$fixture_label"*) ;;
    *) fail "rule '$fixture_label' did not fire on its own fixture; got: $githook_output" ;;
  esac
  git -C "$githook_lab" rm -q --cached "$probe_path"
  rm -f "$githook_lab/$probe_path"
done

# A second, different value per pattern rule. The fixtures above prove a rule
# fires on one string; these prove it fires on the pattern. A stub that keeps
# the rule table verbatim but matches only the fixture strings passes the
# fixtures and the count assertion, and fails here. Rules that are a fixed
# string have no variant, since no probe can distinguish a literal matcher from
# the rule for those.
rule_variants=(
  "private key block:-----BEGIN EC PRIVATE KEY-----"                            # secret-scan:allow
  "AWS access key id:role_key = ASIAZZZZZZZZZZZZZZZZ"                           # secret-scan:allow
  "GitHub token:pat = github_pat_11ABCDEFG0abcdefghijklmnopqrstuvwxyz"          # secret-scan:allow
  "Slack token:hook = xoxp-9876543210-zyxwvutsrqpo"                             # secret-scan:allow
  "Google API key:maps = AIzaB9876543210zyxwvutsrqponmlkjihgfedc"                 # secret-scan:allow
  "Stripe secret key:billing = sk_test_zyxwvutsrqponmlkj"                       # secret-scan:allow
  "Anthropic API key:claude = sk-ant-api99-zzzzzzzzzzzzzzzzzzzz"                # secret-scan:allow
  "JSON Web Token:bearer = eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpZCI6OTk5OTk5fQ.QWxpY2VCb2JDYXJvbA" # secret-scan:allow
  "assigned secret literal:DB_PASSWORD=Zz9Yy8Xx7Ww6Vv5Uu4Tt3Ss2"                      # secret-scan:allow
  "credentials in a URL:store = mysql://svc:Zz9Yy8Xx@db.local/app"              # secret-scan:allow
)

for variant in "${rule_variants[@]}"; do
  variant_label=${variant%%:*}
  variant_value=${variant#*:}
  probe_path=${probe_paths[probe_index % ${#probe_paths[@]}]}
  probe_index=$((probe_index + 1))
  mkdir -p "$githook_lab/$(dirname "$probe_path")"
  printf 'first line is ordinary\nsecond line is ordinary\n%s\n' "$variant_value" \
    > "$githook_lab/$probe_path"
  git -C "$githook_lab" add "$probe_path"
  run_githook pre-commit 1 "look like they carry a secret"
  case "$githook_output" in
    *"$variant_label"*) ;;
    *) fail "rule '$variant_label' fires on its fixture but not on a second value matching the same pattern; the rule table may not be in use. Got: $githook_output" ;;
  esac
  git -C "$githook_lab" rm -q --cached "$probe_path"
  rm -f "$githook_lab/$probe_path"
done

# A deletion-only commit must pass. An earlier revision refused every one of
# them, including removing a secret the scan had just flagged.
printf 'keep\ndrop\n' > "$githook_lab/deletion.txt"
git -C "$githook_lab" add deletion.txt
git -C "$githook_lab" -c user.email=a@b -c user.name=a commit -q -m "chore: seed a line to delete"
printf 'keep\n' > "$githook_lab/deletion.txt"
git -C "$githook_lab" add deletion.txt
run_githook pre-commit 0 ""

# Evasions that previously defeated the scan entirely.
printf 'api_key = aB3dE5fG7hJ9kL1mN3pQ\n' > "$githook_lab/evade.txt"  # secret-scan:allow
printf '\377\376legacy latin1\n' > "$githook_lab/aa-legacy.txt"
git -C "$githook_lab" add evade.txt aa-legacy.txt
run_githook pre-commit 1 "look like they carry a secret"
git -C "$githook_lab" rm -q --cached evade.txt aa-legacy.txt
rm -f "$githook_lab/evade.txt" "$githook_lab/aa-legacy.txt"

printf 'x\n' > "$githook_lab/renamed.txt"
git -C "$githook_lab" add renamed.txt
git -C "$githook_lab" -c user.email=a@b -c user.name=a commit -q -m "chore: seed a file to rename"
git -C "$githook_lab" mv renamed.txt .env
run_githook pre-commit 1 "normally holds credentials"
git -C "$githook_lab" mv .env renamed.txt

# A fabricated credential in staged content must refuse the commit, and the
# refusal must not echo the value back.
# The fixture must look like the real thing for the scan to be meaningful, so
# the line carries the per-line exemption marker.
printf 'aws_access_key_id = AKIAIOSFODNN7EXAMPLE\n' > "$githook_lab/leaky.txt"  # secret-scan:allow
git -C "$githook_lab" add leaky.txt
run_githook pre-commit 1 "look like they carry a secret"
case "$githook_output" in
  *AKIAIOSFODNN7EXAMPLE*) fail "pre-commit echoed the matched secret back into its output" ;; # secret-scan:allow
esac
git -C "$githook_lab" rm -q --cached leaky.txt
rm -f "$githook_lab/leaky.txt"

# The hook file itself is the one narrow file-level exemption. A path that only
# starts with that name must remain ordinary staged content; parsing a diff
# header with `$2` used to collapse this name onto the exemption.
space_path='.agents/githooks/pre-commit notes'
mkdir -p "$githook_lab/$(dirname "$space_path")"
printf 'aws_access_key_id = AKIAIOSFODNN7EXAMPLE\n' > "$githook_lab/$space_path"  # secret-scan:allow
printf 'ordinary companion\n' > "$githook_lab/path-space-companion.txt"
git -C "$githook_lab" add -- "$space_path" path-space-companion.txt
run_githook pre-commit 1 "look like they carry a secret"
case "$githook_output" in
  *AKIAIOSFODNN7EXAMPLE*) fail "pre-commit echoed the path-space fixture" ;; # secret-scan:allow
esac
git -C "$githook_lab" rm -q --cached -- "$space_path" path-space-companion.txt
rm -f "$githook_lab/$space_path" "$githook_lab/path-space-companion.txt"

# Ordinary content must pass, or the hook is unusable rather than safe.
printf 'const timeout = 30\n' > "$githook_lab/ok.txt"
git -C "$githook_lab" add ok.txt
run_githook pre-commit 0 ""

# A newly added credential-shaped filename is refused on its name alone.
printf 'HOST=localhost\n' > "$githook_lab/.env"
git -C "$githook_lab" add -f .env
run_githook pre-commit 1 "normally holds credentials"
git -C "$githook_lab" rm -q --cached .env
rm -f "$githook_lab/.env"

# pre-push decides from the refs Git hands it, not from how the command was
# spelled, so --force, -f, a leading + on the refspec and --mirror are all one
# test. Feed it the stdin contract directly: <local ref> <local sha> <remote
# ref> <remote sha>.
run_prepush() {
  local line=$1 expected=$2 expected_msg=$3 output exit_code
  set +e
  output=$(cd "$githook_lab" && printf '%s\n' "$line" \
    | "$repo_root/.agents/githooks/pre-push" origin ../origin.git 2>&1)
  exit_code=$?
  set -e
  [ "$exit_code" -eq "$expected" ] \
    || fail "pre-push returned $exit_code, expected $expected for '$line': $output"
  if [ -n "$expected_msg" ]; then
    case "$output" in
      *"$expected_msg"*) ;;
      *) fail "pre-push exited $exit_code but not for the expected reason; wanted '$expected_msg', got: $output" ;;
    esac
  fi
}

prepush_zero=0000000000000000000000000000000000000000
prepush_head=$(git -C "$githook_lab" rev-parse HEAD)

# The remote HEAD is the only source for the semantic default-branch decision.
# Give the lab a non-main default explicitly; a feature push must still pass
# while a direct push to that default must not.
git -C "$githook_lab" update-ref refs/remotes/origin/master "$prepush_head"
git -C "$githook_lab" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master
# A real bare remote, not only remote-tracking refs. The hook now asks
# `git ls-remote` to tell an EMPTY remote from one whose HEAD will not resolve,
# and those two cases cannot be simulated with local refs alone.
prepush_remote="$githook_lab/../origin.git"
git init -q --bare "$prepush_remote"
git -C "$githook_lab" remote add origin "$prepush_remote" 2>/dev/null || true
git -C "$githook_lab" push -q --no-verify origin "HEAD:refs/heads/master" 2>/dev/null || true

# Two divergent commits, so the non-fast-forward rule can actually be reached.
# Without them every probe carried an all-zero remote sha and that rule -- the
# one the hook exists for -- was never executed by the suite.
git -C "$githook_lab" checkout -q -b prepush-alt
printf 'diverge\n' > "$githook_lab/diverge.txt"
git -C "$githook_lab" add diverge.txt
git -C "$githook_lab" -c user.email=a@b -c user.name=a commit -q -m "chore: diverge for the push probe"
prepush_alt=$(git -C "$githook_lab" rev-parse HEAD)
git -C "$githook_lab" checkout -q -
printf 'ahead\n' > "$githook_lab/ahead.txt"
git -C "$githook_lab" add ahead.txt
git -C "$githook_lab" -c user.email=a@b -c user.name=a commit -q -m "chore: advance for the push probe"
prepush_ahead=$(git -C "$githook_lab" rev-parse HEAD)
# A deletion always arrives with an all-zero local sha, whatever the spelling.
run_prepush "refs/heads/feat/x $prepush_zero refs/heads/feat/x $prepush_head" 1 "would delete"
# A brand-new feature branch is ordinary work.
run_prepush "refs/heads/feat/x $prepush_head refs/heads/feat/x $prepush_zero" 0 ""
# The resolved non-main default is reserved for a person.
run_prepush "refs/heads/master $prepush_head refs/heads/master $prepush_zero" 1 "default"
# Three situations that look identical from inside the hook and are not. The
# previous revision had ONE probe here, expecting "could not resolve the
# default branch" against a remote that did not exist -- so it was really
# testing the unreachable case while claiming to test the dangling one.
#
# a. The remote HAS refs and its HEAD will not resolve. There is a default
#    branch; the hook cannot see which. It must refuse.
git -C "$githook_lab" symbolic-ref -d refs/remotes/origin/HEAD
run_prepush "refs/heads/feat/x $prepush_head refs/heads/feat/x $prepush_zero" 1 "could not resolve the default branch"

# b. The remote has NO refs at all -- the first push to a repository that was
#    just created. Nothing this hook forbids can apply, and refusing made
#    creating a repository impossible without bypassing the hook.
prepush_empty="$githook_lab/../origin-empty.git"
git init -q --bare "$prepush_empty"
set +e
prepush_boot=$(cd "$githook_lab" \
  && printf 'refs/heads/main %s refs/heads/main %s\n' "$prepush_head" "$prepush_zero" \
  | "$repo_root/.agents/githooks/pre-push" empty-origin "$prepush_empty" 2>&1)
prepush_boot_code=$?
set -e
[ "$prepush_boot_code" -eq 0 ] \
  || fail "pre-push refused the first push to an EMPTY remote ($prepush_boot_code): $prepush_boot"

# c. The remote cannot be reached at all. The hook cannot tell (a) from (b),
#    so it fails closed.
set +e
prepush_unreach=$(cd "$githook_lab" \
  && printf 'refs/heads/feat/x %s refs/heads/feat/x %s\n' "$prepush_head" "$prepush_zero" \
  | "$repo_root/.agents/githooks/pre-push" gone-origin "$githook_lab/../no-such-remote.git" 2>&1)
prepush_unreach_code=$?
set -e
[ "$prepush_unreach_code" -eq 1 ] \
  || fail "pre-push did not refuse an unreachable remote ($prepush_unreach_code): $prepush_unreach"
case "$prepush_unreach" in
  *"could not reach"*) ;;
  *) fail "pre-push refused an unreachable remote for the wrong reason: $prepush_unreach" ;;
esac

git -C "$githook_lab" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master

# Rewriting history: the remote commit is not an ancestor of the local one.
# This is what --force, -f, +refspec and --mirror all reduce to, so it is the
# rule that most needs a probe.
# alt and ahead are siblings of the same parent, so neither is an ancestor of
# the other. Using alt against its own parent would have been a fast-forward.
run_prepush "refs/heads/feat/x $prepush_alt refs/heads/feat/x $prepush_ahead" 1 "rewrite history"
# A genuine fast-forward on the same branch must still pass, or the hook is
# unusable rather than safe.
run_prepush "refs/heads/feat/x $prepush_ahead refs/heads/feat/x $prepush_head" 0 ""
# A mirror-shaped push sends several refs at once; a benign first line must not
# let a later bad one through.
run_prepush "refs/heads/feat/a $prepush_ahead refs/heads/feat/a $prepush_zero
refs/heads/feat/b $prepush_alt refs/heads/feat/b $prepush_ahead" 1 "rewrite history"

# Message rules. A vague summary is the proxy for a commit covering more than
# one task; a specific one that merely contains such a word must pass.
printf 'chore: misc updates\n' > "$githook_lab/msg"
run_githook commit-msg 1 "too vague to trace to one task" msg
printf 'Fixed stuff.\n' > "$githook_lab/msg"
run_githook commit-msg 1 "not Conventional Commits" msg
printf 'fix: repair the parser and also update the docs\n' > "$githook_lab/msg"
run_githook commit-msg 1 "joins separate changes" msg
printf 'docs: clarify the retry wording in the spec\n' > "$githook_lab/msg"
run_githook commit-msg 0 "" msg
printf 'fix(agents): sync shared guard fixes\n' > "$githook_lab/msg"
run_githook commit-msg 0 "" msg
printf 'Merge pull request #1 from x/y\n' > "$githook_lab/msg"
run_githook commit-msg 0 "" msg
# Case is style, not traceability: none of these may be refused. The old rule
# (`^[a-z]`) refused all three -- a capitalised word, a proper noun, and any
# summary not in English. A capital alongside a real violation is refused for
# that violation alone; an earlier revision printed "the commit goes ahead"
# just before the imperative rule refused it.
printf 'feat: Add the parity check\n' > "$githook_lab/msg"
run_githook commit-msg 0 "" msg
printf 'docs: GitHub ruleset is active\n' > "$githook_lab/msg"
run_githook commit-msg 0 "" msg
printf 'docs: 補上中文摘要\n' > "$githook_lab/msg"
run_githook commit-msg 0 "" msg
printf 'feat: Added validation\n' > "$githook_lab/msg"
run_githook commit-msg 1 "use the imperative" msg
# run_githook checks the exit code and, when given, a substring of the output.
# These check that an accepted summary prints nothing at all, that a refusal
# prints nothing before its own reason, and that the length cap counts
# characters under a C locale. Under one, ${#subject} counts bytes, and a
# 37-character Chinese subject was refused as 99 characters.
# A command substitution strips trailing newlines, so output that is only blank
# lines would read as empty. Each capture ends in a sentinel "x", which keeps
# them, and the hook's exit status is passed through; callers strip the "x".
commit_msg_output() { (cd "$githook_lab" && env "$@" "$repo_root/.agents/githooks/commit-msg" msg 2>&1; rc=$?; printf x; exit "$rc"); }
for accepted in 'feat: Add the parity check' 'docs: GitHub ruleset is active' 'docs: 補上中文摘要'; do
  printf '%s\n' "$accepted" > "$githook_lab/msg"
  quiet_output=$(commit_msg_output) || fail "commit-msg refused an accepted summary: $accepted"
  quiet_output=${quiet_output%x}
  [ -z "$quiet_output" ] || fail "commit-msg printed output for an accepted summary ($accepted): $quiet_output"
done
printf 'feat: Added validation\n' > "$githook_lab/msg"
if quiet_output=$(commit_msg_output); then fail "commit-msg accepted a non-imperative summary"; fi
case "$quiet_output" in
  "COMMIT REFUSED: use the imperative"*) ;;
  *) fail "commit-msg printed something before its refusal: $quiet_output" ;;
esac
printf 'docs: 補上雙語文件的中文摘要並修正語系規則的說明以及相關的連結與範例\n' > "$githook_lab/msg"
quiet_output=$(commit_msg_output LC_ALL=C LANG=C) \
  || fail "commit-msg counted bytes, not characters, under a C locale: $quiet_output"
# The other side of the cap, or a hook with no length check at all would pass
# the line above: 73 characters must still be refused, by the length rule.
printf 'docs: 補上雙語文件的中文摘要並修正語系規則的說明以及相關的連結與範例再加上更多的文字讓它真的超過七十二個字元的上限才對所以繼續寫下去直到夠長\n' > "$githook_lab/msg"
if quiet_output=$(commit_msg_output LC_ALL=C LANG=C); then
  fail "commit-msg accepted a 73-character subject under a C locale"
fi
case "$quiet_output" in
  *"the subject is 73 characters"*) ;;
  *) fail "commit-msg refused a 73-character subject, but not for its length: $quiet_output" ;;
esac

echo "Agent workflow guardrails passed."
