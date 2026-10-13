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

# Codex's active hook configuration is user-scoped in the current runtime;
# this repository can verify the shared guard, but cannot enforce that wiring.
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

for path in \
  AGENTS.md \
  .agents/AGENTS.md \
  .agents/docs/scratch-files.md \
  .agents/docs/git-guideline/git-commit.md \
  .agents/docs/git-guideline/pr-evidence.md \
  .agents/docs/git-guideline/safety-boundary.md; do
  test -f "$path" || fail "canonical document missing: $path"
done

# grep, not rg: rg is not installed everywhere, and on at least one machine it
# exists only as an interactive shell function — so a script calling it fails
# with "command not found". That matters here because the stale-reference check
# below treats "found nothing" as success: a search tool that cannot run is
# indistinguishable from a clean repository, and the check passes vacuously.
# This is exactly how the check silently did nothing before.
search_repo() {
  # BSD grep stops parsing options at the first non-option argument, so every
  # --exclude must precede the pattern and the path, and the pattern goes
  # behind -e so a leading dash could never be read as an option.
  grep -r --fixed-strings --quiet \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=backup \
    --exclude=check-collaborative-git.sh \
    -e "$1" .
}

# Prove the search works before trusting any negative result from it. The guard
# script certainly contains its own shebang, so a search for that must succeed;
# if it does not, grep is broken or the working directory is wrong, and every
# "clean" result below would be a lie.
search_repo '#!/usr/bin/env bash' \
  || fail "repository search is not working — its negative results cannot be trusted"

for legacy_path in \
  .agents/docs/git-commit.md \
  .agents/docs/issue-tracker.md \
  .agents/docs/pr-evidence.md \
  .agents/docs/safety-boundary.md; do
  if search_repo "$legacy_path"; then
    fail "stale reference to $legacy_path"
  fi
done

printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
  | "$guard" >/dev/null

if printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' \
  | "$guard" >/dev/null 2>&1; then
  fail "force push payload was not blocked"
fi

project_check=".agents/hooks/check-project-agent-integration.sh"
if [ -e "$project_check" ] || [ -L "$project_check" ]; then
  test -f "$project_check" && test ! -L "$project_check" \
    && test -x "$project_check" \
    || fail "project integration check must be a regular executable file"
  "$project_check" || fail "project integration check failed"
fi

echo "Agent workflow guardrails passed."
