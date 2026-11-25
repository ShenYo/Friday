#!/usr/bin/env bash
# .agents/bin/check-auto-merge, with `gh` stubbed: it passes only when every
# condition holds, and each failing condition exits non-zero with its named
# reason. A 403 from the rules API is a failure, never a pass.
#
# With no argument, or an output directory as $1 (CI passes one), it runs the
# cases against the script, then against one mutant per condition, each of
# which skips that condition, and requires the case that names the condition
# to fail. CHECK_AUTO_MERGE_UNDER_TEST=<file> runs the cases against that file
# alone (how a mutant is run).
set -euo pipefail
root=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)
real=$root/payload/.agents/bin/check-auto-merge
script_under_test=${CHECK_AUTO_MERGE_UNDER_TEST:-$real}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The tree the script expects: .agents/bin/check-auto-merge, a stub gh, and a
# PATH that holds no gh at all. The opt-out file is not in the tree: the script
# reads it from the base branch through the contents API (a stub file here).
tree=$work/tree
mkdir -p "$tree/.agents/bin" "$work/stubbin" "$work/limited"
cp "$script_under_test" "$tree/.agents/bin/check-auto-merge"
chmod +x "$tree/.agents/bin/check-auto-merge"
cat > "$work/stubbin/gh" <<'STUB'
#!/bin/bash
# gh api <endpoint> [-H ...]: answer from $SCEN/<endpoint, with / and ? as _>.
[ "$1" = api ] || { echo "stub gh: only api" >&2; exit 2; }
f=$SCEN/$(printf '%s' "$2" | tr '/?' '__')
if [ -e "$f.fail" ]; then cat "$f.fail" >&2; exit 1; fi
if [ -e "$f" ]; then cat "$f"; exit 0; fi
echo "gh: Not Found (HTTP 404)" >&2; exit 1
STUB
chmod +x "$work/stubbin/gh"
for t in bash tr sed grep tail cut dirname jq cat; do
  ln -s "$(command -v $t)" "$work/limited/$t"
done

SCEN=$work/scen
export SCEN
# Endpoint file names, for the base branch of the scenario (main unless the
# scenario says otherwise; $enc is the base as the script must encode it).
names() { # <base> <encoded base>
  co=repos_o_r_contents_.github_CODEOWNERS_ref=$2
  rules=repos_o_r_rules_branches_$2_per_page=100
  optout=repos_o_r_contents_.agents_auto-merge_ref=$2
}
scenario() { # [base [encoded base]]
  local b=${1:-main} e=${2:-${1:-main}}
  names "$b" "$e"
  rm -rf "$SCEN"; mkdir -p "$SCEN"
  jq -cn --arg b "$b" '{state:"open",base:{ref:$b}}' > "$SCEN/repos_o_r_pulls_7"
  echo '{"allow_auto_merge":true,"owner":{"type":"User"}}' > "$SCEN/repos_o_r"
  echo '[{"type":"deletion","ruleset_id":42},{"type":"pull_request","ruleset_id":42,"parameters":{"required_approving_review_count":1,"require_code_owner_review":true,"dismiss_stale_reviews_on_push":true,"require_last_push_approval":true}}]' > "$SCEN/$rules"
  echo '{"enforcement":"active","current_user_can_bypass":"never"}' > "$SCEN/repos_o_r_rulesets_42"
  printf '# owners\n\n* @o  # the owner\n' > "$SCEN/$co"
  echo '{"login":"agent"}' > "$SCEN/user"
  echo '{"role_name":"write"}' > "$SCEN/repos_o_r_collaborators_agent_permission"
}
failures=0
out=
code=0
run() { # [VAR=value ...]
  set +e
  out=$(env -u GH_TOKEN -u GITHUB_TOKEN "$@" PATH="${PATH_OVERRIDE:-$work/stubbin:$PATH}" "$tree/.agents/bin/check-auto-merge" 7 -R o/r 2>&1)
  code=$?
  set -e
}
# expect_fail <case> <reason substring> [VAR=value ...]: exit 1 and the reason.
expect_fail() {
  local name=$1 reason=$2
  shift 2
  run "$@"
  if [ "$code" -ne 1 ] || [[ $out != *"$reason"* ]]; then
    echo "FAIL: $name (exit $code, wanted 1 and '$reason'): $out"
    failures=$((failures + 1))
  else
    echo "ok: $name"
  fi
}
expect_pass() {
  local name=$1
  shift
  run "$@"
  if [ "$code" -ne 0 ]; then
    echo "FAIL: $name (exit $code): $out"
    failures=$((failures + 1))
  else
    echo "ok: $name"
  fi
}
set_rules() { # <jq filter over the rules array>
  jq -c "$1" "$SCEN/$rules" > "$SCEN/$rules.new" && mv "$SCEN/$rules.new" "$SCEN/$rules"
}

