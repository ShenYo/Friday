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

test -L .claude/hooks/guard-collaborative-git.sh || fail "Claude guard link missing"
test -f .claude/settings.json || fail "Claude settings missing"
jq -e '
  any(.hooks.PreToolUse[];
    .matcher == "Bash" and any(.hooks[];
      .type == "command" and
      (.command | contains(".claude/hooks/guard-collaborative-git.sh"))
    )
  )
' .claude/settings.json >/dev/null || fail "Claude PreToolUse guard is not wired"

codex_hook=.codex/hooks/guard-collaborative-git.sh
test -L "$codex_hook" || fail "Codex guard link missing"
[ "$(readlink "$codex_hook")" = ../../.agents/hooks/guard-collaborative-git.sh ] \
  || fail "Codex guard link target is wrong"
test -f .codex/hooks.json || fail "Codex hooks configuration missing"
jq -e '
  def generic:
    type == "object" and
    .type == "command" and
    .command == "\"$(git rev-parse --show-toplevel)/.codex/hooks/guard-collaborative-git.sh\"" and
    .timeout == 30 and
    .statusMessage == "Checking collaborative Git safety boundary";
  type == "object" and
  (.hooks | type == "object") and
  (.hooks.PreToolUse | type == "array") and
  ([.hooks.PreToolUse[] | select(type == "object" and .matcher == "^(Bash|apply_patch)$")] | length == 1) and
  (.hooks.PreToolUse[] | select(type == "object" and .matcher == "^(Bash|apply_patch)$") | (.hooks | type == "array")) and
  ([.hooks.PreToolUse[] | select(type == "object" and .matcher == "^(Bash|apply_patch)$") | .hooks[] | select(generic)] | length == 1) and
  ([.hooks.PreToolUse[] | select(type == "object" and (.hooks | type == "array")) | .hooks[] | select(generic)] | length == 1)
' .codex/hooks.json >/dev/null || fail "Codex PreToolUse guard is not wired"
if [ -f .codex/config.toml ] \
  && grep -Eq '^[[:space:]]*\[\[hooks\.' .codex/config.toml; then
  fail "Codex config contains inline hooks"
fi

for path in \
  AGENTS.md \
  .agents/AGENTS.md \
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

for legacy_path in \
  .agents/docs/git-commit.md \
  .agents/docs/issue-tracker.md \
  .agents/docs/pr-evidence.md \
  .agents/docs/safety-boundary.md; do
  if search_active_instructions "$legacy_path"; then
    fail "stale reference to $legacy_path"
  fi
done

printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
  | "$guard" >/dev/null

if printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' \
  | "$guard" >/dev/null 2>&1; then
  fail "force push payload was not blocked"
fi

printf '%s' '{"tool_name":"apply_patch","tool_input":{"command":"*** Update File: README.md"}}' \
  | "$guard" >/dev/null

if printf '%s' '{"tool_name":"apply_patch","tool_input":{"command":"*** Delete File: README.md"}}' \
  | "$guard" >/dev/null 2>&1; then
  fail "apply_patch deletion payload was not blocked"
fi

project_check=".agents/hooks/check-project-agent-integration.sh"
if [ -e "$project_check" ] || [ -L "$project_check" ]; then
  test -f "$project_check" && test ! -L "$project_check" \
    && test -x "$project_check" \
    || fail "project integration check must be a regular executable file"
  "$project_check" || fail "project integration check failed"
fi

echo "Agent workflow guardrails passed."
