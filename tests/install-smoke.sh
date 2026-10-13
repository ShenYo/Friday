#!/usr/bin/env bash
# Live-payload installer regression check; preserve outputs for inspection.
set -euo pipefail
[ "$#" -eq 1 ] || { echo "usage: $0 retained-output-directory" >&2; exit 2; }
source_root=$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)
mkdir -p "$1"
run=$(mktemp -d "$1/run.XXXXXX")
kit="$source_root"
expected='
AGENTS.md
.agents/AGENTS.md
.agents/docs/agent-rules.md
.agents/docs/scratch-files.md
.agents/docs/git-guideline/git-commit.md
.agents/docs/git-guideline/pr-evidence.md
.agents/docs/git-guideline/safety-boundary.md
.agents/hooks/check-collaborative-git.sh
.agents/hooks/guard-collaborative-git.sh
.agents/skills/git/commit/SKILL.md
.agents/skills/git/create-pr/SKILL.md
.agents/skills/git/push/SKILL.md
.gitignore
.claude/settings.json'
target() { git init -q "$run/$1"; }
reject() {
  if bash "$kit/install.sh" "$@" > "$run/rejection.log" 2>&1; then
    echo "FAIL: unexpectedly accepted $*" >&2; exit 1
  fi
}

target fresh
bash "$kit/install.sh" --check "$run/fresh" > "$run/preview.log"
for rel in $expected; do grep -q "^NEW $rel$" "$run/preview.log"; done
[ ! -e "$run/fresh/AGENTS.md" ] && [ ! -e "$run/fresh/.agents" ]
bash "$kit/install.sh" "$run/fresh" > "$run/install.log"
for rel in $expected; do cmp "$kit/payload/$rel" "$run/fresh/$rel"; done
[ "$(readlink "$run/fresh/.claude/hooks/guard-collaborative-git.sh")" = ../../.agents/hooks/guard-collaborative-git.sh ]
(cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh)
project_check="$run/fresh/.agents/hooks/check-project-agent-integration.sh"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'touch .project-check-ran' > "$project_check"
chmod +x "$project_check"
(cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh)
[ -f "$run/fresh/.project-check-ran" ]
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$project_check"
chmod +x "$project_check"
if (cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh) > "$run/project-check-failure.log" 2>&1; then
  echo 'FAIL: failing project integration check was accepted' >&2; exit 1
fi
grep -q 'project integration check failed' "$run/project-check-failure.log"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$project_check"
chmod +x "$project_check"
(cd "$run/fresh" && bash .agents/hooks/check-collaborative-git.sh)
unlink "$project_check"
mkdir -p "$run/fresh/docs/temp/probe"
touch "$run/fresh/docs/temp/probe/file.md"
git -C "$run/fresh" check-ignore -v docs/temp/probe/file.md > "$run/ignore.log"
grep -q 'docs/temp/' "$run/ignore.log"
actual=$(cd "$run/fresh" && { printf '%s\n' AGENTS.md .gitignore; find .agents .claude \( -type f -o -type l \) -print; } | sort)
expected_installed=$(printf '%s\n' $expected .claude/hooks/guard-collaborative-git.sh | sort)
[ "$actual" = "$expected_installed" ]
printf 'local overlay\n' > "$run/fresh/local.txt"
printf '# local hook\n' > "$run/fresh/.agents/hooks/local.sh"
chmod 600 "$run/fresh/.agents/hooks/local.sh"
chmod 600 "$run/fresh/.agents/hooks/guard-collaborative-git.sh"
bash "$kit/install.sh" --check "$run/fresh" > "$run/second-preview.log"
for rel in $expected; do grep -q "^IDENTICAL $rel$" "$run/second-preview.log"; done
[ ! -x "$run/fresh/.agents/hooks/guard-collaborative-git.sh" ]
bash "$kit/install.sh" "$run/fresh" > "$run/reinstall.log"
[ -x "$run/fresh/.agents/hooks/guard-collaborative-git.sh" ]
[ ! -x "$run/fresh/.agents/hooks/local.sh" ]
[ "$(< "$run/fresh/local.txt")" = 'local overlay' ]

target conflict
mkdir -p "$run/conflict/.claude"
printf 'local settings\n' > "$run/conflict/.claude/settings.json"
reject --check "$run/conflict"
grep -q '^CONFLICT .claude/settings.json ' "$run/rejection.log"
reject "$run/conflict"
[ ! -e "$run/conflict/AGENTS.md" ] && [ ! -e "$run/conflict/.agents" ]
[ "$(cat "$run/conflict/.claude/settings.json")" = 'local settings' ]

target gitignore-conflict
printf 'local ignore rule\n' > "$run/gitignore-conflict/.gitignore"
reject --check "$run/gitignore-conflict"
grep -q '^CONFLICT .gitignore ' "$run/rejection.log"
reject "$run/gitignore-conflict"
[ ! -e "$run/gitignore-conflict/AGENTS.md" ] && [ ! -e "$run/gitignore-conflict/.agents" ]
[ "$(cat "$run/gitignore-conflict/.gitignore")" = 'local ignore rule' ]

target parent-link
mkdir -p "$run/outside"
ln -s "$run/outside" "$run/parent-link/.agents"
reject "$run/parent-link"
[ ! -e "$run/outside/hooks" ] && [ ! -e "$run/parent-link/AGENTS.md" ]

target file-link
mkdir -p "$run/file-link/.claude"
printf 'outside content\n' > "$run/outside/settings.json"
ln -s "$run/outside/settings.json" "$run/file-link/.claude/settings.json"
reject "$run/file-link"
[ ! -e "$run/file-link/AGENTS.md" ]
[ "$(cat "$run/outside/settings.json")" = 'outside content' ]

target dangling
mkdir -p "$run/dangling/.claude/hooks"
ln -s "$run/absent" "$run/dangling/.claude/hooks/guard-collaborative-git.sh"
reject "$run/dangling"
[ -L "$run/dangling/.claude/hooks/guard-collaborative-git.sh" ]
[ ! -e "$run/dangling/AGENTS.md" ]

target type-conflict
mkdir -p "$run/type-conflict/AGENTS.md"
reject "$run/type-conflict"
[ ! -e "$run/type-conflict/.agents" ]

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
[ ! -e "$run/missing-jq/AGENTS.md" ] && [ ! -e "$run/missing-jq/.agents" ]
echo "PASS: live payload, preview states, self-check, idempotence, conflict/type/symlink gates, arguments and prerequisites"
echo "Retained fixture evidence: $run"
