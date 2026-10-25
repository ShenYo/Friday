#!/usr/bin/env bash
# State tests for bin/friday-lock.
#
# Each case builds a scratch kit -- a copy of bin/ and payload/ in a Git
# repository of its own, so a later payload revision can be committed -- and a
# scratch consumer installed from it, then asserts the status `check` reports.
# Sandboxes are left in place under the printed directory.
set -uo pipefail
[ "$#" -le 1 ] || { echo "usage: $0 [retained-output-directory]" >&2; exit 2; }

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
base=${1:-${TMPDIR:-/tmp}}
mkdir -p "$base"
root=$(mktemp -d "$base/friday-lock-test.XXXXXX")
echo "sandboxes: $root"

fails=0
total=0
n=0
gq() { git -c user.name=t -c user.email=t@example.invalid "$@"; }

# A kit at the current payload, and a consumer holding every managed file.
setup() {
  n=$((n + 1))
  kit="$root/$n/kit"; consumer="$root/$n/consumer"
  mkdir -p "$kit/bin" "$consumer"
  cp "${LOCK_UNDER_TEST:-$source_root/bin/friday-lock}" "$kit/bin/friday-lock"
  cp "$source_root/bin/managed-core.txt" "$kit/bin/"
  cp -R "$source_root/payload" "$kit/payload"
  git init -q "$kit" && gq -C "$kit" add -A && gq -C "$kit" commit -q -m "payload v1"
  git init -q "$consumer"
  while IFS= read -r rel; do
    case "$rel" in ''|'#'*|'!'*) continue ;; esac
    mkdir -p "$consumer/$(dirname "$rel")"
    cp "$kit/payload/$rel" "$consumer/$rel"
  done < "$kit/bin/managed-core.txt"
  bash "$kit/bin/friday-lock" write "$consumer" >/dev/null
}
commit_kit() { gq -C "$kit" add -A && gq -C "$kit" commit -q -m "$1"; }
tag_kit() { gq -C "$kit" tag -a "$1" -m "release $1"; }
move_tag() { gq -C "$kit" tag -f -a "$1" -m "release $1" >/dev/null; }
# Record again, as friday-lock write would, optionally pinned to the kit's HEAD.
rewrite() { ${PIN:+env FRIDAY_TREE="$(git -C "$kit" rev-parse HEAD)"} bash "$kit/bin/friday-lock" write "$consumer" >/dev/null; }
lock_tag() { jq -c 'if .friday | has("tag") then .friday.tag else "absent" end' "$consumer/.friday-lock.json"; }
first_managed() { grep -v -e '^#' -e '^!' -e '^[[:space:]]*$' "$kit/bin/managed-core.txt" | sed -n "${1}p"; }

expect() { # status, name
  local want=$1 name=$2 out got
  total=$((total + 1))
  out=$(${PIN:+env FRIDAY_TREE="$(git -C "$kit" rev-parse HEAD)"} bash "$kit/bin/friday-lock" check "$consumer" 2>&1)
  got=$(printf '%s\n' "$out" | sed -n 's/^status: //p')
  if [ "$got" = "$want" ]; then
    echo "ok   $want: $name"
  else
    echo "FAIL want '$want', got '${got:-no status}': $name"
    printf '%s\n' "$out" | sed 's/^/     /' | tail -8
    fails=$((fails + 1))
  fi
  last_out=$out
}
says() { # a line the last check must contain
  total=$((total + 1))
  if printf '%s\n' "$last_out" | grep -qF -- "$1"; then echo "ok   says: $1"; else echo "FAIL missing: $1"; fails=$((fails + 1)); fi
}

equals() { # got, want, name
  total=$((total + 1))
  if [ "$1" = "$2" ]; then echo "ok   $3"; else echo "FAIL $3: want '$2', got '$1'"; fails=$((fails + 1)); fi
}

setup
expect "in sync" "a fresh install"

setup
printf '\n# local edit\n' >> "$consumer/$(first_managed 1)"
expect drifted "a managed file edited in the consumer"

setup
printf '\n# payload v2\n' >> "$kit/payload/$(first_managed 1)"
commit_kit "payload v2"
expect behind "a managed file that moved in the payload"

