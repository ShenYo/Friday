#!/usr/bin/env bash
# Install the agent-management payload into a target repository, then verify it.
#
#   ~/.Friday/install.sh [target-repo-path]    (default: current directory)
#
# --check previews without writing. Installation adds missing files, preserves
# identical files, and refuses conflicts before making any target changes.
#
# The payload is an explicit, closed baseline. Consumer repositories may add
# overlays after installation; future payload files are not installed until
# they are deliberately added to bin/managed-core.txt.
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

# A linked worktree has a .git file, not a directory. core.hooksPath is shared
# by every worktree of a repository, so wiring it from one would leave the
# others running no hooks. Refuse before anything is written.
linked_worktree=false
if [ -f "$TARGET/.git" ]; then
  linked_worktree=true
elif [ -e "$TARGET/.git" ]; then
  git_dir=$(git -C "$TARGET" rev-parse --absolute-git-dir 2>/dev/null) || git_dir=
  common_dir=$(git -C "$TARGET" rev-parse --git-common-dir 2>/dev/null) || common_dir=
  case "$common_dir" in
    "") ;;
    /*) ;;
    *) common_dir="$TARGET/$common_dir" ;;
  esac
  if [ -n "$git_dir" ] && [ -n "$common_dir" ] \
     && [ "$(cd "$git_dir" && pwd -P)" != "$(cd "$common_dir" && pwd -P)" ]; then
    linked_worktree=true
  fi
fi
if [ "$linked_worktree" = true ]; then
  echo "error: $TARGET is a linked worktree." >&2
  echo "       core.hooksPath is shared by every worktree of a repository, so wiring" >&2
  echo "       it here would leave the others running no hooks. Install into the main" >&2
  echo "       worktree, then check this one out from it." >&2
  exit 1
fi

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
# The allowlist is bin/managed-core.txt: every entry, managed and
# consumer-owned (`!`) alike. It used to be written out here as well, a second
# copy of one list that could disagree with the first. It is still closed --
# nothing is discovered from payload/ -- and the inventory check below refuses
# a payload file the list does not name, before the target is touched.
LIST="$KIT_ROOT/bin/managed-core.txt"
[ -f "$LIST" ] || { echo "error: $LIST missing — is this the Friday repo?" >&2; exit 1; }
files=()
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%%#*}
  line=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -n "$line" ] || continue
  files+=("${line#!}")
done < "$LIST"
[ ${#files[@]} -gt 0 ] || { echo "error: $LIST names no files" >&2; exit 1; }

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
# Wiring core.hooksPath replaces .git/hooks wholesale, so a target already
# using husky or another manager needs a deliberate decision rather than a
# silent override. Checked here with every other conflict, before anything is
# written, so --check reports it and a refusal leaves the target untouched.
existing_hooks_path=$(git -C "$TARGET" config --local core.hooksPath 2>/dev/null || true)
if [ -n "$existing_hooks_path" ] && [ "$existing_hooks_path" != .agents/githooks ]; then
  echo "CONFLICT core.hooksPath (already set to '$existing_hooks_path'; reconcile it with .agents/githooks)"
  conflicts=1
fi
if [ -d "$TARGET/.git/hooks" ] \
  && [ -n "$(find "$TARGET/.git/hooks" -type f ! -name '*.sample' -print -quit 2>/dev/null)" ]; then
  echo "CONFLICT .git/hooks (holds hooks that core.hooksPath would bypass; move or remove them deliberately)"
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
  case "$rel" in
    .agents/hooks/*.sh) chmod +x "$TARGET/$rel" ;;
    .agents/githooks/*) chmod +x "$TARGET/$rel" ;;
  esac
done

# --- Wire the commit-time hooks ---------------------------------------------
# core.hooksPath is per-clone config, not tracked, so it has to be set here.
# These hooks are where the secret scan and the message checks actually run: a
# runtime tool hook cannot see a staged diff, and `git commit -F -` hides the
# message from it entirely. The preflight above has already refused a target
# where this would override another hook manager.
git -C "$TARGET" config core.hooksPath .agents/githooks
echo "  wired  core.hooksPath -> .agents/githooks"

# --- Wire runtime hooks -----------------------------------------------------
# Runtime hook paths must hold links, not copies, so both adapters share the
# reviewed guard implementation.
for link in "${links[@]}"; do
  rel=${link%%:*}
  mkdir -p "$(dirname "$TARGET/$rel")"
  if [ ! -L "$TARGET/$rel" ]; then ln -s "${link#*:}" "$TARGET/$rel"; fi
  echo "  linked $rel"
done

# --- Record the position ------------------------------------------------------
# The lock is what lets a consumer answer "which Friday am I on, and has
# anything moved since?" without a human comparing files by hand. Written
# last, so it records the state the install actually produced.
bash "$KIT_ROOT/bin/friday-lock" write "$TARGET" | sed 's/^/  /'

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
