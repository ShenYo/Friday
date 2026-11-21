#!/usr/bin/env bash
# State tests for bin/friday-behind-notice and its workflow seed.
#
# Each case builds a scratch kit (a copy of bin/ and payload/ in a Git
# repository of its own, tagged as releases) and a scratch consumer holding the
# managed core, then runs the script with a shim `gh` on PATH that records every
# call and fails or answers as the case says. No network, no real GitHub.
# NOTICE_UNDER_TEST=<path> runs another copy of the script; the suite must fail
# for a script that opens an issue in the wrong state.
set -uo pipefail
[ "$#" -le 1 ] || { echo "usage: $0 [retained-output-directory]" >&2; exit 2; }

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
base=${1:-${TMPDIR:-/tmp}}
mkdir -p "$base"
root=$(cd "$base" && mktemp -d "$PWD/friday-behind-notice-test.XXXXXX")
echo "sandboxes: $root"
unset FRIDAY_PRODUCER GITHUB_REPOSITORY GH_TOKEN

TITLE='Friday: managed core is not in sync with the latest release'
fails=0; total=0; n=0
gq() { git -c user.name=t -c user.email=t@example.invalid "$@"; }

shim="$root/shim"; mkdir -p "$shim"
cat > "$shim/gh" <<'SHIM'
#!/usr/bin/env bash
# Stateful shim. Records the call; keeps the repository's issues in $GH_STATE (a
# JSON array of {number,title,state}). `issue list` honours --state (closed
# issues are returned unless `--state open`) and --limit (30 unless given),
# newest (highest number) first, like gh. `issue create` appends an open issue.
printf '%s\n' "$*" >> "$GH_LOG"
state=""; limit=30; title=""; body=""; prev=""
for a in "$@"; do
  case "$prev" in
    --state) state=$a ;; --limit) limit=$a ;; --title) title=$a ;; --body) body=$a ;;
  esac
  prev=$a
done
case "$1 $2" in
  "issue list")
    [ "${GH_FAIL:-}" = list ] && exit 1
    jq -c --arg s "$state" --argjson l "$limit" \
      '[.[] | select($s != "open" or .state == "OPEN")] | sort_by(-.number) | .[0:$l] | map({number,title})' "$GH_STATE"
    exit 0 ;;
  "issue create")
    [ "${GH_FAIL:-}" = create ] && exit 1
    printf '%s\n' "$title" >> "$GH_LOG.titles"; printf '%s' "$body" > "$GH_LOG.body"
    jq -c --arg t "$title" '. + [{number: (([.[].number] | max // 0) + 1), title: $t, state: "OPEN"}]' "$GH_STATE" > "$GH_STATE.new" \
      && mv "$GH_STATE.new" "$GH_STATE"
    echo "https://github.com/o/r/issues/1"; exit 0 ;;
  "issue edit")
    [ "${GH_FAIL:-}" = edit ] && exit 1
    printf '%s' "$body" > "$GH_LOG.body"; exit 0 ;;
esac
exit 0
SHIM
chmod +x "$shim/gh"