# A file that joined the managed core after the lock was written. The lock has
# no entry for it, and a check that iterates only the lock never looks.
setup
mkdir -p "$kit/payload/.agents/docs"
printf 'new\n' > "$kit/payload/.agents/docs/added.md"
printf '.agents/docs/added.md\n' >> "$kit/bin/managed-core.txt"
commit_kit "payload: add a managed file"
expect behind "a file that joined the managed core"
says ".agents/docs/added.md (new in the payload)"

# A file that left the managed core. The consumer still has it and the lock
# still records it; deleting it is a person's call, so the check names it.
setup
gone=$(first_managed 2)
grep -vxF -- "$gone" "$kit/bin/managed-core.txt" > "$kit/bin/managed-core.txt.new"
mv "$kit/bin/managed-core.txt.new" "$kit/bin/managed-core.txt"
mv "$kit/payload/$gone" "$root/$n/retired-file"
commit_kit "payload: retire a managed file"
expect retired "a file that left the managed core"
says "RETIRED"
says "  $gone"

# Both at once: the change to carry outranks the decision to make, and the
# retired file is still named.
setup
gone=$(first_managed 2)
grep -vxF -- "$gone" "$kit/bin/managed-core.txt" > "$kit/bin/managed-core.txt.new"
mv "$kit/bin/managed-core.txt.new" "$kit/bin/managed-core.txt"
mv "$kit/payload/$gone" "$root/$n/retired-file"
printf '\n# payload v2\n' >> "$kit/payload/$(first_managed 1)"
commit_kit "payload: retire one file, move another"
expect behind "a retired file alongside a moved one"
says "  $gone"

# A retired file the consumer edited is reported retired, not drifted: it is
# no longer Friday's to compare.
setup
gone=$(first_managed 2)
printf '\n# local edit\n' >> "$consumer/$gone"
grep -vxF -- "$gone" "$kit/bin/managed-core.txt" > "$kit/bin/managed-core.txt.new"
mv "$kit/bin/managed-core.txt.new" "$kit/bin/managed-core.txt"
mv "$kit/payload/$gone" "$root/$n/retired-file"
commit_kit "payload: retire a file the consumer edited"
expect retired "a retired file the consumer had edited"

# A path outside ASCII reads the same pinned to a commit as from the working
# tree. git quotes such paths unless told not to, and a quoted path matches no
# managed-core entry.
setup
mkdir -p "$kit/payload/.agents/docs"
printf 'caf\n' > "$kit/payload/.agents/docs/café.md"
printf '.agents/docs/café.md\n' >> "$kit/bin/managed-core.txt"
commit_kit "payload: a non-ASCII managed file"
mkdir -p "$consumer/.agents/docs"; cp "$kit/payload/.agents/docs/café.md" "$consumer/.agents/docs/"
bash "$kit/bin/friday-lock" write "$consumer" >/dev/null
expect "in sync" "a non-ASCII path, read from the working tree"
PIN=1 expect "in sync" "a non-ASCII path, read from a pinned commit"

# --- releases ----------------------------------------------------------------

# The lock records the newest tag whose commit holds the same payload, or null.
setup
tag_kit v1.0.0; rewrite
equals "$(lock_tag)" '"v1.0.0"' "write: records the tag whose commit holds this payload"
equals "$(jq -c '.friday | keys_unsorted' "$consumer/.friday-lock.json")" '["repo","commit","tag","synced"]' "write: field order is repo, commit, tag, synced"
expect "in sync" "a lock that records a tag"
says "release: v1.0.0"

setup
equals "$(lock_tag)" 'null' "write: null when no tag exists"
expect "in sync" "a lock that records no tag"
says "release: none"

# Version order, not name order: v1.10.0 is newer than v1.9.0.
setup
tag_kit v1.9.0; tag_kit v1.10.0; rewrite
equals "$(lock_tag)" '"v1.10.0"' "write: the newest of two tags on equal payload wins, by version"

# A tag on exactly the pinned commit beats a newer tag that only has equal content.
setup
tag_kit v1.0.0
printf 'notes\n' > "$kit/NOTES"; commit_kit "docs: notes"; tag_kit v1.0.1
FRIDAY_TREE=$(git -C "$kit" rev-parse 'v1.0.0^{commit}') bash "$kit/bin/friday-lock" write "$consumer" >/dev/null
equals "$(lock_tag)" '"v1.0.0"' "write: pinning the older of two equal-content tags records the older"
FRIDAY_TREE=$(git -C "$kit" rev-parse 'v1.0.1^{commit}') bash "$kit/bin/friday-lock" write "$consumer" >/dev/null
equals "$(lock_tag)" '"v1.0.1"' "write: pinning the newer records the newer"
rewrite
equals "$(lock_tag)" '"v1.0.1"' "write: unpinned HEAD records the tag on HEAD"

