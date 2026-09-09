#!/usr/bin/env bash
# A fixture-only installer regression check; preserve outputs for inspection.
set -euo pipefail
[ "$#" -eq 1 ] || { echo "usage: $0 retained-output-directory" >&2; exit 2; }
source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$1"
run=$(mktemp -d "$1/run.XXXXXX")
kit="$run/kit"
mkdir -p "$kit/.git" "$kit/payload/.agents/hooks" "$kit/payload/.claude"
cp "$source_root/install.sh" "$kit/install.sh"
printf '#!/usr/bin/env bash\nprintf "checked\\n" >> .selfcheck-runs\n[ ! -e .fail-selfcheck ]\n' > "$kit/payload/.agents/hooks/check-collaborative-git.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$kit/payload/.agents/hooks/guard-collaborative-git.sh"
printf '{"fixture":true}\n' > "$kit/payload/.claude/settings.json"
printf 'fixture payload\n' > "$kit/payload/new.txt"
target() { mkdir -p "$run/$1/.git"; }
reject() {
  if bash "$kit/install.sh" "$@" > "$run/rejection.log" 2>&1; then
    echo "FAIL: unexpectedly accepted $*" >&2; exit 1
  fi
}

target fresh
bash "$kit/install.sh" --check "$run/fresh" > "$run/preview.log"
grep -q '^NEW new.txt$' "$run/preview.log"
[ ! -e "$run/fresh/new.txt" ] && [ ! -e "$run/fresh/.agents" ]
[ ! -e "$run/fresh/.selfcheck-runs" ]
bash "$kit/install.sh" "$run/fresh" > "$run/install.log"
[ "$(wc -l < "$run/fresh/.selfcheck-runs")" -eq 1 ]
cmp "$kit/payload/new.txt" "$run/fresh/new.txt"
[ "$(readlink "$run/fresh/.claude/hooks/guard-collaborative-git.sh")" = ../../.agents/hooks/guard-collaborative-git.sh ]
printf 'local overlay\n' > "$run/fresh/local.txt"
printf '# local hook\n' > "$run/fresh/.agents/hooks/local.sh"
chmod 600 "$run/fresh/.agents/hooks/local.sh"
chmod 600 "$run/fresh/.agents/hooks/guard-collaborative-git.sh"
bash "$kit/install.sh" --check "$run/fresh" > "$run/second-preview.log"
grep -q '^IDENTICAL new.txt$' "$run/second-preview.log"
[ "$(wc -l < "$run/fresh/.selfcheck-runs")" -eq 1 ]
[ ! -x "$run/fresh/.agents/hooks/guard-collaborative-git.sh" ]
bash "$kit/install.sh" "$run/fresh" > "$run/reinstall.log"
[ "$(wc -l < "$run/fresh/.selfcheck-runs")" -eq 2 ]
[ -x "$run/fresh/.agents/hooks/guard-collaborative-git.sh" ]
[ ! -x "$run/fresh/.agents/hooks/local.sh" ]
[ "$(cat "$run/fresh/local.txt")" = 'local overlay' ]

target conflict
mkdir -p "$run/conflict/.claude"
printf 'local settings\n' > "$run/conflict/.claude/settings.json"
reject --check "$run/conflict"
grep -q '^CONFLICT .claude/settings.json ' "$run/rejection.log"
reject "$run/conflict"
[ ! -e "$run/conflict/new.txt" ] && [ ! -e "$run/conflict/.agents" ]
[ "$(cat "$run/conflict/.claude/settings.json")" = 'local settings' ]

target parent-link
mkdir -p "$run/outside"
ln -s "$run/outside" "$run/parent-link/.agents"
reject "$run/parent-link"
[ ! -e "$run/outside/hooks" ] && [ ! -e "$run/parent-link/new.txt" ]

target file-link
mkdir -p "$run/file-link/.claude"
printf 'outside content\n' > "$run/outside/settings.json"
ln -s "$run/outside/settings.json" "$run/file-link/.claude/settings.json"
reject "$run/file-link"
[ ! -e "$run/file-link/new.txt" ]
[ "$(cat "$run/outside/settings.json")" = 'outside content' ]

target dangling
mkdir -p "$run/dangling/.claude/hooks"
ln -s "$run/absent" "$run/dangling/.claude/hooks/guard-collaborative-git.sh"
reject "$run/dangling"
[ -L "$run/dangling/.claude/hooks/guard-collaborative-git.sh" ]
[ ! -e "$run/dangling/new.txt" ]

target type-conflict
mkdir -p "$run/type-conflict/new.txt"
reject "$run/type-conflict"
[ ! -e "$run/type-conflict/.agents" ]

target selfcheck-failure
touch "$run/selfcheck-failure/.fail-selfcheck"
reject "$run/selfcheck-failure"
[ "$(wc -l < "$run/selfcheck-failure/.selfcheck-runs")" -eq 1 ]
grep -q 'self-check FAILED' "$run/rejection.log"

reject --unknown
reject "$run/fresh" extra
reject "$kit"
reject "$run/outside"

# Keep dirname available so this fails at the jq preflight, not earlier.
target missing-jq
mkdir -p "$run/no-jq-bin"
ln -s /usr/bin/dirname "$run/no-jq-bin/dirname"
if PATH="$run/no-jq-bin" /bin/bash "$kit/install.sh" "$run/missing-jq" > "$run/missing-jq.log" 2>&1; then
  echo 'FAIL: missing prerequisite accepted' >&2; exit 1
fi
grep -q "'jq' is required" "$run/missing-jq.log"
[ ! -e "$run/missing-jq/new.txt" ] && [ ! -e "$run/missing-jq/.agents" ]
echo "PASS: preview states, self-check execution/failure, idempotence, conflict/type/symlink gates, arguments and prerequisites"
echo "Retained fixture evidence: $run"