# A kit with release v1.0.0, and a consumer in sync with it.
setup() {
  n=$((n + 1))
  kit="$root/$n/kit"; consumer="$root/$n/consumer"; log="$root/$n/gh.log"; state="$root/$n/issues.json"
  mkdir -p "$kit/bin" "$consumer"; : > "$log"; echo '[]' > "$state"
  cp "$source_root/bin/friday-lock" "$kit/bin/"
  cp "${NOTICE_UNDER_TEST:-$source_root/bin/friday-behind-notice}" "$kit/bin/friday-behind-notice"
  cp "$source_root/bin/managed-core.txt" "$kit/bin/"
  cp -R "$source_root/payload" "$kit/payload"
  git init -q "$kit" && gq -C "$kit" add -A && gq -C "$kit" commit -q -m "payload v1"
  gq -C "$kit" tag -a v1.0.0 -m "release v1.0.0"
  git init -q "$consumer"
  while IFS= read -r rel; do
    case "$rel" in ''|'#'*|'!'*) continue ;; esac
    mkdir -p "$consumer/$(dirname "$rel")"
    cp "$kit/payload/$rel" "$consumer/$rel"
  done < "$kit/bin/managed-core.txt"
  bash "$kit/bin/friday-lock" write "$consumer" >/dev/null
}
# Friday ships a change to one managed file as release v1.0.1.
release_change() {
  local rel; rel=$(grep -v -e '^#' -e '^!' -e '^[[:space:]]*$' "$kit/bin/managed-core.txt" | sed -n 1p)
  printf '\n# a change\n' >> "$kit/payload/$rel"
  gq -C "$kit" add -A && gq -C "$kit" commit -q -m "payload v2" && gq -C "$kit" tag -a v1.0.1 -m "release v1.0.1"
}
# shellcheck disable=SC2034  # rc and out are read by the check strings
run() { # <args...>; sets rc and out
  out=$(cd "$consumer" && PATH="$shim:$PATH" GH_LOG="$log" GH_STATE="$state" GH_TOKEN=x GITHUB_REPOSITORY=o/r \
        bash "$kit/bin/friday-behind-notice" "$@" 2>&1)
  rc=$?
}
check() { # name, command that must succeed
  total=$((total + 1))
  if eval "$2"; then echo "ok   $1"; else
    echo "FAIL $1"; printf '%s\n' "$out" | sed 's/^/     /' | tail -6; echo "     gh: $(tr '\n' '|' < "$log" | cut -c1-200)"
    fails=$((fails + 1)); fi
}
seed() { printf '%s\n' "$1" > "$state"; } # the repository's issues before the run
creates() { grep -q '^issue create' "$log"; }
edits()   { grep -q '^issue edit' "$log"; }
writes()  { grep -q -e '^issue create' -e '^issue edit' "$log"; }

# 1. A stale lock is reported behind, and an issue is created with the fixed title.
setup; release_change; run v1.0.1 .
check "stale lock: exit 0"              '[ "$rc" -eq 0 ]'
check "stale lock: reports BEHIND"      'printf "%s" "$out" | grep -q "status: behind"'
check "stale lock: creates the issue"   'creates'
check "stale lock: exact title"         '[ "$(cat "$log.titles")" = "$TITLE" ]'
check "stale lock: create names the repo" 'grep -q "^issue create -R o/r " "$log"'
check "stale lock: body carries output" 'grep -q "BEHIND" "$log.body"'
check "stale lock: body has the status line, four-backtick fence" 'grep -q "status: behind" "$log.body" && grep -q "^\`\`\`\`text" "$log.body"'

# 2. An in-sync lock opens nothing.
setup; release_change; run v1.0.0 .
check "in sync: exit 0"                 '[ "$rc" -eq 0 ]'
check "in sync: no issue written"       '! writes'
check "in sync: no notice issue, no hint" '! printf "%s" "$out" | grep -q "still open"'
# 2b. In sync while the notice issue is open: say so, change nothing, exit 0.
setup; release_change
seed "[{\"number\":7,\"title\":\"$TITLE\",\"state\":\"OPEN\"}]"; run v1.0.0 .
check "in sync, issue open: exit 0"     '[ "$rc" -eq 0 ]'
check "in sync, issue open: hint names #7" 'printf "%s" "$out" | grep -qF "issue #7 is still open; close it now that the lock is in sync."'
check "in sync, issue open: nothing written" '! writes'
setup; release_change
seed "[{\"number\":7,\"title\":\"$TITLE\",\"state\":\"OPEN\"}]"; GH_FAIL=list run v1.0.0 .
check "in sync, list fails: still exit 0, warns" '[ "$rc" -eq 0 ] && printf "%s" "$out" | grep -q "warning"'

# 3. An open issue with the same title is updated, never duplicated.
setup; release_change
seed "[{\"number\":4,\"title\":\"unrelated\",\"state\":\"OPEN\"},{\"number\":7,\"title\":\"$TITLE\",\"state\":\"OPEN\"}]"
run v1.0.1 .
check "open issue: exit 0"              '[ "$rc" -eq 0 ]'
check "open issue: no create"           '! creates'
check "open issue: edits that number"   'grep -q "^issue edit 7 -R o/r" "$log"'
# 3b. Only an exact title match counts.
seed '[{"number":4,"title":"Friday: something else","state":"OPEN"}]'
: > "$log"; run v1.0.1 .
check "other title: creates, no edit"   'creates && ! edits'
# 3c. A closed issue with the same title is not reopened or edited: a new one opens.
seed "[{\"number\":9,\"title\":\"$TITLE\",\"state\":\"CLOSED\"}]"
: > "$log"; run v1.0.1 .
check "closed same title: creates, no edit" 'creates && ! edits'
# 3d. More than 30 open issues, the notice not among the newest 30: still one issue.
fixture=$(jq -nc --arg t "$TITLE" '[{number:1,title:$t,state:"OPEN"}] + [range(2;42) | {number:., title:"other \(.)", state:"OPEN"}]')
seed "$fixture"
: > "$log"; run v1.0.1 .
check "41 open issues: edits #1, no create" 'edits && ! creates && grep -q "^issue edit 1 -R o/r" "$log"'
# 3e. Two runs on one repository: one create, then one edit, never two creates.
setup; release_change
run v1.0.1 .; run v1.0.1 .
check "two runs: exactly one create"    '[ "$(grep -c "^issue create" "$log")" -eq 1 ]'
check "two runs: then one edit"         '[ "$(grep -c "^issue edit" "$log")" -eq 1 ] && [ "$(wc -l < "$log.titles")" -eq 1 ]'