# A stale clone is not evidence of tampering: without the recorded commit the
# tag cannot be compared, and a tag that is not here is unverified, not moved.
setup
tag_kit v1.0.0; rewrite
printf '\n# payload v2\n' >> "$kit/payload/$(first_managed 1)"
commit_kit "payload v2"
jq '.friday.commit = "0000000000000000000000000000000000000000"' "$consumer/.friday-lock.json" > "$root/$n/lock" && mv "$root/$n/lock" "$consumer/.friday-lock.json"
gq -C "$kit" tag -d v1.0.0 >/dev/null
expect behind "a clone lacking both the recorded commit and the tag"
total=$((total + 1))
if printf '%s\n' "$last_out" | grep -qF -e MOVED -e not\ found; then echo "FAIL a stale clone raised a tag finding"; fails=$((fails + 1)); else echo "ok   a stale clone raises no tag finding"; fi
setup
tag_kit v1.0.0; rewrite
printf '\n# payload v2\n' >> "$kit/payload/$(first_managed 1)"
commit_kit "payload v2"; move_tag v1.0.0
jq '.friday.commit = "0000000000000000000000000000000000000000"' "$consumer/.friday-lock.json" > "$root/$n/lock" && mv "$root/$n/lock" "$consumer/.friday-lock.json"
expect behind "a differing tag is not compared when the recorded commit is absent"

# FRIDAY_RELEASE names the tag meant when several share the pinned commit, but
# only a release tag that points exactly there.
setup
tag_kit v1.0.0; tag_kit v1.0.1
FRIDAY_TREE=$(git -C "$kit" rev-parse HEAD) FRIDAY_RELEASE=v1.0.0 bash "$kit/bin/friday-lock" write "$consumer" >/dev/null
equals "$(lock_tag)" '"v1.0.0"' "write: FRIDAY_RELEASE picks the older of two tags on one commit"
printf 'notes\n' > "$kit/NOTES"; commit_kit "docs: notes"; tag_kit v1.0.2
FRIDAY_TREE=$(git -C "$kit" rev-parse HEAD) FRIDAY_RELEASE=v1.0.0 bash "$kit/bin/friday-lock" write "$consumer" >/dev/null
equals "$(lock_tag)" '"v1.0.2"' "write: FRIDAY_RELEASE naming a tag on another commit is ignored"
FRIDAY_TREE=$(git -C "$kit" rev-parse HEAD) FRIDAY_RELEASE=v9.9.9 bash "$kit/bin/friday-lock" write "$consumer" >/dev/null
equals "$(lock_tag)" '"v1.0.2"' "write: FRIDAY_RELEASE naming a tag that does not exist is ignored"

# A release is exactly vMAJOR.MINOR.PATCH.
setup
tag_kit v1.0.0-rc1; tag_kit v1x; tag_kit v1.0.0.1; rewrite
equals "$(lock_tag)" 'null' "write: pre-release and malformed tags are never releases"
tag_kit v1.0.0; tag_kit v1.0.1-rc1; rewrite
equals "$(lock_tag)" '"v1.0.0"' "write: a pre-release on the same commit does not displace the release"
printf 'notes\n' > "$kit/NOTES"; commit_kit "docs: notes"; tag_kit v1.0.2-rc1
rewrite
equals "$(lock_tag)" '"v1.0.0"' "write: a pre-release on the content-equal commit is not picked either"
FRIDAY_RELEASE=v1.0.2-rc1 rewrite
equals "$(lock_tag)" '"v1.0.0"' "write: FRIDAY_RELEASE naming a pre-release is ignored"

# A later payload commit that nobody tagged is not any release.
setup
tag_kit v1.0.0
printf '\n# payload v2\n' >> "$kit/payload/$(first_managed 1)"
commit_kit "payload v2"; rewrite
equals "$(lock_tag)" 'null' "write: a later untagged payload commit records null"
tag_kit v1.1.0; rewrite
equals "$(lock_tag)" '"v1.1.0"' "write: ... and the tag that follows it is recorded"

