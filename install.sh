#!/usr/bin/env bash
# Install the agent-management payload into a target repository, then verify it.
#
#   ~/.Friday/install.sh [--check] [--release vX.Y.Z | --working-tree]
#                        [--managed-only] [target-repo-path]
#                                               (default target: current directory)
#
# By default this installs a release, never this checkout as it stands: the
# newest annotated tag vMAJOR.MINOR.PATCH, chosen and validated the way
# bin/friday-propagate does (on origin as the same tag object, reachable from
# main). The release's tree is exported to a temporary directory and its own
# install.sh does the work, so a checkout on a feature branch, or with
# uncommitted edits, cannot reach the target; the lock records the release.
#   --release vX.Y.Z   install that release instead of the newest
#   --working-tree     install this checkout as it is -- for developing Friday,
#                      not for a project; the lock names no tag unless the
#                      payload happens to match one
#   --managed-only     for a project that already has its own AGENTS.md,
#                      .gitignore and the like: copy only the managed core, leave
#                      every consumer-owned seed (the `!` entries of
#                      bin/managed-core.txt) alone and list each as SEED
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
# The interface this installer speaks. A release install reads this line from
# the exported copy to know whether it takes --as-release and --managed-only
# (2 and later) or is an older installer that installs its own tree under
# [--check] [target]. Raise it when the flags the release path passes change.
INSTALL_INTERFACE=2
# Exactly vMAJOR.MINOR.PATCH: a pre-release or a malformed name is no release.
RELEASE_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'
check_only=false
managed_only=false
working_tree=false
release_tag=
as_release=   # internal: set by the release install below on the exported copy
target_arg=
have_target=false
usage="usage: $0 [--check] [--release vX.Y.Z | --working-tree] [--managed-only] [target-repo-path]"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) check_only=true; shift ;;
    --managed-only) managed_only=true; shift ;;
    --working-tree) working_tree=true; shift ;;
    --release|--as-release)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then echo "$usage" >&2; exit 2; fi
      if [ "$1" = --release ]; then release_tag=$2; else as_release=$2; fi
      shift 2 ;;
    -*) echo "$usage" >&2; exit 2 ;;
    *)
      if "$have_target"; then echo "$usage" >&2; exit 2; fi
      target_arg=$1; have_target=true; shift ;;
  esac
done
if [ -n "$as_release" ]; then working_tree=true; fi
if [ -n "$release_tag" ] && [ "$working_tree" = true ]; then
  echo "error: --release and --working-tree are alternatives: a release is not this checkout." >&2
  echo "$usage" >&2
  exit 2
fi
TARGET=$(cd "${target_arg:-.}" && pwd)
# friday-lock records the index instead of the working tree when this is set,
# and a target's index holds none of what is about to be copied.
unset FRIDAY_LOCK_FROM_INDEX

# The allowlist is bin/managed-core.txt: every entry, managed and
# consumer-owned (`!`) alike. It is still closed -- nothing is discovered from
# payload/ -- and the inventory check below refuses a payload file the list
# does not name, before the target is touched.
managed_files=()
seed_files=()
read_list() { # <list file>: fills managed_files and seed_files
  local line
  managed_files=()
  seed_files=()
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}
    line=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -n "$line" ] || continue
    case "$line" in
      '!'*) seed_files+=("${line#!}") ;;
      *) managed_files+=("$line") ;;
    esac
  done < "$1"
}

# One line per consumer-owned file: a project that took only the managed core
# keeps its own, and this is what it has left to reconcile by hand.
# setup_makes_pointers: yes when the install will run a setup.sh that creates a
# missing AGENTS.md or CLAUDE.md, so the line for one can say what will happen.
setup_makes_pointers=no
report_seeds() { # uses PAYLOAD, TARGET, seed_files and setup_makes_pointers
  local rel dest
  for rel in ${seed_files+"${seed_files[@]}"}; do
    dest="$TARGET/$rel"
    if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then
      echo "SEED $rel (yours: a link or not a regular file; not touched)"
    elif [ ! -e "$dest" ]; then
      case $rel in
        AGENTS.md|CLAUDE.md)
          if [ "$setup_makes_pointers" = yes ]; then
            echo "SEED $rel (missing; setup.sh creates it from Friday's seed)"
          else
            echo "SEED $rel (missing; not created)"
          fi ;;
        *) echo "SEED $rel (missing; not created)" ;;
      esac
    elif cmp -s "$PAYLOAD/$rel" "$dest"; then
      echo "SEED $rel (identical to Friday's; not touched)"
    else
      echo "SEED $rel (yours; not touched)"
    fi
  done
}

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

