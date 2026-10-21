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
jq -e '
  any(.hooks.PreToolUse[];
    .matcher == "Bash" and any(.hooks[];
      .type == "command" and
      .command == "bash .claude/hooks/guard-collaborative-git.sh"
    )
  )
' .claude/settings.json >/dev/null || fail "Claude PreToolUse guard is not wired"

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