# Content decides, not commits: a commit outside the payload is the same release.
setup
tag_kit v1.0.0
printf 'notes\n' > "$kit/NOTES"; commit_kit "docs: notes"; rewrite
equals "$(lock_tag)" '"v1.0.0"' "write: a later commit that moves no payload byte is still that release"

# ... and a change to the managed-core list alone is not.
setup
tag_kit v1.0.0
printf '# a note\n' >> "$kit/bin/managed-core.txt"; commit_kit "managed core: a note"; rewrite
equals "$(lock_tag)" 'null' "write: a changed managed-core list is not the tagged release"

# The working tree is not a release; a pin to a commit is.
setup
tag_kit v1.0.0
printf '\n# uncommitted\n' >> "$kit/payload/$(first_managed 1)"; rewrite
equals "$(lock_tag)" 'null' "write: an uncommitted payload edit records null when not pinned"
PIN=1 rewrite
equals "$(lock_tag)" '"v1.0.0"' "write: the same edit does not matter when pinned to a commit"
setup
tag_kit v1.0.0
printf '# uncommitted\n' >> "$kit/bin/managed-core.txt"; rewrite
equals "$(lock_tag)" 'null' "write: an uncommitted managed-core edit records null when not pinned"

# A lock written before releases existed is still a valid record.
setup
jq 'del(.friday.tag)' "$consumer/.friday-lock.json" > "$root/$n/lock" && mv "$root/$n/lock" "$consumer/.friday-lock.json"
expect "in sync" "an old lock with no tag field"
says "release: none"

# A tag that moved or vanished is reported, not trusted.
setup
tag_kit v1.0.0; rewrite
printf '\n# payload v2\n' >> "$kit/payload/$(first_managed 1)"
commit_kit "payload v2"; move_tag v1.0.0
expect tag-moved "a tag re-pointed to a commit with a different payload"
says "MOVED -- the release tag no longer matches what this lock recorded:"
says "  v1.0.0 now points at"

setup
tag_kit v1.0.0; rewrite
gq -C "$kit" tag -d v1.0.0 >/dev/null
expect "in sync" "a tag this clone does not have, with the recorded commit present"
says "release v1.0.0 not found in this Friday clone (fetch tags, or it was deleted); not verified"

setup
tag_kit v1.0.0; rewrite
printf '\n# payload v2\n' >> "$kit/payload/$(first_managed 1)"
commit_kit "payload v2"; move_tag v1.0.0
printf '\n# local edit\n' >> "$consumer/$(first_managed 2)"
expect drifted "drifted still wins over a moved tag"
says "MOVED"

# Moving a tag to a commit with the same payload changes nothing the lock named.
setup
tag_kit v1.0.0; rewrite
printf 'notes\n' > "$kit/NOTES"; commit_kit "docs: notes"; move_tag v1.0.0
expect "in sync" "a tag re-pointed to a commit with the same payload"
says "release: v1.0.0"

# A tag still in place is not a reason to hide that Friday moved on.
setup
tag_kit v1.0.0; rewrite
printf '\n# payload v2\n' >> "$kit/payload/$(first_managed 1)"
commit_kit "payload v2"
expect behind "a recorded tag that is intact while the payload moved on"
says "release: v1.0.0"

# A list that changed after the recorded commit, in a release cut after it, is
# the lock's own release, not a moved tag.
setup
printf '# a note\n' >> "$kit/bin/managed-core.txt"; commit_kit "managed core: a note"; tag_kit v1.0.0; rewrite
expect "in sync" "a release cut on a list-only commit after the recorded one"
says "release: v1.0.0"

# A list that differs on a commit from nowhere near the recorded one is moved.
setup
tag_kit v1.0.0; rewrite
orig=$(git -C "$kit" symbolic-ref --short HEAD)
gq -C "$kit" checkout -q --orphan alt
printf '# a note\n' >> "$kit/bin/managed-core.txt"; commit_kit "orphan: a different list"
move_tag v1.0.0; gq -C "$kit" checkout -q -f "$orig"
expect tag-moved "a tag re-pointed to an unrelated commit with a different list"

echo
if [ "$fails" -gt 0 ]; then echo "$fails of $total failed"; exit 1; fi
echo "all $total passed"