# --- A release, by default -----------------------------------------------------
# What a project receives is a release, not whatever this checkout holds: the
# checkout is a development one, often on a feature branch or with uncommitted
# edits. The release is picked and checked the way bin/friday-propagate does it,
# its tree is exported, and that tree's own install.sh installs it, so the
# tooling that runs is the release's and not this checkout's. FRIDAY_KIT_ROOT and
# FRIDAY_TREE make the lock it writes read this repository at the release's
# commit, so the lock records that commit and tag. A release that predates
# this interface (v1.0.0, v1.0.1) has no --as-release and installs its own tree
# under its old one, which is exactly the release.
if [ "$working_tree" != true ]; then
  die() { echo "error: $*" >&2; exit 1; }
  command -v jq >/dev/null || die "'jq' is required."
  command -v git >/dev/null && command -v tar >/dev/null || die "'git' and 'tar' are required to install a release."
  git -C "$KIT_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || die "$KIT_ROOT is not a Git checkout, so it holds no release. Clone Friday (git clone https://github.com/ShenYo/Friday.git), or use --working-tree to install these files as they are."
  shallow=
  if [ "$(git -C "$KIT_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
    shallow=" $KIT_ROOT is a shallow clone, which can lack the history a release needs: run 'git -C $KIT_ROOT fetch --unshallow --tags'."
  fi
  no_release="Fetch the releases ('git -C $KIT_ROOT fetch --tags'), or cut one in $KIT_ROOT: an annotated tag on main, pushed to origin ('git tag -a vX.Y.Z -m <note> <commit>', then 'git push origin vX.Y.Z').$shallow Nothing was written."

  tag=$release_tag
  if [ -z "$tag" ]; then
    tag=$(git -C "$KIT_ROOT" tag -l 'v[0-9]*' --sort=-v:refname | grep -E "$RELEASE_RE" | sed -n 1p || true)
    [ -n "$tag" ] || die "Friday has no release tag (vMAJOR.MINOR.PATCH). $no_release"
  fi
  [[ $tag =~ $RELEASE_RE ]] || die "not a release tag (vMAJOR.MINOR.PATCH): $tag. Nothing was written."
  tree=$(git -C "$KIT_ROOT" rev-parse --verify -q "refs/tags/$tag^{commit}") \
    || die "no such release tag: $tag. $no_release"
  git -C "$KIT_ROOT" rev-parse --verify -q refs/heads/main >/dev/null \
    || die "$KIT_ROOT has no local main branch to check $tag against. Create it ('git -C $KIT_ROOT branch main origin/main'). Nothing was written."
  git -C "$KIT_ROOT" merge-base --is-ancestor "$tree" refs/heads/main 2>/dev/null \
    || die "$tag is not on Friday's main (its commit is not an ancestor of the main branch in $KIT_ROOT; if main is behind origin, pull it).$shallow Nothing was written."
  [ "$(git -C "$KIT_ROOT" cat-file -t "refs/tags/$tag" 2>/dev/null)" = tag ] \
    || die "$tag is not an annotated tag. Nothing was written."
  local_tag_obj=$(git -C "$KIT_ROOT" rev-parse --verify -q "refs/tags/$tag") || die "cannot read tag $tag. Nothing was written."
  # Read origin on its own: inside a pipeline a failure here would end the script
  # under set -e before any message, with git's status.
  origin_refs=$(git -C "$KIT_ROOT" ls-remote --tags origin "refs/tags/$tag" 2>&1) \
    || die "cannot read origin of $KIT_ROOT, so $tag cannot be checked against it (offline, no access, or no remote named origin): $origin_refs. Nothing was written."
  origin_tag_obj=$(printf '%s\n' "$origin_refs" | awk -v r="refs/tags/$tag" '$2 == r { print $1 }')
  [ -n "$origin_tag_obj" ] || die "$tag is not on origin (push it: git push origin $tag). Nothing was written."
  [ "$origin_tag_obj" = "$local_tag_obj" ] \
    || die "origin's $tag points at a different tag object than this checkout's. Nothing was written."

  released=$(mktemp -d "${TMPDIR:-/tmp}/friday-release.XXXXXX") || die "cannot create a temporary directory"
  trap 'rm -rf "$released"' EXIT
  git -C "$KIT_ROOT" archive --format=tar "$tree" | tar -x -C "$released" \
    || die "cannot export $tag from $KIT_ROOT"
  echo "release: $tag (commit $tree), installed by its own install.sh"

  export FRIDAY_KIT_ROOT=$KIT_ROOT FRIDAY_TREE=$tree FRIDAY_RELEASE=$tag
  args=()
  if "$check_only"; then args+=(--check); fi
  interface=$(sed -n 's/^INSTALL_INTERFACE=\([0-9][0-9]*\)$/\1/p' "$released/install.sh" | sed -n 1p)
  if [ "${interface:-1}" -ge 2 ]; then
    args+=(--as-release "$tag")
    if "$managed_only"; then args+=(--managed-only); fi
  elif "$managed_only"; then
    # The release predates --managed-only. Take the seeds out of the exported
    # copy -- from its list and from its payload -- so its old install.sh finds
    # only the managed core to install, and say what is left alone here.
    PAYLOAD="$released/payload"
    read_list "$released/bin/managed-core.txt"
    setup_makes_pointers=no   # the old installer never runs setup.sh
    report_seeds
    grep -v '^[[:space:]]*!' "$released/bin/managed-core.txt" > "$released/managed-only.txt"
    mv -f "$released/managed-only.txt" "$released/bin/managed-core.txt"
    for rel in ${seed_files+"${seed_files[@]}"}; do rm -f "$released/payload/$rel"; done
  fi
  status=0
  bash "$released/install.sh" ${args+"${args[@]}"} "$TARGET" || status=$?
  exit "$status"
fi
# From here on this checkout, or the exported copy of a release, installs itself.
# A caller's FRIDAY_* variables must not point the lock at anything else.
if [ -z "$as_release" ]; then
  unset FRIDAY_KIT_ROOT FRIDAY_TREE FRIDAY_RELEASE
  {
    echo "warning: --working-tree installs this checkout as it is, not a release."
    branch=$(git -C "$KIT_ROOT" symbolic-ref --short -q HEAD 2>/dev/null || echo "(not on a branch)")
    echo "         $KIT_ROOT is on $branch; the lock records a release tag only if the payload matches one."
    if [ -n "$(git -C "$KIT_ROOT" status --porcelain -- payload/ bin/managed-core.txt 2>/dev/null)" ]; then
      echo "         It has uncommitted changes under payload/ or to bin/managed-core.txt."
    fi
  } >&2
fi

[ -d "$PAYLOAD" ] || { echo "error: $PAYLOAD missing — is this the Friday repo?" >&2; exit 1; }

# --as-release says "this tree is that release". Nothing here takes its word for
# it: the variables must be the ones a release install sets, the tag must be the
# tree it names, and every file about to be copied must be that tree's bytes in
# the repository they point to. Otherwise a checkout with edits, run with the
# right variables, would install unreleased files and have the lock call them a
# release.
if [ -n "$as_release" ]; then
  refuse_as_release() { echo "error: --as-release: $*. Nothing was written." >&2; exit 1; }
  [ -n "${FRIDAY_KIT_ROOT:-}" ] && [ -n "${FRIDAY_TREE:-}" ] && [ -n "${FRIDAY_RELEASE:-}" ] \
    || refuse_as_release "FRIDAY_KIT_ROOT, FRIDAY_TREE and FRIDAY_RELEASE must be set; this flag is for the copy a release install exports, not for use by hand (use --working-tree)"
  [ "$as_release" = "$FRIDAY_RELEASE" ] \
    || refuse_as_release "$as_release is not FRIDAY_RELEASE ($FRIDAY_RELEASE)"
  want_commit=$(git -C "$FRIDAY_KIT_ROOT" rev-parse --verify -q "$FRIDAY_TREE^{commit}") \
    || refuse_as_release "FRIDAY_TREE ($FRIDAY_TREE) is not a commit in $FRIDAY_KIT_ROOT"
  tag_commit=$(git -C "$FRIDAY_KIT_ROOT" rev-parse --verify -q "refs/tags/$as_release^{commit}") \
    || refuse_as_release "$as_release is not a tag in $FRIDAY_KIT_ROOT"
  [ "$tag_commit" = "$want_commit" ] \
    || refuse_as_release "$as_release does not resolve to FRIDAY_TREE ($FRIDAY_TREE)"
  tree_count=0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    tree_count=$((tree_count + 1))
    { [ -f "$PAYLOAD/${rel#payload/}" ] && [ ! -L "$PAYLOAD/${rel#payload/}" ] \
      && git -C "$FRIDAY_KIT_ROOT" show "$want_commit:$rel" | cmp -s - "$PAYLOAD/${rel#payload/}"; } \
      || refuse_as_release "$rel does not match $as_release in $FRIDAY_KIT_ROOT"
  done < <(git -C "$FRIDAY_KIT_ROOT" -c core.quotePath=false ls-tree -r --name-only "$want_commit" -- payload/)
  [ "$(find "$PAYLOAD" \( -type f -o -type l \) -print | wc -l | tr -d ' ')" -eq "$tree_count" ] \
    || refuse_as_release "the payload holds files $as_release does not, so it does not match $as_release in $FRIDAY_KIT_ROOT"
  { [ -f "$KIT_ROOT/bin/managed-core.txt" ] \
    && git -C "$FRIDAY_KIT_ROOT" show "$want_commit:bin/managed-core.txt" | cmp -s - "$KIT_ROOT/bin/managed-core.txt"; } \
    || refuse_as_release "bin/managed-core.txt does not match $as_release in $FRIDAY_KIT_ROOT"
fi


# Check prerequisites before copying, not after a partially completed install.
command -v jq >/dev/null || { echo "error: 'jq' is required." >&2; exit 1; }
LIST="$KIT_ROOT/bin/managed-core.txt"
[ -f "$LIST" ] || { echo "error: $LIST missing — is this the Friday repo?" >&2; exit 1; }
read_list "$LIST"
# A payload with its own setup.sh gets it run, and that creates a missing
# AGENTS.md or CLAUDE.md; the --managed-only preview says so.
if [ -f "$PAYLOAD/.agents/bin/setup.sh" ]; then setup_makes_pointers=yes; fi
all_files=(${managed_files+"${managed_files[@]}"} ${seed_files+"${seed_files[@]}"})
[ ${#all_files[@]} -gt 0 ] || { echo "error: $LIST names no files" >&2; exit 1; }
# What is copied: the whole payload, or with --managed-only just the managed
# core, leaving every consumer-owned seed to the project.
if "$managed_only"; then files=(${managed_files+"${managed_files[@]}"}); else files=("${all_files[@]}"); fi

contains_file() {
  local candidate=$1 rel
  for rel in "${all_files[@]}"; do
    [ "$rel" = "$candidate" ] && return 0
  done
  return 1
}

for rel in "${all_files[@]}"; do
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
[ "$actual_count" -eq "${#all_files[@]}" ] || {
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

for rel in ${files+"${files[@]}"}; do check_destination "$rel" file; done
# With --managed-only the seeds are not conflicts, whatever they hold: they stay
# the project's. They are listed so the person sees what is left to reconcile.
if "$managed_only"; then report_seeds; fi
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
  if "$managed_only"; then
    echo "       --managed-only left the seeds listed as SEED to you; the boundary needs their wiring (see ADOPTING.md)." >&2
  fi
  exit 1
fi

echo ""
echo "Next: add consumer-specific overlays only after reviewing this shared baseline."
