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

missing_path_launcher=$(printf '%s' "$collaborative_launcher" \
  | sed 's@/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin@/definitely-missing@g')
run_codex_command "$missing_path_launcher" "$harmless_bash" 2 /bin "$repo_root"
case "$codex_command_output" in
  *'BLOCKED: required executable unavailable: git'*) ;;
  *) fail "missing Git dependency did not produce a concise BLOCKED message: $codex_command_output" ;;
esac

missing_bash_launcher=$(printf '%s' "$collaborative_launcher" \
  | sed 's@PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"@PATH="/usr/bin"@')
run_codex_command "$missing_bash_launcher" "$harmless_bash" 2 /bin "$repo_root"
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
  | sed 's@/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin@/definitely-missing@g')
run_claude_command "$harmless_bash" 2 "BLOCKED: required" /bin "$repo_root"
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
claude_decoy_cleanup() {
  rm -f "$claude_decoy_root/.claude/hooks/guard-collaborative-git.sh" 2>/dev/null || true
  rmdir "$claude_decoy_root/.claude/hooks" "$claude_decoy_root/.claude" \
    "$claude_decoy_root" 2>/dev/null || true
}
# Without this, any fail() before the cleanup tail leaks an executable no-op
# named exactly like a real guard into the temporary directory, once per run.
trap claude_decoy_cleanup EXIT
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
rm -f "$claude_decoy_root/.claude/hooks/guard-collaborative-git.sh"
rmdir "$claude_decoy_root/.claude/hooks" "$claude_decoy_root/.claude" "$claude_decoy_root"

set +e
missing_jq_output=$(sed 's@/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin@/definitely-missing@g' "$guard" \
  | env PATH=/bin /bin/bash 2>&1)
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
run_guard '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
[ "$guard_exit" -eq 0 ] || fail "guard blocked an allowed normal push: $guard_output"
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

# A dangerous word inside a commit message is not the operation it names.
# Both quote styles, because the rules key on the quote position.
for message_command in \
  'git commit -m "fix: clean up the parser"' \
  "git commit -m 'fix: clean up the parser'" \
  'git commit -m "chore: document reset --hard"' \
  'git commit -m "docs: explain branch -D"' \
  'git commit -m "fix: drop the stale worktree remove note"'; do
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

echo "Agent workflow guardrails passed."
