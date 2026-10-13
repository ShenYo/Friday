#!/usr/bin/env bash
# Install the agent-management payload into a target repository, then verify it.
#
#   ~/Friday/install.sh [target-repo-path]     (default: current directory)
#
# --check previews without writing. Installation adds missing files, preserves
# identical files, and refuses conflicts before making any target changes.
#
# The payload is an explicit, closed baseline. Consumer repositories may add
# overlays after installation; future payload files are not installed until
# they are deliberately added to the allowlist below.
set -euo pipefail

KIT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PAYLOAD="$KIT_ROOT/payload"
check_only=false
if [ "${1:-}" = "--check" ]; then check_only=true; shift; fi
if [ "$#" -gt 1 ] || [[ "${1:-}" = -* ]]; then
  echo "usage: $0 [--check] [target-repo-path]" >&2
  exit 2
fi
TARGET=$(cd "${1:-.}" && pwd)

[ -d "$PAYLOAD" ] || { echo "error: $PAYLOAD missing — is this the Friday repo?" >&2; exit 1; }

if [ ! -d "$TARGET/.git" ]; then
  echo "error: $TARGET is not a git repository." >&2
  echo "       The safety boundary guards Git operations, so it has nothing to" >&2
  echo "       guard here. Run 'git init' first if that is what you meant." >&2
  exit 1
fi

if [ "$TARGET" = "$KIT_ROOT" ]; then
  echo "error: refusing to install the kit into itself." >&2
  exit 1
fi

# Check prerequisites before copying, not after a partially completed install.
command -v jq >/dev/null || { echo "error: 'jq' is required." >&2; exit 1; }
# This intentionally does not discover payload files. Friday's MVP installs a
# reviewed, closed baseline; adding a payload file without reconciling this
# list fails before the target is touched.
files=(
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
  .claude/settings.json
  .codex/hooks.json
)

contains_file() {
  local candidate=$1 rel
  for rel in "${files[@]}"; do
    [ "$rel" = "$candidate" ] && return 0
  done
  return 1
}

for rel in "${files[@]}"; do
  src="$PAYLOAD/$rel"
  [ -f "$src" ] && [ ! -L "$src" ] || {
    echo "error: declared payload file is missing or unsafe: $rel" >&2
    exit 1
  }
done

actual_count=0
while IFS= read -r src; do
  rel=${src#"$PAYLOAD"/}
  contains_file "$rel" || {
    echo "error: undeclared payload file: $rel" >&2
    exit 1
  }
  actual_count=$((actual_count + 1))
done < <(find "$PAYLOAD" \( -type f -o -type l \) -print)
[ "$actual_count" -eq "${#files[@]}" ] || {
  echo "error: payload inventory does not match the install allowlist." >&2
  exit 1
}

links=(
  '.claude/hooks/guard-collaborative-git.sh:../../.agents/hooks/guard-collaborative-git.sh'
  '.codex/hooks/guard-collaborative-git.sh:../../.agents/hooks/guard-collaborative-git.sh'
)
conflicts=0
check_destination() {
  local rel=$1 kind=$2 link_target=${3:-} current=$TARGET part dest
  local -a components
  IFS=/ read -r -a components <<< "$rel"
  for ((i=0; i<${#components[@]}-1; i++)); do
    part=${components[i]}
    current="$current/$part"
    if [ -L "$current" ] || { [ -e "$current" ] && [ ! -d "$current" ]; }; then
      echo "CONFLICT $rel (unsafe parent: $current)"
      conflicts=1
      return
    fi
  done
  dest="$TARGET/$rel"
  if [ "$kind" = link ] && [ -L "$dest" ] && [ "$(readlink "$dest")" = "$link_target" ]; then
    echo "IDENTICAL $rel"
  elif [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then
    echo "CONFLICT $rel (unexpected file type or symlink)"
    conflicts=1
  elif [ -e "$dest" ]; then
    if [ "$kind" = file ] && cmp -s "$PAYLOAD/$rel" "$dest"; then
      echo "IDENTICAL $rel"
    else
      echo "CONFLICT $rel (existing content)"
      conflicts=1
    fi
  else
    echo "NEW $rel"
  fi
}

for rel in "${files[@]}"; do check_destination "$rel" file; done
for link in "${links[@]}"; do
  rel=${link%%:*}
  check_destination "$rel" link "${link#*:}"
done
if [ -f "$TARGET/.codex/config.toml" ] \
  && grep -Eq '^[[:space:]]*\[\[hooks\.' "$TARGET/.codex/config.toml"; then
  echo "CONFLICT .codex/config.toml (inline hooks duplicate hooks.json)"
  conflicts=1
fi
if [ "$conflicts" -ne 0 ]; then
  echo "error: resolve conflicts in a reviewed change; nothing was written." >&2
  exit 1
fi
if "$check_only"; then exit 0; fi

# Preflight prevents known conflicts, not concurrent changes or later I/O errors.
copied=0
for rel in "${files[@]}"; do
  src="$PAYLOAD/$rel"
  dest="$TARGET/$rel"
  mkdir -p "$(dirname "$dest")"
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then continue; fi
  cp "$src" "$dest"
  echo "  wrote  $rel"
  copied=$((copied + 1))
done

[ "$copied" -eq 0 ] && echo "  (payload already current)"

for rel in "${files[@]}"; do
  case "$rel" in .agents/hooks/*.sh) chmod +x "$TARGET/$rel" ;; esac
done

# --- Wire runtime hooks -----------------------------------------------------
# Runtime hook paths must hold links, not copies, so both adapters share the
# reviewed guard implementation.
for link in "${links[@]}"; do
  rel=${link%%:*}
  mkdir -p "$(dirname "$TARGET/$rel")"
  if [ ! -L "$TARGET/$rel" ]; then ln -s "${link#*:}" "$TARGET/$rel"; fi
  echo "  linked $rel"
done

# --- Verify -----------------------------------------------------------------
# The payload ships its own check, which feeds the guard a force-push payload
# and fails if it is not blocked. Running it here means a bad install is caught
# now rather than the first time someone relies on the boundary.
echo ""
# jq only: the self-check parses settings.json with it. It deliberately does
# not need ripgrep — see the note in check-collaborative-git.sh.
if (cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh); then
  echo "self-check passed: static declared hook wiring and direct guard probes passed; native Codex callback delivery, exit handling, handler order, and fail-closed behavior remain unverified."
else
  echo "self-check FAILED — the boundary is not trustworthy in $TARGET." >&2
  exit 1
fi

echo ""
echo "Next: add consumer-specific overlays only after reviewing this shared baseline."