scenario; expect_pass "every condition holds"
scenario; echo on > "$SCEN/$optout"; expect_pass "opt-out file says on"
scenario; echo off > "$SCEN/$optout"; expect_fail "opt-out off" "opt-out: .agents/auto-merge on main says off"
scenario; echo maybe > "$SCEN/$optout"; expect_fail "opt-out unknown value" "opt-out: .agents/auto-merge on main must say on or off"
scenario; echo "gh: Server Error (HTTP 500)" > "$SCEN/$optout.fail"; expect_fail "opt-out unreadable" "opt-out: cannot read .agents/auto-merge on main"
scenario; expect_fail "GH_TOKEN set" "token: GH_TOKEN is set" GH_TOKEN=value-one-0001
case $out in *value-one-0001*) echo "FAIL: a token value was printed"; failures=$((failures + 1)) ;; esac
scenario; expect_fail "GITHUB_TOKEN set" "token: GITHUB_TOKEN is set" GITHUB_TOKEN=value-two-0002
case $out in *value-two-0002*) echo "FAIL: a token value was printed"; failures=$((failures + 1)) ;; esac
scenario; echo '{"allow_auto_merge":true,"owner":{"type":"Organization"}}' > "$SCEN/repos_o_r"; expect_fail "repo owned by an organization" "owner: o/r is not owned by a user"
scenario; echo '{"allow_auto_merge":false,"owner":{"type":"User"}}' > "$SCEN/repos_o_r"; expect_fail "repo disallows auto-merge" "does not allow auto-merge"
scenario; echo '{"state":"closed","base":{"ref":"main"}}' > "$SCEN/repos_o_r_pulls_7"; expect_fail "pull request not open" "is not open"
scenario; printf 'gh: Upgrade to GitHub Pro or make this repository public (HTTP 403)\n' > "$SCEN/$rules.fail"; rm "$SCEN/$rules"
expect_fail "403 from the rules API" "rules: cannot read repos/o/r/rules/branches/main?per_page=100"
case $out in *403*) ;; *) echo "FAIL: the 403 is not in the reason: $out"; failures=$((failures + 1)) ;; esac
scenario; echo '[{"type":"deletion","ruleset_id":42}]' > "$SCEN/$rules"; expect_fail "no pull_request rule" "needs exactly one pull_request rule"
scenario; set_rules '. + [.[1]]'; expect_fail "two pull_request rules" "needs exactly one pull_request rule"
scenario; set_rules '(.[1].parameters.required_approving_review_count) = 0'; expect_fail "zero approvals" "required_approving_review_count is below 1"
for k in require_code_owner_review dismiss_stale_reviews_on_push require_last_push_approval; do
  scenario; set_rules "(.[1].parameters.$k) = false"; expect_fail "$k false" "rules: $k is not true"
