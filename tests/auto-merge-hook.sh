#!/usr/bin/env bash
# The shipped Bash guard allows `gh pr merge <n> --auto --squash -R owner/repo`
# as the whole command, and only when .agents/bin/check-auto-merge passes for
# that pull request; any other form with --auto stays blocked. The guard is
# copied beside a stub check script, so no network is involved. It is also run
# through a symlink, the way the Claude Code launcher reaches it.
# CI passes an output directory as $1, which this test does not use.
set -euo pipefail
root=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/.agents/hooks" "$work/.agents/bin" "$work/.claude/hooks"
cp "$root/payload/.agents/hooks/guard-collaborative-git.sh" "$work/.agents/hooks/"
ln -s ../../.agents/hooks/guard-collaborative-git.sh "$work/.claude/hooks/guard-collaborative-git.sh"
stub=$work/.agents/bin/check-auto-merge
failures=0

stub_check() { # <exit status> <reason>
  printf '#!/bin/bash\necho "$*" > "%s/args"\necho "%s" >&2\nexit %s\n' "$work" "$2" "$1" > "$stub"
  chmod +x "$stub"
  rm -f "$work/args"
}
guard() { # <command> [guard path]; sets out and code
  local g=${2:-$work/.agents/hooks/guard-collaborative-git.sh}
  set +e
  out=$(jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}' | "$g" 2>&1)
  code=$?
  set -e
}
expect() { # <name> <exit> <output substring> <command> [guard path]
  guard "$4" "${5:-}"
  if [ "$code" -ne "$2" ] || [[ $out != *"$3"* ]]; then
    echo "FAIL: $1 (exit $code, wanted $2 and '$3'): $out"
    failures=$((failures + 1))
  else
    echo "ok: $1"
  fi
}
armed='gh pr merge 12 --auto --squash -R o/r'

stub_check 0 'check-auto-merge: ok'
expect "armed form with a passing check is allowed" 0 "" "$armed"
[ "$(cat "$work/args")" = "12 -R o/r" ] \
  || { echo "FAIL: the check got '$(cat "$work/args")', wanted '12 -R o/r'"; failures=$((failures + 1)); }
expect "armed form through the launcher symlink is allowed" 0 "" "$armed" "$work/.claude/hooks/guard-collaborative-git.sh"
stub_check 1 'check-auto-merge: not armed (rules: cannot read repos/o/r/rules/branches/main: HTTP 403)'
expect "armed form with a failing check is blocked, with the reason" 2 "rules: cannot read repos/o/r/rules/branches/main: HTTP 403" "$armed"
expect "the same through the launcher symlink" 2 "HTTP 403" "$armed" "$work/.claude/hooks/guard-collaborative-git.sh"

stub_check 0 'check-auto-merge: ok'
for bad in \
  'gh pr merge 12 --auto --squash' \
  'gh pr merge 12 --auto --squash -R o/r --admin' \
  'gh pr merge 12 --auto --merge -R o/r' \
  'gh pr merge 12 --squash --auto -R o/r' \
  'gh pr merge 12 --auto -R o/r' \
  'gh pr merge --auto --squash -R o/r' \
  'gh pr merge 12 --auto --squash -R "o/r"' \
  "gh pr merge 12 --auto --squash -R 'o/r'" \
  'gh pr merge $(echo 12) --auto --squash -R o/r' \
  'gh pr merge 12 --auto --squash -R $(echo o/r)' \
  'gh pr merge 12 --auto --squash -R `echo o/r`' \
  'gh pr merge 12 --auto --squash -R o/r && echo done' \
  'gh pr merge 12 --auto --squash -R o/r; echo done' \
  'gh pr merge 12 --auto --squash -R o/r | cat' \
  'echo x && gh pr merge 12 --auto --squash -R o/r' \
  'gh  pr merge 12 --auto --squash -R o/r' \
  'gh pr merge 12 --auto --squash -R o/r --match-head-commit abc' \
  'gh pr merge 12 --auto --squash -R ../..' \
  'gh pr merge 12 --auto --squash -R ./r' \
  'gh pr merge 12 --merge' \
  'gh pr merge 12' \
  "gh api graphql -f query='mutation{enablePullRequestAutoMerge(input:{pullRequestId:\"X\",mergeMethod:SQUASH}){clientMutationId}}'" \
  "gh api graphql -f query='mutation{mergePullRequest(input:{pullRequestId:\"X\"}){clientMutationId}}'" \
  'gh api -X PUT repos/o/r/pulls/12/merge' \
  'gh api repos/o/r/pulls/12/merge --method PUT' \
  'gh api repos/o/r/pulls/12/merge' \
  '\gh pr merge 12 --auto --squash' \
  '\gh pr merge 12 --auto --squash -R o/r' \
  '/opt/homebrew/bin/gh pr merge 12 --auto --squash' \
  '/opt/homebrew/bin/gh pr merge 12 --auto --squash -R o/r' \
  '"gh" pr merge 12 --auto' \
  "'gh' pr merge 12 --auto --squash -R o/r" \
  '"/opt/homebrew/bin/gh" pr merge 12 --auto --squash -R o/r' \
  '\gh api -X PUT repos/o/r/pulls/12/merge'; do
  expect "blocked even with a passing check: $bad" 2 "BLOCKED" "$bad"
done
[ ! -e "$work/args" ] \
  || { echo "FAIL: the check ran for a form that is not the plain armed form"; failures=$((failures + 1)); }
expect "gh pr merge without --auto is unchanged" 2 "permanently agent-prohibited" 'gh pr merge 12'

for allowed in \
  'gh pr merge 12 --disable-auto' \
  'gh pr merge 12 --disable-auto -R o/r'; do
  expect "--disable-auto is allowed: $allowed" 0 "" "$allowed"
done
expect "--disable-auto with a chained command is blocked" 2 "BLOCKED" 'gh pr merge 12 --disable-auto && gh pr merge 12 --auto'

# Ordinary reads and non-merge gh calls stay allowed (the merge rules must not
# make the guard unusable).
for allowed in \
  'gh api repos/o/r/pulls/12' \
  'gh api repos/o/r/pulls/12/comments' \
  'gh api repos/o/r/pulls/12/merge-readiness' \
  'gh pr view 12' \
  'gh pr view 12 -R o/r --json state'; do
  expect "ordinary read is allowed: $allowed" 0 "" "$allowed"
done

rm -f "$stub"
expect "a missing check script blocks the armed form" 2 "check-auto-merge is missing" "$armed"

if [ "$failures" -ne 0 ]; then echo "FAILED: $failures case(s)"; exit 1; fi
echo "all auto-merge hook cases passed"
