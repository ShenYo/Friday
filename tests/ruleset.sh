#!/usr/bin/env bash
# The ruleset seed parses, has the top-level, conditions and pull_request keys
# and the rule types the REST API documents (the rest of each rule's shape is
# not checked), and carries the rules the safety boundary assumes of the default
# branch.
# CI passes an output directory as $1, which this test does not use.
# RULESET_UNDER_TEST=<file> tests that file instead (to prove the test fails
# on a broken one).
set -euo pipefail
root=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)
file=${RULESET_UNDER_TEST:-$root/payload/.github/rulesets/main.json}
python3 -I - "$file" "$root" <<'PY'
import json, sys
file, root = sys.argv[1:3]
r = json.load(open(file))
def fail(m):
    print("FAIL: " + m); sys.exit(1)
# Fields documented for POST /repos/{owner}/{repo}/rulesets and for the rules used.
top = {"name", "target", "enforcement", "conditions", "rules", "bypass_actors"}
if set(r) - top: fail("undocumented top-level field %s" % sorted(set(r) - top))
if r["target"] != "branch": fail("target is not branch")
if r["enforcement"] != "active": fail("enforcement is not active")
if set(r["conditions"]) != {"ref_name"}: fail("conditions has keys other than ref_name")
rn = r["conditions"]["ref_name"]
if set(rn) != {"include", "exclude"}: fail("ref_name keys are not include and exclude")
if rn["exclude"] != []: fail("ref_name.exclude is not empty")
if rn["include"] != ["~DEFAULT_BRANCH"]: fail("ref_name.include is not exactly [~DEFAULT_BRANCH]")
if {x["type"] for x in r["rules"]} - {"deletion", "non_fast_forward", "pull_request", "required_status_checks"}:
    fail("a rule type other than deletion, non_fast_forward, pull_request, required_status_checks")
rules = {x["type"]: x.get("parameters") for x in r["rules"]}
for t in ("deletion", "non_fast_forward", "pull_request"):
    if t not in rules: fail("missing rule " + t)
if len(rules) != len(r["rules"]): fail("a rule type is listed twice")
for t in ("deletion", "non_fast_forward"):
    if "parameters" in next(x for x in r["rules"] if x["type"] == t): fail(t + " carries parameters")
pr = rules["pull_request"]
n = pr["required_approving_review_count"]
if type(n) is not int or not 1 <= n <= 10: fail("required_approving_review_count is not between 1 and 10")
m = pr["allowed_merge_methods"]
if not m or not set(m) <= {"merge", "squash", "rebase"}: fail("allowed_merge_methods is empty or has an invalid method")
for k in ("require_code_owner_review", "dismiss_stale_reviews_on_push",
          "require_last_push_approval", "required_review_thread_resolution"):
    if pr[k] is not True: fail(k + " is not true")
known = {"allowed_merge_methods", "dismiss_stale_reviews_on_push", "require_code_owner_review",
         "require_extra_approval_for_unattributed_changes", "require_last_push_approval",
         "required_approving_review_count", "required_review_thread_resolution", "required_reviewers"}
if set(pr) - known: fail("undocumented pull_request parameter")
if "required_status_checks" in rules and not rules["required_status_checks"]["required_status_checks"]:
    fail("required_status_checks with no check")
# The only bypass is the repository admin role, in pull_request mode.
if r["bypass_actors"] != [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request"}]:
    fail("bypass_actors is not the admin role in pull_request mode")
print("ok: ruleset file")
PY
doc=$root/payload/.agents/docs/git-guideline/safety-boundary.md
for s in '## The server-side ruleset' '.github/rulesets/main.json' 'gh api --method POST repos/OWNER/REPO/rulesets' 'free GitHub plan' 'diff <(jq -S' 'rules/branches/' '--jq .default_branch'; do
  grep -Fq -- "$s" "$doc" || { echo "FAIL: safety-boundary.md lacks: $s"; exit 1; }
done
echo "ruleset: all passed"
