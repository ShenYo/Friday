#!/usr/bin/env bash
# Finish a consumer's per-clone setup. Run it after cloning, and again after
# a Skill is added, removed or renamed.
#
#   bash .agents/bin/setup.sh [--check]
#
# Install runs once, on one machine. What it wires lives outside the tracked
# files -- core.hooksPath is local Git config -- or is a pointer a clone may
# lack, so a fresh clone has none of it. This script does that wiring from
# the clone itself, with no copy of Friday at hand:
#
#   1. core.hooksPath -> .agents/githooks, so the Git hooks run
#   2. the Claude and Codex runtime hook links to the shared guard
#   3. the root AGENTS.md and CLAUDE.md pointers, when missing
#   4. .claude/skills/<name> links to .agents/skills, for Claude Code
#
# It is idempotent, and it only ever adds: nothing it did not create is
# overwritten, moved or deleted. Whatever stands in the way is reported as
# CONFLICT and left alone, and the rest still runs. The one thing it replaces
# is a dangling Skill link of the form it writes itself, one that points into
# ../../.agents/skills/ -- a Skill that was moved or renamed. Any other
# dangling link is not setup's to remove.
#
# --check reports what a run would do and writes nothing. It exits 0 when
# nothing would change and there is no conflict, and 1 otherwise; a normal run
# exits 1 when it reported a conflict. STALE and SKIPPED entries are only
# reported; they do not change the exit status.
set -uo pipefail

check_only=false
if [ "${1:-}" = "--check" ]; then check_only=true; shift; fi
if [ "$#" -gt 0 ]; then
  echo "usage: bash .agents/bin/setup.sh [--check]" >&2
  exit 2
fi

# The repository is whichever one the working directory is in, as with git.
root=$(git rev-parse --show-toplevel 2>/dev/null) || root=
if [ -z "$root" ] || [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != true ]; then
  echo "error: not inside a Git work tree; run this from inside the consumer repository." >&2
  exit 1
fi
# A linked worktree has a git dir that is not the repository's common dir (a
# submodule's is the same as its common dir). core.hooksPath is shared by every
# worktree, so wiring it from one would leave the others running no hooks.
git_dir=$(cd "$(git rev-parse --git-dir)" && pwd -P) || git_dir=
common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd -P) || common_dir=
if [ -z "$git_dir" ] || [ -z "$common_dir" ]; then
  echo "error: cannot resolve the git directory of $root." >&2
  exit 1
fi
if [ "$git_dir" != "$common_dir" ]; then
  echo "error: $root is a linked worktree." >&2
  echo "       core.hooksPath is shared by every worktree of a repository, so wiring" >&2
  echo "       it here would leave the others running no hooks. Run this in the main" >&2
  echo "       worktree." >&2
  exit 1
fi
cd "$root" || exit 1

if "$check_only"; then echo "check: $root (nothing will be written)"; else echo "setup: $root"; fi

changes=0; oks=0; conflicts=0; stales=0
ok() { echo "OK       $*"; oks=$((oks + 1)); }
conflict() { echo "CONFLICT $1 ($2)"; conflicts=$((conflicts + 1)); }
stale() { echo "STALE    $1 ($2)"; stales=$((stales + 1)); }
# Count and announce a change; true when it should really be made.
change() {
  changes=$((changes + 1))
  if "$check_only"; then echo "WOULD CREATE $*"; return 1; fi
  echo "CREATED  $*"
}

# Writing through a symlinked or non-directory ancestor would land outside the
# repository, or fail; refuse the same way install.sh does.
unsafe_parent() {
  local rel=$1 cur='' part rest=${1%/*}
  [ "$rest" != "$1" ] || return 1
  while [ -n "$rest" ]; do
    part=${rest%%/*}
    if [ "$part" = "$rest" ]; then rest=''; else rest=${rest#*/}; fi
    cur=${cur:+$cur/}$part
    if [ -L "$cur" ] || { [ -e "$cur" ] && [ ! -d "$cur" ]; }; then
      conflict "$rel" "unsafe parent: $cur"
      return 0
    fi
  done
  return 1
}

