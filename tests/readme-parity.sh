#!/usr/bin/env bash
# Tests for bin/check-readme-parity.py: a pair of language versions that drifts
# fails, and the real pairs pass.
#
# Each case writes a small good pair in a scratch directory, breaks it one way
# (a dropped section, a changed number, a dead link, a stale term) and runs the
# script. PARITY_UNDER_TEST=<path> runs another copy of the script; the suite
# must fail against one that has a check disabled. The last cases build such
# mutants, one per check, and require the cases to catch each. Needs python3.
set -uo pipefail
[ "$#" -le 1 ] || { echo "usage: $0 [retained-output-directory]" >&2; exit 2; }

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script=${PARITY_UNDER_TEST:-$source_root/bin/check-readme-parity.py}
base=${1:-${TMPDIR:-/tmp}}
mkdir -p "$base"
root=$(mktemp -d "$base/readme-parity-test.XXXXXX")
root=$(cd "$root" && pwd)
echo "sandboxes: $root"

fails=0
total=0
ok()   { total=$((total + 1)); echo "ok   $1"; }
fail() { total=$((total + 1)); echo "FAIL $1"; fails=$((fails + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else fail "$name"; fi; }

n=0
# new_pair: a good pair in a fresh directory $d, with an empty stale-terms file.
new_pair() {
  n=$((n + 1)); d="$root/$n"; mkdir -p "$d"
  : > "$d/docs.txt"
  printf '# T\n\n[a](./A.zh-TW.md)\n\n## One\n\nSee [x](./x.md). 3 files, the 2nd, 36.\n\n```sh\nls\n```\n\n### Sub\n' > "$d/A.md"
  printf '# T\n\n[a](./A.md)\n\n## 一\n\n見 [x](./x.md)。3 個檔，第 2 個，36。\n\n```sh\nls\n```\n\n### 子\n' > "$d/A.zh-TW.md"
  : > "$d/x.md"
}
# run <script>: run it on the pair in $d; the output goes to $d/out, the status to $rc.
run() { (cd "$d" && python3 -I "$1" A.md A.zh-TW.md "${2:-docs.txt}") > "$d/out" 2>&1; rc=$?; }
refused() { [ "$rc" = 1 ] && grep -q "$1" "$d/out"; }

# cases <script> <label>: every case against one script. Prints ok/FAIL lines, and
# returns the number of cases that failed.
cases() {
  local s=$1 l=$2 f=0
  c() { local name=$1; shift; if "$@"; then echo "ok   $l: $name"; else echo "FAIL $l: $name"; f=$((f + 1)); fi; }

  new_pair; run "$s"
  c "a good pair passes, ordinal and sentence-final numbers included" bash -c "[ $rc = 0 ] && grep -q '^Parity ok' '$d/out'"

  new_pair; printf '\n## Two\n' >> "$d/A.md"; run "$s"
  c "a dropped section fails" bash -c "[ $rc = 1 ] && grep -q '## sections: A.md has 2, A.zh-TW.md has 1' '$d/out'"

  new_pair; printf '\n```sh\nls\n```\n' >> "$d/A.md"; run "$s"
  c "a dropped code fence fails" bash -c "[ $rc = 1 ] && grep -q 'code fences' '$d/out'"

  new_pair; sed 's/36/37/' "$d/A.zh-TW.md" > "$d/t" && mv "$d/t" "$d/A.zh-TW.md"; run "$s"
  c "a changed number fails" bash -c "[ $rc = 1 ] && grep -q 'numbers differ -- only in A.md: 36; only in A.zh-TW.md: 37' '$d/out'"

  new_pair; printf '[y](./y.md)\n' >> "$d/A.md"; printf '[y](./y.md)\n' >> "$d/A.zh-TW.md"; run "$s"
  c "a dead link in both files fails" bash -c "[ $rc = 1 ] && grep -q 'link does not resolve: ./y.md' '$d/out'"

  new_pair; : > "$d/z.md"; printf '[z](./z.md)\n' >> "$d/A.md"; run "$s"
  c "a link in one file only fails" bash -c "[ $rc = 1 ] && grep -q 'relative links differ' '$d/out'"

  new_pair; printf 'old-term\n' > "$d/docs.txt"; printf 'old-term\n' >> "$d/A.zh-TW.md"; run "$s"
  c "a stale term in the other-language file fails" bash -c "[ $rc = 1 ] && grep -q \"A.zh-TW.md: stale term present: 'old-term'\" '$d/out'"

  new_pair; printf 'old-term\n' > "$d/docs.txt"; printf 'old-term\n' >> "$d/A.md"; run "$s"
  c "a stale term in the English file fails" bash -c "[ $rc = 1 ] && grep -q \"A.md: stale term present: 'old-term'\" '$d/out'"

  new_pair; sed 's/^\[a\].*/[a](.\/B.md)/' "$d/A.md" > "$d/t" && mv "$d/t" "$d/A.md"; run "$s"
  c "a language switcher pointing nowhere fails" bash -c "[ $rc = 1 ] && grep -q 'does not resolve' '$d/out'"

  return "$f"
}

out=$(cases "$script" real); f=$?
echo "$out"
total=$((total + $(echo "$out" | grep -c '^\(ok\|FAIL\)')))
fails=$((fails + f))

# The real pairs agree (this suite's script, the repository's stale terms).
for p in README ADOPTING; do
  if (cd "$source_root" && python3 -I "$script" "$p.md" "$p.zh-TW.md" bin/readme-stale-terms.txt) > "$root/$p.out" 2>&1; then
    ok "$p.md and $p.zh-TW.md agree"
  else
    fail "$p.md and $p.zh-TW.md agree"; cat "$root/$p.out"
  fi
done

# Mutants: copy the script with one check disabled; the cases must fail on each.
mutate() { # <name> <python replace: old> <new>
  local name=$1 old=$2 new=$3 m="$root/mutant-$1.py"
  python3 -I - "$script" "$m" "$old" "$new" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src, encoding="utf-8").read()
if old not in t:
    sys.exit("mutant target not found: " + old)
open(dst, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
  [ -f "$m" ] || { fail "mutant $name could not be built"; return; }
  if cases "$m" "mutant-$name" > "$root/mutant-$name.out"; then
    fail "mutant '$name' is caught by the cases (it was not)"
  else
    ok "mutant '$name' is caught by the cases"
  fi
}
mutate structure  '        if va != vb:'      '        if False:'
mutate numbers    '    if na != nb:'          '    if False:'
mutate links-diff '    if la != lb:'          '    if False:'
mutate resolve    '            if not (root / link).exists():' '            if False:'
mutate stale      '                if term in text:' '                if False:'

echo
if [ "$fails" -gt 0 ]; then echo "$fails of $total failed"; exit 1; fi
echo "all $total passed"
