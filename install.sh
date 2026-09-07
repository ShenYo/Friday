#!/usr/bin/env bash
# Install the agent-management payload into a target repository, then verify it.
#
#   ~/Friday/install.sh [target-repo-path]     (default: current directory)
#
# Copies payload/ over the target, wires the Claude hook symlink, and runs the
# payload's own self-check. Idempotent: re-run it to repair a partial install
# or to pick up a newer payload.
#
# What it does NOT do: fill in the per-project layer (the AGENTS.md routing
# table, the domain glossary, the issue-tracker choice). Those need answers
# only the project owner has — see README.md.
set -euo pipefail

KIT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PAYLOAD="$KIT_ROOT/payload"
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

echo "Installing into $TARGET"
echo ""

# --- Copy the payload -------------------------------------------------------
# Existing files are overwritten: the payload is the source of truth for what
# it ships. Anything the project added alongside it is left alone.
copied=0
while IFS= read -r src; do
  rel=${src#"$PAYLOAD"/}
  dest="$TARGET/$rel"
  mkdir -p "$(dirname "$dest")"
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then continue; fi
  cp "$src" "$dest"
  echo "  wrote  $rel"
  copied=$((copied + 1))
done < <(find "$PAYLOAD" -type f)

[ "$copied" -eq 0 ] && echo "  (payload already current)"

chmod +x "$TARGET/.agents/hooks/"*.sh

# --- Wire the Claude hook ---------------------------------------------------
# .claude/hooks/ must hold a link, not a copy: settings.json points at that
# path, and a copy would silently go stale when the payload guard changes.
mkdir -p "$TARGET/.claude/hooks"
ln -sfn ../../.agents/hooks/guard-collaborative-git.sh \
        "$TARGET/.claude/hooks/guard-collaborative-git.sh"
echo "  linked .claude/hooks/guard-collaborative-git.sh"

# --- Verify -----------------------------------------------------------------
# The payload ships its own check, which feeds the guard a force-push payload
# and fails if it is not blocked. Running it here means a bad install is caught
# now rather than the first time someone relies on the boundary.
echo ""
# jq only: the self-check parses settings.json with it. It deliberately does
# not need ripgrep — see the note in check-collaborative-git.sh.
command -v jq >/dev/null || {
  echo "error: 'jq' is required by the self-check but is not installed." >&2
  exit 1
}

if (cd "$TARGET" && bash .agents/hooks/check-collaborative-git.sh); then
  echo "self-check passed: the safety boundary is installed and blocking."
else
  echo "self-check FAILED — the boundary is not trustworthy in $TARGET." >&2
  exit 1
fi

echo ""
echo "Next: the per-project layer is not installed. See README.md — you need an"
echo ".agents/AGENTS.md routing table before agents will read any of this."