done
scenario; echo '{"enforcement":"evaluate","current_user_can_bypass":"never"}' > "$SCEN/repos_o_r_rulesets_42"; expect_fail "ruleset not active" "ruleset: ruleset 42 is not active"
scenario; echo '{"enforcement":"active","current_user_can_bypass":"always"}' > "$SCEN/repos_o_r_rulesets_42"; expect_fail "agent can bypass" "current_user_can_bypass is not never"
scenario; echo "gh: Forbidden (HTTP 403)" > "$SCEN/repos_o_r_rulesets_42.fail"; rm "$SCEN/repos_o_r_rulesets_42"; expect_fail "ruleset unreadable" "ruleset: cannot read"
scenario; printf '* @o\n/docs @someone\n' > "$SCEN/$co"; expect_fail "CODEOWNERS has a second rule" "codeowners: .github/CODEOWNERS on main must be a single"
scenario; printf '* @o @other\n' > "$SCEN/$co"; expect_fail "CODEOWNERS names two owners" "codeowners:"
scenario; printf '* @someone-else\n' > "$SCEN/$co"; expect_fail "CODEOWNERS names another owner" "codeowners:"
scenario; printf '* @O\n' > "$SCEN/$co"; expect_pass "CODEOWNERS owner differs only in case"
scenario; printf '# nothing\n' > "$SCEN/$co"; expect_fail "CODEOWNERS has no rule" "codeowners:"
scenario; rm "$SCEN/$co"; expect_fail "CODEOWNERS missing" "codeowners: cannot read"
# The base branch is the pull request's, and is encoded in every URL.
scenario develop; expect_pass "base develop, only develop has rules"
scenario develop; echo off > "$SCEN/$optout"; expect_fail "base develop opt-out off" "opt-out: .agents/auto-merge on develop says off"
# main strict, develop has none: must fail.
strict=$(printf '%s' '[{"type":"pull_request","ruleset_id":42,"parameters":{"required_approving_review_count":1,"require_code_owner_review":true,"dismiss_stale_reviews_on_push":true,"require_last_push_approval":true}}]')
scenario develop; echo '[]' > "$SCEN/repos_o_r_rules_branches_develop_per_page=100"; echo "$strict" > "$SCEN/repos_o_r_rules_branches_main_per_page=100"
expect_fail "base develop has no rules while main is strict" "needs exactly one pull_request rule"
scenario 'main#x' 'main%23x'; expect_pass "base with a # is read as that branch"
scenario 'main#x' 'main%23x'; echo "$strict" > "$SCEN/repos_o_r_rules_branches_main_per_page=100"; echo '[]' > "$SCEN/$rules"
expect_fail "base main#x has no rules while main is strict" "needs exactly one pull_request rule"
scenario; echo '{"role_name":"admin"}' > "$SCEN/repos_o_r_collaborators_agent_permission"; expect_fail "acting login is admin" "role: the acting login's role_name on o/r is not write"
scenario; echo '{"role_name":"maintain"}' > "$SCEN/repos_o_r_collaborators_agent_permission"; expect_fail "acting login is maintain" "role: the acting login"
scenario; rm "$SCEN/user"; expect_fail "acting login unreadable" "role: cannot read user"
scenario; PATH_OVERRIDE=$work/limited; expect_fail "gh missing" "tool: gh is not installed"; unset PATH_OVERRIDE
scenario; set +e; "$tree/.agents/bin/check-auto-merge" seven -R o/r >/dev/null 2>&1; bad=$?; set -e
if [ "$bad" -eq 2 ]; then echo "ok: bad invocation exits 2"; else echo "FAIL: bad invocation exit $bad"; failures=$((failures + 1)); fi

if [ "$failures" -ne 0 ]; then echo "FAILED: $failures case(s) against $script_under_test"; exit 1; fi
if [ -n "${CHECK_AUTO_MERGE_UNDER_TEST:-}" ]; then echo "all cases passed against $script_under_test"; exit 0; fi

