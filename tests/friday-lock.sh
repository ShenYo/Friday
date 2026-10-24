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
first_managed() { grep -v -e '^#' -e '^!' -e '^[[:space:]]*$' "$kit/bin/managed-core.txt" | sed -n "${1}p"; }

expect() { # status, name
  local want=$1 name=$2 out got
  total=$((total + 1))
  out=$(bash "$kit/bin/friday-lock" check "$consumer" 2>&1)
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

echo
if [ "$fails" -gt 0 ]; then echo "$fails of $total failed"; exit 1; fi
echo "all $total passed"
