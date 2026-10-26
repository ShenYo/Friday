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

# A linked worktree has a .git file, not a directory, and a git dir that is not
# the repository's common dir (a submodule has the file too, but not that).
# core.hooksPath is shared by every worktree of a repository, so wiring it from
# one would leave the others running no hooks. Refuse before anything is written.
linked_worktree=false
if [ -f "$TARGET/.git" ]; then
  git_dir=$(cd "$TARGET" && cd "$(git rev-parse --git-dir)" && pwd -P) || git_dir=
  common_dir=$(cd "$TARGET" && cd "$(git rev-parse --git-common-dir)" && pwd -P) || common_dir=
  if [ -n "$git_dir" ] && [ -n "$common_dir" ] && [ "$git_dir" != "$common_dir" ]; then
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

# The runtime links setup.sh makes. Listed here too so the preflight refuses
# whatever stands in their way before anything is written.
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
# setup.sh links every Skill as .claude/skills/<name>, for Claude Code, and
# stops on what stands in the way. The same rules are applied here to the Skills
# as they will be once the copy is done -- the target's own plus the payload's --
# so a target setup would then stop on is refused now, before anything is
# written. A Skill is a directory holding SKILL.md at depth 1 or 2, named by its
# `name:` frontmatter, else its directory; a symlinked directory is not one.
skill_name() {
  awk '
    NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
    /^---[[:space:]]*$/ { exit }
    /^name:/ {
      v = $0; sub(/^name:[[:space:]]*/, "", v); sub(/\r$/, "", v)
      q = substr(v, 1, 1)
      if (q == "\"" || q == "\047") {
        i = index(substr(v, 2), q)
        if (i > 0) { print substr(v, 2, i - 1); exit }
      }
      sub(/[[:space:]]+#.*$/, "", v); sub(/[[:space:]]+$/, "", v)
      print v; exit
    }
  ' "$1"
}
skill_rels=()
skill_names=()
collect_skills() { # <skills root> <skip rels the payload replaces: yes|no>
  local root=$1 skip=$2 dir rel name r shipped
  [ -d "$root" ] || return 0
  while IFS= read -r dir; do
    rel=${dir#"$root"/}
    shipped=no
    if [ "$skip" = yes ]; then
      for r in "${skill_rels[@]}"; do [ "$r" = "$rel" ] && shipped=yes; done
    fi
    [ "$shipped" = no ] || continue
    name=$(skill_name "$dir/SKILL.md")
    [ -n "$name" ] || name=${rel##*/}
    skill_rels+=("$rel")
    skill_names+=("$name")
  done < <(find -H "$root" -mindepth 1 -maxdepth 2 -type d -exec test -f '{}/SKILL.md' \; -print | sort)
}
collect_skills "$PAYLOAD/.agents/skills" no
collect_skills "$TARGET/.agents/skills" yes

# Whether a path (relative to the repository root) exists once the copy is
# done: already there, or a file or directory the payload is about to put there.
will_exist() {
  [ -e "$TARGET/$1" ] || [ -e "$PAYLOAD/$1" ]
}
# The path a link in .claude/skills/ names, resolved without touching the disk
# beyond that, so the answer can be about files that do not exist yet.
link_resolves() { # <link text>
  local text=$1 part resolved='.claude/skills'
  case $text in
    "$TARGET"/*) will_exist "${text#"$TARGET"/}"; return ;;
    /*) [ -e "$text" ]; return ;;
  esac
  local -a parts
  IFS=/ read -r -a parts <<< "$text"
  for part in "${parts[@]}"; do
    case $part in
      ''|.) ;;
      ..) case $resolved in
            */*) resolved=${resolved%/*} ;;
            ?*) resolved= ;;
            *) return 1 ;;
          esac ;;
      *) resolved=${resolved:+$resolved/}$part ;;
    esac
  done
  will_exist "$resolved"
}

check_skill_link() { # <link name> <skill rel>
  local rel=.claude/skills/$1 want=../../.agents/skills/$2 current=$TARGET part have
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
  current=$TARGET/$rel
  if [ -L "$current" ]; then
    have=$(readlink "$current")
    if [ "$have" = "$want" ]; then
      echo "IDENTICAL $rel"
    elif link_resolves "$have"; then
      echo "CONFLICT $rel (points to $have, expected $want)"
      conflicts=1
    elif [[ $have == ../../.agents/skills/* ]]; then
      echo "NEW $rel (replaces a dangling link to $have)"
    else
      echo "CONFLICT $rel (a dangling link to $have, which is not one setup wrote; expected $want)"
      conflicts=1
    fi
  elif [ -e "$current" ]; then
    echo "CONFLICT $rel (exists and is not a symlink)"
    conflicts=1
  else
    echo "NEW $rel"
  fi
}
seen_names=$'\n'
for ((k=0; k<${#skill_rels[@]}; k++)); do
  name=${skill_names[k]}
  case $seen_names in *$'\n'"$name"$'\n'*) continue ;; esac
  seen_names=$seen_names$name$'\n'
  case $name in
    */*|.|..) echo "CONFLICT .agents/skills/${skill_rels[k]} (its name '$name' is not usable as a link name)"; conflicts=1; continue ;;
  esac
  owners=; count=0
  for ((m=0; m<${#skill_rels[@]}; m++)); do
    if [ "${skill_names[m]}" = "$name" ]; then
      owners="${owners:+$owners, }.agents/skills/${skill_rels[m]}"
      count=$((count + 1))
    fi
  done
  if [ "$count" -gt 1 ]; then
    echo "CONFLICT .claude/skills/$name (declared by more than one Skill: $owners; linked for none)"
    conflicts=1
    continue
  fi
  check_skill_link "$name" "${skill_rels[k]}"
done
if [ -f "$TARGET/.codex/config.toml" ] \
  && grep -Eq '^[[:space:]]*\[\[hooks\.' "$TARGET/.codex/config.toml"; then
  echo "CONFLICT .codex/config.toml (inline hooks duplicate hooks.json)"
  conflicts=1
fi
# Wiring core.hooksPath replaces .git/hooks wholesale, so a target already
# using husky or another manager needs a deliberate decision rather than a
# silent override. Checked here with every other conflict, before anything is
# written, so --check reports it and a refusal leaves the target untouched. The
# effective value counts, from whichever scope it comes (setup.sh does the same).
existing_hooks_path=$(git -C "$TARGET" config --get core.hooksPath 2>/dev/null || true)
if [ -n "$existing_hooks_path" ] && [ "$existing_hooks_path" != .agents/githooks ]; then
  echo "CONFLICT core.hooksPath (already set to '$existing_hooks_path'; reconcile it with .agents/githooks)"
  conflicts=1
fi
if [ -d "$TARGET/.git/hooks" ] \
  && [ -n "$(find "$TARGET/.git/hooks" \( -type f -o -type l \) ! -name '*.sample' -print -quit 2>/dev/null)" ]; then
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
    .agents/bin/*.sh) chmod +x "$TARGET/$rel" ;;
    .agents/hooks/*.sh) chmod +x "$TARGET/$rel" ;;
    .agents/githooks/*) chmod +x "$TARGET/$rel" ;;
  esac
done

# --- Wire the clone ---------------------------------------------------------
# core.hooksPath is per-clone config, not tracked, and the runtime hook paths
# must hold links, not copies, so both adapters share the one reviewed guard.
# That wiring, and the Skill links and root pointers, live in the one script
# the payload ships, so a later clone does it the same way: this runs the copy
# just installed. The preflight above has already refused a target where it
# would override another hook manager, so a conflict here is unexpected.
setup_status=0
setup_out=$(cd "$TARGET" && bash .agents/bin/setup.sh 2>&1) || setup_status=$?
printf '%s\n' "$setup_out" | sed 's/^/  /'
if [ "$setup_status" -ne 0 ]; then
  echo "error: .agents/bin/setup.sh reported a problem in $TARGET (exit $setup_status); see above." >&2
  exit 1
fi

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