# One mutant per condition: the script with that condition skipped. Each must
# fail the suite, and the case that names the condition must be among the
# failures.
mutate() { # <name> <case that must fail> <old text, once in the script> <new>
  local name=$1 case_name=$2 old=$3 new=$4 m=$work/mutant-$1 res
  python3 -I - "$real" "$m" "$old" "$new" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.exit("mutant text not found exactly once: " + old)
open(dst, "w").write(s.replace(old, new))
PY
  chmod +x "$m"
  if res=$(CHECK_AUTO_MERGE_UNDER_TEST=$m bash "$0" 2>&1); then
    echo "FAIL: mutant '$name' was not caught"; exit 1
  fi
  case $res in
    *"FAIL: $case_name ("*) echo "ok: mutant '$name' fails the case '$case_name'" ;;
    *) echo "FAIL: mutant '$name' failed, but not the case '$case_name':"; printf '%s\n' "$res" | grep '^FAIL'; exit 1 ;;
  esac
}
mutate optout-off "opt-out off" 'off) fail "opt-out: .agents/auto-merge on $base says off" ;;' 'off) ;;'
mutate optout-garbage "opt-out unknown value" '*) fail "opt-out: .agents/auto-merge on $base must say on or off" ;;' '*) ;;'
mutate optout-error "opt-out unreadable" '*) fail "opt-out: cannot read' '*) optout=on; true "opt-out: cannot read'
mutate optout-404 "every condition holds" '*"(HTTP 404)"*) optout=on ;;' '*"(HTTP 404)"*) optout=off ;;'
mutate token-gh "GH_TOKEN set" 'for name in GH_TOKEN GITHUB_TOKEN; do' 'for name in GITHUB_TOKEN; do'
mutate token-github "GITHUB_TOKEN set" 'for name in GH_TOKEN GITHUB_TOKEN; do' 'for name in GH_TOKEN; do'
mutate tools "gh missing" 'command -v "$tool" >/dev/null 2>&1 || fail' 'true || fail'
mutate allow-auto-merge "repo disallows auto-merge" '.allow_auto_merge == true' '.allow_auto_merge == true or true'
mutate pr-open "pull request not open" '[ "$state" = open ] ||' 'true ||'
mutate exactly-one "two pull_request rules" "| jq 'length')\" = 1 ]" "| jq 'length')\" -ge 1 ]"
mutate review-count "zero approvals" 'and . >= 1)' 'and . >= 0)'
mutate code-owner "require_code_owner_review false" 'for key in require_code_owner_review dismiss' 'for key in dismiss'
mutate stale "dismiss_stale_reviews_on_push false" 'dismiss_stale_reviews_on_push require_last_push_approval; do' 'require_last_push_approval; do'
mutate last-push "require_last_push_approval false" 'dismiss_stale_reviews_on_push require_last_push_approval; do' 'dismiss_stale_reviews_on_push; do'
mutate ruleset-active "ruleset not active" '= active ] \' '= active ] || true \'
mutate bypass "agent can bypass" '= never ] \' '= never ] || true \'
mutate codeowners-owner "CODEOWNERS names another owner" '[ "$have" = "$want" ] \' '[ "$have" = "$have" ] \'
mutate role "acting login is admin" '= write ] \' '= write ] || true \'
mutate api-error "403 from the rules API" 'fail "$label: cannot read $endpoint:' 'true "$label: cannot read $endpoint:'
mutate base-rules "base develop, only develop has rules" 'api rules "repos/$repo/rules/branches/$base_enc?per_page=100"' 'api rules "repos/$repo/rules/branches/main?per_page=100"'
mutate base-codeowners "base develop, only develop has rules" 'CODEOWNERS?ref=$base_enc"' 'CODEOWNERS?ref=main"'
mutate base-optout "base develop opt-out off" 'auto-merge?ref=$base_enc"' 'auto-merge?ref=main"'
mutate base-unencoded "base with a # is read as that branch" "base_enc=\$(jq -rn --arg b \"\$base\" '\$b | @uri')" 'base_enc=$base'
mutate pagination "every condition holds" '$base_enc?per_page=100' '$base_enc'
mutate lowercase "CODEOWNERS owner differs only in case" "tr -s '[:space:]' ' ' | tr '[:upper:]' '[:lower:]')" "tr -s '[:space:]' ' ')"
mutate owner-type "repo owned by an organization" '= User ] \' '= User ] || true \'
echo "all cases passed, and every mutant was caught"