# 4. A tool error (exit 2: no lock) fails and writes nothing.
setup; release_change; rm "$consumer/.friday-lock.json"; run v1.0.1 .
check "no lock: nonzero"                '[ "$rc" -ne 0 ]'
check "no lock: no issue written"       '! writes'
check "no lock: gh not called"          '[ ! -s "$log" ]'

# 5. gh failing on create fails the run; failing on list writes nothing.
setup; release_change; GH_FAIL=create run v1.0.1 .
check "gh create fails: nonzero"        '[ "$rc" -ne 0 ]'
setup; release_change; GH_FAIL=list run v1.0.1 .
check "gh list fails: nonzero"          '[ "$rc" -ne 0 ]'
check "gh list fails: nothing written"  '! writes'
setup; release_change; seed "[{\"number\":7,\"title\":\"$TITLE\",\"state\":\"OPEN\"}]"; GH_FAIL=edit run v1.0.1 .
check "gh edit fails: nonzero"          '[ "$rc" -ne 0 ]'

# 6. A drifted consumer is also a notice, and a bad argument is refused.
setup; printf '\n# local\n' >> "$consumer/$(grep -v -e '^#' -e '^!' -e '^[[:space:]]*$' "$kit/bin/managed-core.txt" | sed -n 1p)"; run v1.0.0 .
check "drifted: creates the issue"      'creates && [ "$rc" -eq 0 ]'
check "drifted: body has the status line, not the behind advice" 'grep -q "status: drifted" "$log.body" && ! grep -q "Take the change" "$log.body"'
setup; run main .
check "not a release tag: refused"      '[ "$rc" -ne 0 ] && [ ! -s "$log" ]'
setup; run v9.9.9 .
check "tag not in the kit: nonzero"     '[ "$rc" -ne 0 ] && ! writes'

# 7. The workflow seed: classified consumer-owned, and least privilege.
wf=.github/workflows/friday-behind.yml
perms() { awk '/^permissions:/ {p=1; next} p && /^[^ ]/ {p=0} p && NF {gsub(/^ +| +$/,""); print}' "$1"; }
wf_ok() { # file: permissions exactly contents: read + issues: write, one block, no secrets
  [ "$(perms "$1")" = "$(printf 'contents: read\nissues: write')" ] \
    && [ "$(grep -c '^permissions:' "$1")" -eq 1 ] \
    && ! grep -qE '^[[:space:]]+permissions:' "$1" \
    && ! grep -q 'secrets\.' "$1"
}
out=""
check "workflow: permissions are exactly contents: read, issues: write" 'wf_ok "$source_root/payload/$wf"'
check "workflow: listed as a consumer-owned seed" 'grep -qxF "!$wf" "$source_root/bin/managed-core.txt"'
check "workflow: triggers schedule and workflow_dispatch" 'grep -q "^  schedule:" "$source_root/payload/$wf" && grep -q "^  workflow_dispatch:" "$source_root/payload/$wf"'
mut="$root/mutant.yml"
sed 's/issues: write/contents: write/' "$source_root/payload/$wf" > "$mut"
check "workflow check: rejects a widened permission" '! wf_ok "$mut"'
{ cat "$source_root/payload/$wf"; printf '  x: ${{ secrets.TOKEN }}\n'; } > "$mut"
check "workflow check: rejects a secret"            '! wf_ok "$mut"'

echo
if [ "$fails" -eq 0 ]; then echo "all $total passed"; else echo "$fails of $total FAILED"; exit 1; fi
