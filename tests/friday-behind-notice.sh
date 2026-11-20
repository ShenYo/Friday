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
# Records the call, then answers from the case's environment.
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  "issue list")   [ "${GH_FAIL:-}" = list ] && exit 1; printf '%s\n' "${GH_LIST_JSON:-[]}"; exit 0 ;;
  "issue create") [ "${GH_FAIL:-}" = create ] && exit 1; echo "https://github.com/o/r/issues/1"; exit 0 ;;
  "issue edit")   [ "${GH_FAIL:-}" = edit ] && exit 1; exit 0 ;;
esac
exit 0
SHIM
chmod +x "$shim/gh"

# A kit with release v1.0.0, and a consumer in sync with it.
setup() {
  n=$((n + 1))
  kit="$root/$n/kit"; consumer="$root/$n/consumer"; log="$root/$n/gh.log"
  mkdir -p "$kit/bin" "$consumer"; : > "$log"
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
  out=$(cd "$consumer" && PATH="$shim:$PATH" GH_LOG="$log" GH_TOKEN=x GITHUB_REPOSITORY=o/r \
        bash "$kit/bin/friday-behind-notice" "$@" 2>&1)
  rc=$?
}
check() { # name, command that must succeed
  total=$((total + 1))
  if eval "$2"; then echo "ok   $1"; else
    echo "FAIL $1"; printf '%s\n' "$out" | sed 's/^/     /' | tail -6; echo "     gh: $(tr '\n' '|' < "$log" | cut -c1-200)"
    fails=$((fails + 1)); fi
}
creates() { grep -q '^issue create' "$log"; }
edits()   { grep -q '^issue edit' "$log"; }
writes()  { grep -q -e '^issue create' -e '^issue edit' "$log"; }

# 1. A stale lock is reported behind, and an issue is created with the fixed title.
setup; release_change; run v1.0.1 .
check "stale lock: exit 0"              '[ "$rc" -eq 0 ]'
check "stale lock: reports BEHIND"      'printf "%s" "$out" | grep -q "status: behind"'
check "stale lock: creates the issue"   'creates'
check "stale lock: fixed title, repo"   'grep -qF -- "issue create -R o/r --title $TITLE" "$log"'
check "stale lock: body carries output" 'grep -q "BEHIND" "$log"'

# 2. An in-sync lock opens nothing.
setup; release_change; run v1.0.0 .
check "in sync: exit 0"                 '[ "$rc" -eq 0 ]'
check "in sync: no issue written"       '! writes'
check "in sync: gh not called at all"   '[ ! -s "$log" ]'

# 3. An open issue with the same title is updated, never duplicated.
setup; release_change
export GH_LIST_JSON="[{\"number\":4,\"title\":\"unrelated\"},{\"number\":7,\"title\":\"$TITLE\"}]"
: > "$log"; run v1.0.1 .
check "open issue: exit 0"              '[ "$rc" -eq 0 ]'
check "open issue: no create"           '! creates'
check "open issue: edits that number"   'grep -q "^issue edit 7 -R o/r" "$log"'
# 3b. Only an exact title match counts.
export GH_LIST_JSON='[{"number":4,"title":"Friday: something else"}]'
: > "$log"; run v1.0.1 .
check "other title: creates, no edit"   'creates && ! edits'
unset GH_LIST_JSON

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
setup; release_change; GH_LIST_JSON="[{\"number\":7,\"title\":\"$TITLE\"}]" GH_FAIL=edit run v1.0.1 .
check "gh edit fails: nonzero"          '[ "$rc" -ne 0 ]'

# 6. A drifted consumer is also a notice, and a bad argument is refused.
setup; printf '\n# local\n' >> "$consumer/$(grep -v -e '^#' -e '^!' -e '^[[:space:]]*$' "$kit/bin/managed-core.txt" | sed -n 1p)"; run v1.0.0 .
check "drifted: creates the issue"      'creates && [ "$rc" -eq 0 ]'
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
