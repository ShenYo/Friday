#!/usr/bin/env bash
# Tests for bin/friday-seed-check: a release that changes a consumer-owned seed
# needs a "### Seed changes" section in its changelog entry.
#
# Each case builds a scratch repository (bin/, a payload with one seed and one
# managed file, a changelog) with release tags, and runs the real script in it.
# CHECK_UNDER_TEST=<path> runs another copy of the script, which is how a
# mutant is tried. Sandboxes are left in place under the printed directory.
set -uo pipefail
[ "$#" -le 1 ] || { echo "usage: $0 [retained-output-directory]" >&2; exit 2; }

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
base=${1:-${TMPDIR:-/tmp}}
mkdir -p "$base"
root=$(mktemp -d "$base/friday-seed-check-test.XXXXXX")
root=$(cd "$root" && pwd)
echo "sandboxes: $root"

fails=0
total=0
ok()   { total=$((total + 1)); echo "ok   $1"; }
fail() { total=$((total + 1)); echo "FAIL $1"; fails=$((fails + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else fail "$name"; fi; }
gq() { git -c user.name=t -c user.email=t@example.invalid "$@"; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

n=0
new_repo() {
  n=$((n + 1)); r="$root/$n${1:-}"
  mkdir -p "$r/bin" "$r/payload" "$r/docs/changelog"
  cp "${CHECK_UNDER_TEST:-$source_root/bin/friday-seed-check}" "$r/bin/friday-seed-check"
  printf 'managed.md\n\n# --- consumer-owned ---\n!seed.md\n' > "$r/bin/managed-core.txt"
  printf 'managed\n' > "$r/payload/managed.md"; printf 'seed\n' > "$r/payload/seed.md"
  printf '# v1\n\n## Unreleased\n\n## v1.1.0 (2026-01-01)\n\n- first.\n' > "$r/docs/changelog/v1.md"
  git init -q -b main "$r" && gq -C "$r" add -A && gq -C "$r" commit -q -m "first" && gq -C "$r" tag -a v1.1.0 -m v1.1.0
}
# edit <file> <text>: append to a payload file and commit.
edit() { printf '%s\n' "$2" >> "$r/payload/$1"; gq -C "$r" commit -qam "payload: $1"; }
tag() { gq -C "$r" tag -a "$1" -m "$1"; }
# entry <heading> [with-section|no-section|missing-check]: set the top of the changelog.
entry() {
  local f="$r/docs/changelog/v1.md" tail_
  tail_=$(sed -n '/^## v1.1.0/,$p' "$f")
  {
    printf '# v1\n\n## %s\n\n- a change.\n\n' "$1"
    case "${2:-no-section}" in
      with-section|missing-check)
        printf '### Seed changes\n\n- **Capability:** cap\n- **Who is affected:** who\n- **Action:** do\n'
        [ "$2" = with-section ] && printf '%s\n' '- **Check:** `run it`'
        printf '\n' ;;
    esac
    printf '%s\n' "$tail_"
  } > "$f.new" && mv "$f.new" "$f"
  gq -C "$r" commit -qam "docs: changelog"
}
run() { bash "$r/bin/friday-seed-check" > "$r/out" 2>&1; rc=$?; }
says() { grep -q -- "$1" "$r/out"; }

# 1. A release that changed a seed, with the section: passes.
new_repo; edit seed.md one; entry "v1.2.0 (2026-02-01)" with-section; tag v1.2.0
run
check "release with a seed change and the section passes" bash -c "[ $rc = 0 ]"
check "... and the check says it looked at that release" says 'ok   v1.2.0: Seed changes section present'

# 2. The same release without the section fails, naming the release.
new_repo; edit seed.md one; entry "v1.2.0 (2026-02-01)" no-section; tag v1.2.0
run
check "release with a seed change and no section fails" bash -c "[ $rc = 1 ]"
check "... and names the release and the missing section" says "FAIL v1.2.0: changed a seed (payload/seed.md) .*no '### Seed changes' section"

# 3. A section that lacks a field fails, naming the field.
new_repo; edit seed.md one; entry "v1.2.0 (2026-02-01)" missing-check; tag v1.2.0
run
check "a section without the Check field fails" bash -c "[ $rc = 1 ]"
check "... and names the field" says "no '- \*\*Check:\*\* <text>' field"

# 4. A managed-only release needs nothing; neither does a seed change before v1.2.0.
new_repo; edit managed.md one; entry "v1.2.0 (2026-02-01)" no-section; tag v1.2.0
run
check "a release that changed no seed needs no section" bash -c "[ $rc = 0 ]"
new_repo; edit seed.md before-the-floor; tag v1.1.1; edit managed.md one; entry "v1.2.0 (2026-02-01)" no-section; tag v1.2.0
run
check "a seed change in a release before v1.2.0 is not asked for" bash -c "[ $rc = 0 ]"

# 5. The pending entry: a seed change since the last release.
new_repo; edit managed.md one; entry "v1.2.0 (2026-02-01)" no-section; tag v1.2.0
edit seed.md two; entry "Unreleased" no-section
run
check "pending: a seed change under Unreleased with no section fails" bash -c "[ $rc = 1 ] && grep -q 'FAIL pending' '$r/out'"
entry "Unreleased" with-section
run
check "pending: ... and passes once Unreleased has the section" bash -c "[ $rc = 0 ]"
sed -i.bak 's/^## Unreleased/## v1.3.0 (2026-03-01)/' "$r/docs/changelog/v1.md"; gq -C "$r" commit -qam "docs: release v1.3.0"
run
check "pending: an entry renamed for a tag not yet cut is the one checked" bash -c "[ $rc = 0 ] && grep -q 'ok   pending' '$r/out'"
new_repo; edit managed.md one; entry "v1.2.0 (2026-02-01)" no-section; tag v1.2.0
edit seed.md two
run
check "pending: when the top entry is already released, the seed change has no home and fails" \
  bash -c "[ $rc = 1 ] && grep -q 'already released' '$r/out'"

# 6. A clone without the full history cannot be judged, and says so.
new_repo; edit seed.md one; entry "v1.2.0 (2026-02-01)" no-section; tag v1.2.0
git clone -q --depth 1 "file://$r" "$r/shallow" 2>/dev/null
bash "$r/shallow/bin/friday-seed-check" > "$r/out" 2>&1; rc=$?
check "a shallow clone is refused, not passed" bash -c "[ $rc = 2 ] && grep -q 'shallow' '$r/out'"

# setlog: replace the changelog with stdin, and commit it.
setlog() { cat > "$r/docs/changelog/v1.md"; gq -C "$r" commit -qam "docs: changelog"; }
SECTION='### Seed changes

- **Capability:** cap
- **Who is affected:** who
- **Action:** do
- **Check:** chk
'

# 7. A path with a space in it is read whole.
new_repo " sp ace"; edit managed.md one; tag v1.2.0
edit seed.md two
setlog <<EOF
# v1

## Unreleased

- a change.

$SECTION
## v1.2.0 (2026-02-01)

- x.

## v1.1.0 (2026-01-01)

- first.
EOF
run
check "a kit path with a space: the pending entry is found and passes" bash -c "[ $rc = 0 ] && grep -q 'ok   pending' '$r/out'"

# 8. The section must be in the entry of the release that changed the seed.
new_repo; edit seed.md one; tag v1.2.0
setlog <<EOF
# v1

## v1.2.0 (2026-02-01)

- no section here.

## v1.1.0 (2026-01-01)

- first.

$SECTION
EOF
run
check "another entry's section does not cover this release" bash -c "[ $rc = 1 ] && grep -q 'FAIL v1.2.0' '$r/out'"
new_repo; edit seed.md one; tag v1.2.0
edit seed.md two
setlog <<EOF
# v1

## Unreleased

- no section here.

## v1.2.0 (2026-02-01)

- x.

$SECTION
## v1.1.0 (2026-01-01)

- first.
EOF
run
check "pending: the released entry's section does not cover the Unreleased entry" bash -c "[ $rc = 1 ] && grep -q 'FAIL pending' '$r/out'"

# 9. A field must have text, and the heading must be exactly "Seed changes".
new_repo; edit seed.md one; tag v1.2.0
setlog <<EOF
# v1

## v1.2.0 (2026-02-01)

### Seed changes

- **Capability:** cap
- **Who is affected:** who
- **Action:**
- **Check:** chk

## v1.1.0 (2026-01-01)
EOF
run
check "an empty field fails, and is named" bash -c "[ $rc = 1 ]"
check "... naming Action" says "no '- \*\*Action:\*\* <text>' field"
new_repo; edit seed.md one; tag v1.2.0
setlog <<EOF
# v1

## v1.2.0 (2026-02-01)

### Seed changes (notes)

- **Capability:** cap
- **Who is affected:** who
- **Action:** do
- **Check:** chk

## v1.1.0 (2026-01-01)
EOF
run
check "a heading that only starts with Seed changes is not the section" bash -c "[ $rc = 1 ] && grep -q \"no '### Seed changes' section\" '$r/out'"

# 10. The seed set is the union of both ends of the range.
new_repo; tag v1.2.0
printf 'second\n' > "$r/payload/seed2.md"; printf '!seed2.md\n' >> "$r/bin/managed-core.txt"
gq -C "$r" add -A; gq -C "$r" commit -qm "a seed joins"; tag v1.2.1
run
check "a seed added to managed-core.txt within the range counts" bash -c "[ $rc = 1 ] && grep -q 'FAIL v1.2.1: changed a seed (payload/seed2.md)' '$r/out'"
new_repo; tag v1.2.0
printf 'managed.md\n' > "$r/bin/managed-core.txt"; printf 'changed\n' >> "$r/payload/seed.md"
gq -C "$r" commit -qam "a seed is dropped from the list, and changes"; tag v1.2.1
run
check "a seed dropped from the list while its file changes counts" bash -c "[ $rc = 1 ] && grep -q 'FAIL v1.2.1: changed a seed (payload/seed.md)' '$r/out'"
new_repo; tag v1.2.0
printf 'managed.md\nseed.md\n' > "$r/bin/managed-core.txt"; printf 'changed\n' >> "$r/payload/seed.md"
gq -C "$r" commit -qam "a seed is promoted to managed core, and changes"; tag v1.2.1
run
check "a seed promoted to managed core with a content change counts" bash -c "[ $rc = 1 ] && grep -q 'FAIL v1.2.1: changed a seed (payload/seed.md)' '$r/out'"

# 11. The previous release is found by ancestry among vMAJOR.MINOR.PATCH tags.
new_repo; edit seed.md one; tag v1.2.0rc1
edit managed.md two; tag v1.2.0
run
check "a tag that is not a release does not shorten the range" bash -c "[ $rc = 1 ] && grep -q 'FAIL v1.2.0: changed a seed' '$r/out'"

# 12. No v1.2.0 tag: every release is held to the rule, and the run says so.
new_repo; edit seed.md one; tag v1.1.1
run
check "without a v1.2.0 tag every release is checked" bash -c "[ $rc = 1 ] && grep -q 'FAIL v1.1.1' '$r/out' && grep -q 'no v1.2.0 tag' '$r/out'"

# 13. HEAD reaching no release says so instead of printing nothing.
new_repo; tag v1.2.0
gq -C "$r" checkout -q --orphan other; gq -C "$r" commit -qm "unrelated root"
run
check "pending: no reachable release prints a skip line" bash -c "[ $rc = 0 ] && grep -q '^skip pending' '$r/out'"

# 14. An entry ends at its file's end: the next file's title and intro are not
#     part of it, so a section there is not the last entry's.
new_repo; edit seed.md one; tag v1.2.0
setlog <<EOF
# v1

## v1.1.0 (2026-01-01)

- first.

## v1.2.0 (2026-02-01)

- no section here.
EOF
cat > "$r/docs/changelog/v2.md" <<EOF
# v2

An intro.

$SECTION
EOF
run
check "the last entry of a file does not take a section from the next file" bash -c "[ $rc = 1 ] && grep -q 'FAIL v1.2.0' '$r/out'"

echo
if [ "$fails" -gt 0 ]; then echo "$fails of $total failed"; exit 1; fi
echo "all $total passed"