# ensure_link <path> <target> <replace-dangling: yes|no>
ensure_link() {
  local path=$1 want=$2 replace=$3 have
  unsafe_parent "$path" && return
  if [ -L "$path" ]; then
    have=$(readlink "$path")
    if [ "$have" = "$want" ]; then
      if [ -e "$path" ]; then ok "$path"; else conflict "$path" "dangling: $want does not exist"; fi
    elif [ ! -e "$path" ] && [ "$replace" = yes ] && [[ $have == ../../.agents/skills/* ]]; then
      if change "$path -> $want (replacing a dangling link to $have)"; then
        if ! { rm "$path" && ln -s "$want" "$path"; }; then conflict "$path" "could not replace the link"; fi
      fi
    else
      if [ -e "$path" ]; then
        conflict "$path" "points to $have, expected $want"
      else
        conflict "$path" "a dangling link to $have, which is not one setup wrote; expected $want"
      fi
    fi
  elif [ -e "$path" ]; then
    conflict "$path" "exists and is not a symlink"
  elif change "$path -> $want"; then
    if ! { mkdir -p "${path%/*}" && ln -s "$want" "$path"; }; then conflict "$path" "could not create the link"; fi
  fi
}

# --- 1. Git hooks -------------------------------------------------------------
# core.hooksPath is where the secret scan and the message checks run. It is
# per-clone config, so a fresh clone has it unset. The effective value counts,
# from whichever scope it comes (global config included): a value that is not
# ours is another hook manager's, and setting it locally would override it.
wired=false
if current=$(git config --get core.hooksPath); then
  if [ "$current" = .agents/githooks ]; then
    ok "core.hooksPath -> .agents/githooks"; wired=true
  else
    conflict core.hooksPath "set to '$current'; reconcile it with .agents/githooks"
  fi
elif change "core.hooksPath -> .agents/githooks"; then
  if git config --local core.hooksPath .agents/githooks; then wired=true; else conflict core.hooksPath "could not set it"; fi
else
  wired=true
fi
# Pointing core.hooksPath elsewhere bypasses .git/hooks wholesale.
if "$wired" && [ -d "$common_dir/hooks" ] \
  && [ -n "$(find "$common_dir/hooks" \( -type f -o -type l \) ! -name '*.sample' -print -quit 2>/dev/null)" ]; then
  conflict .git/hooks "holds hooks that core.hooksPath bypasses; move or remove them deliberately"
fi
# git skips a hook that is not executable, and the commit goes through.
hooks_ok=true
for h in pre-commit commit-msg pre-push; do
  if [ ! -f ".agents/githooks/$h" ]; then
    conflict ".agents/githooks/$h" "missing"; hooks_ok=false
  elif [ ! -x ".agents/githooks/$h" ]; then
    conflict ".agents/githooks/$h" "not executable; git would skip it, run chmod +x"; hooks_ok=false
  fi
done
if "$hooks_ok"; then ok ".agents/githooks (pre-commit commit-msg pre-push are executable)"; fi

# --- 2. Runtime hook links ----------------------------------------------------
# Links, not copies, so both adapters share the one reviewed guard. A link to a
# guard that is not there guards nothing, so that is reported rather than made.
guard=.agents/hooks/guard-collaborative-git.sh
for rel in .claude/hooks/guard-collaborative-git.sh .codex/hooks/guard-collaborative-git.sh; do
  if [ ! -L "$rel" ] && [ ! -e "$rel" ] && [ ! -f "$guard" ]; then
    conflict "$rel" "cannot link to $guard, which is missing"
  else
    ensure_link "$rel" "../../$guard" no
  fi
done

# --- 3. Root pointers ---------------------------------------------------------
# Seeds, owned by the consumer from the moment they exist: created when missing,
# never read or compared when present. These texts are copies of
# payload/AGENTS.md and payload/CLAUDE.md in Friday, kept equal by a test.
seed_agents() {
  cat <<'SEED'
# Agent Instructions

Read [`.agents/AGENTS.md`](.agents/AGENTS.md) before working in this
repository. It is the shared agent baseline installed by Friday.
SEED
}
seed_claude() {
  cat <<'SEED'
# Claude Instructions

Source of truth: [`.agents/AGENTS.md`](.agents/AGENTS.md) — auto-imported below.

@.agents/AGENTS.md
SEED
}
for f in AGENTS.md CLAUDE.md; do
  if [ -L "$f" ] && [ ! -e "$f" ]; then
    conflict "$f" "dangling symlink"
  elif [ -f "$f" ]; then
    ok "$f"
  elif [ -e "$f" ]; then
    conflict "$f" "exists and is not a file"
  elif change "$f (from the seed)"; then
    if [ "$f" = AGENTS.md ]; then seed_agents; else seed_claude; fi > "$f" \
      || conflict "$f" "could not write it"
  fi
done

# --- 4. Claude Code Skill bridge ----------------------------------------------
# Claude Code reads .claude/skills/<name>; the Skills live in .agents/skills.
# A Skill is a directory holding SKILL.md at depth 1 or 2, so a grouping
# directory such as git/ is never linked itself. It is linked under its own
# `name:` frontmatter, because that is what the tool matches on (git/commit
# declares `name: git-commit`), falling back to the directory name.
skill_name() {
  awk '
    NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
    /^---[[:space:]]*$/ { exit }
    /^name:/ {
      v = $0; sub(/^name:[[:space:]]*/, "", v); sub(/\r$/, "", v)
      q = substr(v, 1, 1)
      if (q == "\"" || q == "\047") {
        # Quoted: the name is what is inside; a # in there is part of it.
        i = index(substr(v, 2), q)
        if (i > 0) { print substr(v, 2, i - 1); exit }
      }
      # Unquoted: a # after whitespace starts a YAML comment.
      sub(/[[:space:]]+#.*$/, "", v); sub(/[[:space:]]+$/, "", v)
      print v; exit
    }
  ' "$1"
}
tab=$(printf '\t')
skills=''
if [ -d .agents/skills ]; then
  while IFS= read -r dir; do
    rel=${dir#.agents/skills/}
    name=$(skill_name "$dir/SKILL.md")
    [ -n "$name" ] || name=${rel##*/}
    skills="$skills$rel$tab$name
"
  done < <(find -H .agents/skills -mindepth 1 -maxdepth 2 -type d -exec test -f '{}/SKILL.md' \; -print | sort)

  # A Skill directory that is a symlink is not followed. Inside .agents/skills
  # it is an alias of a Skill already linked under its own path (git-commit ->
  # git/commit), so there is nothing to say; outside it, the Skill's content is
  # not in .agents/skills at all, so say it was passed over.
  skills_root=$(cd .agents/skills && pwd -P)
  while IFS= read -r link; do
    [ -d "$link" ] && [ -f "$link/SKILL.md" ] || continue
    real=$(cd "$link" && pwd -P) || continue
    case $real in "$skills_root"/*) continue ;; esac
    echo "SKIPPED  $link (a symlink outside .agents/skills; not followed)"
  done < <(find -H .agents/skills -mindepth 1 -maxdepth 2 -type l | sort)
fi

names=''
seen=''
while IFS="$tab" read -r rel name; do
  [ -n "$rel" ] || continue
  case $name in
    */*|.|..) conflict ".agents/skills/$rel" "its name '$name' is not usable as a link name"; continue ;;
  esac
  if printf '%s' "$seen" | grep -Fxq -- "$name"; then continue; fi
  seen="$seen$name
"
  # The name goes in through the environment: awk -v would read a backslash in
  # it as an escape and no longer match the name it was given.
  paths=$(printf '%s' "$skills" | SKILL_NAME=$name awk -F'\t' '$2 == ENVIRON["SKILL_NAME"] { printf "%s.agents/skills/%s", s, $1; s = ", " }')
  if [ "$(printf '%s' "$skills" | SKILL_NAME=$name awk -F'\t' '$2 == ENVIRON["SKILL_NAME"]' | wc -l | tr -d ' ')" -gt 1 ]; then
    names="$names$name
"
    conflict ".claude/skills/$name" "declared by more than one Skill: $paths; linked for none"
    continue
  fi
  names="$names$name
"
  ensure_link ".claude/skills/$name" "../../.agents/skills/$rel" yes
done <<EOF_SKILLS
$skills
EOF_SKILLS

# Entries a person may want to remove: reported, never touched. The glob skips
# names starting with a dot (.DS_Store and the like): they are not Skills.
if [ -d .claude/skills ] && [ ! -L .claude/skills ]; then
  for entry in .claude/skills/*; do
    [ -L "$entry" ] || [ -e "$entry" ] || continue
    name=${entry##*/}
    if printf '%s' "$names" | grep -Fxq -- "$name"; then continue; fi
    if [ -L "$entry" ] && [ ! -e "$entry" ]; then
      stale "$entry" "dangling link to $(readlink "$entry")"
    else
      stale "$entry" "matches no Skill under .agents/skills; remove it if it is not needed"
    fi
  done
fi

# --- 5. Summary ---------------------------------------------------------------
if "$check_only"; then verb='would create'; else verb=created; fi
line="$verb $changes, ok $oks, conflicts $conflicts, stale $stales"
[ "$changes" -eq 0 ] && line="$line -- nothing to change"
echo "$line"

if [ "$conflicts" -gt 0 ]; then exit 1; fi
if "$check_only" && [ "$changes" -gt 0 ]; then exit 1; fi
exit 0
