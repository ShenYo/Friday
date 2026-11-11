#!/bin/bash
#
# Refuse agent writes to paths the project has declared off-limits.
#
# The list lives in .agents/protected-paths.conf, not here: which files are
# untouchable is a project decision, while refusing to touch them is not.
#
# Scope, stated plainly. This stops an agent that has not read — or has
# forgotten — the maintenance rules from editing a file it should have asked
# about. It is not a security boundary.
#
# Two known inaccuracies, both accepted:
#
#   Misses. The Bash scan matches literal text, so any write whose target is
#   not literally present in the command escapes it. Verified:
#   `python3 -c "open('CLAUDE.md','w')"` (a language runtime — a shell command
#   is not a reliable description of what a program will do);
#   `eval $(echo <base64> | base64 -d)`; and, the one that matters most,
#   `T=CLAUDE.md; echo hi > "$T"` — plain shell, no obfuscation intended, the
#   kind of line a careless agent writes by habit rather than to evade.
#
#   That last case narrows what this guard can claim. It stops the plain forms,
#   which is most of them, but "carelessness always uses the plain forms" is
#   not true. The list itself is the policy; the hook cannot see every write
#   that breaks it. The tool-level matchers for Write and Edit have no such
#   gap, because they receive the resolved path. A `cd` or `pushd` in the
#   command is followed when its destination is literal.
#
#   False alarms. The Bash scan reads the command as text, so a protected path
#   written after a `>` inside a heredoc or a quoted string looks like a
#   redirection. Likewise, when the command anywhere contains a `cd` whose
#   destination cannot be read (`cd "$X"`, `cd -`), even in a heredoc body or
#   after the write, every relative write target is refused. Refusing a write
#   that was never going to happen is the safe direction to be wrong in, and
#   the message says what matched, so the way out is obvious.
set -euo pipefail

block() {
  echo "BLOCKED: $1" >&2
  exit 2
}

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"
export PATH

for required in cat jq grep sed tr awk dirname pwd; do
  command -v "$required" >/dev/null 2>&1 \
    || block "required executable unavailable: $required"
done

input=$(cat) || block "unable to read hook payload"
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null) \
  || block "unable to parse hook payload"

repo_root=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
config="$repo_root/.agents/protected-paths.conf"

# --- collect the paths this call would write ---------------------------------

targets=()
cd_dests=()
cd_unknown=

case "$tool_name" in
  Write | Edit | MultiEdit | NotebookEdit)
    target_paths=$(printf '%s' "$input" | jq -er '
      def valid_path($name):
        (has($name) | not) or (.[$name] | type == "string");
      def valid_edits:
        (has("edits") | not) or
        (.edits | type == "array" and all(.[];
          type == "object" and valid_path("file_path")));
      .tool_input
      | if type != "object" or
          (valid_path("file_path") | not) or
          (valid_path("notebook_path") | not) or
          (valid_edits | not)
        then error("invalid write payload")
        else
          [ (if has("file_path") then .file_path else empty end),
            (if has("notebook_path") then .notebook_path else empty end),
            (.edits[]? | if has("file_path") then .file_path else empty end) ]
          | map(select(type == "string" and length > 0)) as $paths
          | if ($paths | length) > 0 then $paths[] else error("missing write target") end
        end
    ' 2>/dev/null) || block "invalid write-class hook payload"
    while IFS= read -r p; do
      [ -n "$p" ] && targets+=("$p")
    done <<< "$target_paths"
    ;;
  apply_patch)
    # Serves Codex, which Friday does not wire for this guard yet.
    patch=$(printf '%s' "$input" | jq -er '
      if (.tool_input | type) == "object" and (.tool_input.command | type) == "string"
      then .tool_input.command else error("invalid apply_patch payload") end
    ' 2>/dev/null) || block "invalid apply_patch hook payload"
    [ -n "$patch" ] || block "invalid apply_patch hook payload"
    first_line=${patch%%$'\n'*}
    last_line=${patch##*$'\n'}
    if [ "$first_line" != '*** Begin Patch' ] \
      || ! printf '%s\n' "$patch" | grep -Eq '^\*\*\* (Add|Update|Delete) File: .+$' \
      || [ "$last_line" != '*** End Patch' ]; then
      block "apply_patch payload was not a framed patch with a usable target; refusing it."
    fi
    if printf '%s\n' "$patch" | grep -Eq '^\*\*\* (Add|Update) File: .+$' \
      && ! printf '%s\n' "$patch" | grep -Eqv '^\*\*\* (Begin Patch|End Patch|(Add|Update|Delete) File: .+)$|^$'; then
      block "apply_patch Add/Update payload did not contain diff, hunk, or content; refusing it."
    fi
    target_paths=$(printf '%s\n' "$patch" \
      | sed -nE 's/^\*\*\* (Add|Update|Delete) File: //p') \
      || block "invalid apply_patch hook payload"
    [ -n "$target_paths" ] || block "apply_patch payload did not contain a usable patch target; refusing it."
    while IFS= read -r p; do
      [ -n "$p" ] && targets+=("$p")
    done <<< "$target_paths"
    ;;
  Bash)
    command=$(printf '%s' "$input" | jq -er '
      if (.tool_input | type) == "object" and (.tool_input.command | type) == "string"
      then .tool_input.command else error("invalid Bash payload") end
    ' 2>/dev/null) || block "invalid Bash hook payload"
    [[ -n ${command//[[:space:]]/} ]] || block "invalid Bash hook payload"
    # Shell writes only. A path that merely appears in a command is not a
    # write, so `cat`, `grep` and `git add` stay free.
    #
    # Redirections name their target directly. The others (sed -i, cp, mv,
    # install) write to the last argument of their clause, which is far more
    # reliable to find than parsing each command's own flag grammar — BSD and
    # GNU sed alone disagree about whether -i takes a separate argument.
    while IFS= read -r p; do
      [ -n "$p" ] && targets+=("$p")
    # `|| true` on each: grep exits 1 when a form is absent, and under
    # `set -e` with pipefail that would abort this subshell before the later
    # extractions ran — so a command using only `tee` was never inspected at
    # all, because the redirection grep above it found nothing first.
    #
    # Parentheses are not clause breaks for the last-argument forms: a
    # command substitution or a sed group would cut the clause before its
    # target. A subshell's closing parenthesis, glued to the last field or
    # standing alone after it, is dropped instead. (No comment inside the
    # process substitution below: bash 3.2 misparses one that holds an
    # unbalanced parenthesis.)
    done < <(
      {
        printf '%s\n' "$command" \
          | grep -oE ">>?[[:space:]]*(\"[^\"]*\"|'[^']*'|[^[:space:];|&<>()]+)" \
          | sed -E 's/^>>?[[:space:]]*//' || true
        printf '%s\n' "$command" \
          | tr ';|&' '\n' \
          | grep -E '(^|[[:space:](])(tee|cp|mv|install|sed[[:space:]]+-i)([[:space:]]|$)' \
          | sed -E 's/[[:space:]]*$//' \
          | awk '{ n = NF; while (n > 1 && $n ~ /^\)+$/) n--; f = $n; if (f !~ /\(/) sub(/\)+$/, "", f); print f }' || true
      } | sed -E "s/^[\"'](.*)[\"']$/\\1/"
    )
    # A `cd` or `pushd` in the command moves the shell, so a relative target
    # after it does not land under the hook's cwd. Collect each literal
    # destination; every relative target is then judged from the hook's cwd
    # and from each of them (how each is resolved is set out where the list
    # is built). Judging from too many places can only add refusals. A
    # destination that cannot be read literally ($VAR, `cd -`, a glob)
    # anywhere in the command leaves every relative target unjudgeable, so it
    # is refused. A cd that opens a command substitution, as in
    # DIR=$(cd "$(dirname "$0")" && pwd), cannot move the outer shell and is
    # skipped; a write inside that same substitution is missed.
    cd_word='^[[:space:]]*("[^"]*"|'\''[^'\'']*'\''|[^[:space:]]+)'
    while IFS= read -r clause; do
      verb=${clause%%@*}
      rest=${clause#*@}
      word=
      while [[ $rest =~ $cd_word ]]; do
        rest=${rest:${#BASH_REMATCH[0]}}
        case "${BASH_REMATCH[1]}" in
          -[LPe@] | -[LPe@][LPe@] | --) ;;
          # A quoted part that runs on into more text ('a b'/c) is one word
          # the pattern above cannot read whole; keep all of it so it is
          # treated as unreadable below rather than cut at the quote.
          *) word=${BASH_REMATCH[1]}${rest%%[[:space:]]*}; break ;;
        esac
      done
      # A redirection glued to the destination (cd X>/dev/null) is not part
      # of it.
      case "$word" in
        \"*\"[\<\>]*) word=${word%%\"[<>]*}\" ;;
        \'*\'[\<\>]*) word=${word%%\'[<>]*}\' ;;
        \"* | \'*) ;;
        *) word=${word%%[<>]*} ;;
      esac
      dest=
      case "$word" in
        '') [ "$verb" = cd ] && dest=${HOME-} ;; # a bare pushd swaps the stack
        \'*\')
          dest=${word:1:${#word}-2}
          case "$dest" in *\'*) dest= ;; esac
          ;;
        \"*\")
          dest=${word:1:${#word}-2}
          case "$dest" in *'$'* | *'`'* | *\\* | *\"*) dest= ;; esac
          ;;
        *'$'* | *'`'* | *\\* | *\"* | *\'* | *'*'* | *'?'* | *'['* | -* | +*) ;;
        '~') dest=${HOME-} ;;
        '~/'*) [ -n "${HOME-}" ] && dest=$HOME/${word#'~/'} ;;
        '~'*) ;;
        *) dest=$word ;;
      esac
      if [ -n "$dest" ]; then
        cd_dests+=("$dest")
      else
        cd_unknown="the command moves with '$verb${word:+ $word}', whose destination cannot be read literally"
      fi
    done < <(
      printf '%s\n' "$command" \
        | sed -E 's/\$\(/$(@subst /g' \
        | tr ';|&(){}' '\n' \
        | sed -nE 's/^[[:space:]]*((then|do|else|elif|if|while|until|time|!)[[:space:]]+)*((builtin|command)[[:space:]]+)?(cd|pushd)([[:space:]]+(.*))?$/\5@\7/p' || true
    )
    ;;
  *)
    exit 0
    ;;
esac

# No list means nothing is protected *here*, but a target may lie in another
# project that does have one, so this no longer ends the run. Each target
# resolves its own governing project below.
[ ${#targets[@]} -eq 0 ] && exit 0

# (Serves Codex, which Friday does not wire for this guard yet.)
# Codex supplies an absolute event cwd when it can. A relative cwd is not a
# stable base, so reject it rather than accidentally interpreting it through
# the hook's own process cwd. Older callers have no .cwd; their inherited PWD
# is the session cwd.
event_cwd=$(printf '%s' "$input" | jq -r '
  if has("cwd") then
    if (.cwd | type) == "string" and (.cwd | startswith("/")) then .cwd
    else error("invalid cwd") end
  else null end
' 2>/dev/null) || block "invalid hook cwd"
if [ "$event_cwd" = null ]; then
  event_cwd=${PWD-}
fi
[ -n "$event_cwd" ] \
  || block "unable to normalize hook cwd"
event_cwd=$(cd -P "$event_cwd" 2>/dev/null && pwd -P) \
  || block "unable to normalize hook cwd"

# Build an absolute lexical path without requiring the target to exist. An
# existing directory symlink is resolved through cd -P, so aliases of the
# checkout remain comparable to repo_root. A final symlink to a non-directory
# is refused: resolving it portably would require a readlink/realpath policy,
# and allowing an unnormalizable write target would be unsafe.
#
# The result goes to the global `normalized`, not to stdout: a relative target
# is normalized once per cd destination, and a command substitution per call
# would fork that many subshells.
normalize_target() {
  local target=$1 base=$2 path component next

  if [[ "$target" == /* ]]; then
    path=$target
    base=/
  else
    path=$target
  fi

  while :; do
    component=${path%%/*}
    if [ "$path" = "$component" ]; then
      path=
    else
      path=${path#*/}
    fi

    case "$component" in
      '' | .) ;;
      ..)
        [ "$base" = / ] || base=${base%/*}
        [ -n "$base" ] || base=/
        ;;
      *)
        if [ "$base" = / ]; then
          next=/$component
        else
          next=$base/$component
        fi
        if [ -L "$next" ]; then
          [ -d "$next" ] || return 1
          base=$(cd -P "$next" 2>/dev/null && pwd -P) || return 1
        else
          base=$next
        fi
        ;;
    esac

    [ -n "$path" ] || break
  done

  normalized=$base
}

# Resolve the project that owns a path by walking up to the nearest .git,
# into the global `owner`. Pure shell on purpose: `git -C` needs an existing
# directory, and a write target's parent may not exist yet. No fork per level,
# for the same reason as normalize_target.
owning_root() {
  local dir=$1
  while [ -n "$dir" ] && [ "$dir" != / ] && [ "$dir" != . ]; do
    [ -e "$dir/.git" ] && { owner=$dir; return 0; }
    dir=${dir%/*}
  done
  return 1
}

# Judge ONE target against the list of the project that owns it.
#
# The owning project is the nearest ancestor holding a `.git` (file or
# directory), so a worktree nested inside the repository is its own project and
# a target in another repository is judged by that repository's list. The
# guard's own `repo_root` only picks the wording of the message.
#
# Everything here is `local`, except a cache of the last list read, which is
# keyed by its root. Resolving a foreign list into a *global* array without
# that key would leave every later target in the same payload judged against
# the wrong list: a multi-target call whose first target lay in another
# project would make protected files writable with exit 0 and no message.
cached_root=
cached_pats=()
judge_target() {
  local absolute=$1
  local root rel conf line pattern append_only label whose
  local -a pats=()

  owning_root "${absolute%/*}" || return 0
  root=$owner
  if [ "$root" = "$repo_root" ]; then
    label=.agents/protected-paths.conf
    # Keep this wording stable: it is the refusal projects document.
    whose="this project's protected-paths list"
  else
    label="$root/.agents/protected-paths.conf"
    # A foreign target must name whose list refused it, or the message sends
    # the reader to a conf file that does not contain the matched rule.
    whose="the protected-paths list of the project at $root"
  fi

  conf="$root/.agents/protected-paths.conf"
  # Only an absent list means unprotected. A directory, FIFO or dangling link
  # in its place is a broken policy, refused like an unreadable one.
  [ -e "$conf" ] || [ -L "$conf" ] || return 0
  [ -f "$conf" ] || block "$label exists but is not a regular file; refusing rather than treating the project as unprotected."
  [ -r "$conf" ] || block "$label exists but is not readable; refusing rather than treating the project as unprotected."

  if [ "$absolute" = "$root" ]; then rel=.; else rel=${absolute#"$root"/}; fi

  if [ "$root" != "$cached_root" ]; then
    cached_pats=()
    while IFS= read -r line || [ -n "$line" ]; do
      line=${line%%#*}
      line=${line#"${line%%[![:space:]]*}"}
      line=${line%"${line##*[![:space:]]}"}
      [ -z "$line" ] || cached_pats+=("$line")
    done < "$conf"
    cached_root=$root
  fi
  [ ${#cached_pats[@]} -eq 0 ] && return 0
  pats=("${cached_pats[@]}")

  for pattern in "${pats[@]}"; do
    # An `append-only` prefix means the path may be created but never changed:
    # an existing file is protected, a new one is allowed. Snapshots need this,
    # because the procedure that produces them writes into a protected tree.
    append_only=0
    case "$pattern" in
      "append-only "*) append_only=1; pattern=${pattern#append-only } ;;
    esac

    # The pattern is a glob on purpose; in `case`, * spans '/'.
    case $rel in
      $pattern)
        if [ "$append_only" -eq 1 ]; then
          [ -e "$root/$rel" ] || continue
          block "'$rel' already exists and is append-only ($label, matched 'append-only $pattern'). Snapshots are immutable — write a new file instead of changing this one."
        fi
        block "'$rel' is on $whose ($label, matched '$pattern'). Ask the user to make this change, or to remove the entry if the rule no longer applies."
        ;;
    esac
  done
  return 0
}

# The places a relative Bash target may be relative to: the hook's cwd, and
# every literal `cd` destination. Each destination has a primary place: where
# it lands if the cds before it all ran in sequence. A relative destination is
# resolved from the previous primary, from the hook's cwd and from every
# earlier primary, since a subshell may have undone any of the cds between.
# Resolving it from every known place instead would double the list with each
# cd. Duplicates are dropped, and past a cap a relative target is refused
# rather than judged slowly enough to hit the hook timeout.
max_bases=64
bases=("$event_cwd")
prims=("$event_cwd")
prev=$event_cwd
for dest in ${cd_dests[@]+"${cd_dests[@]}"}; do
  [ -z "$cd_unknown" ] || break
  if [[ $dest == /* ]]; then
    from=(/)
  else
    from=("$prev" "${prims[@]}")
  fi
  first=1
  for base in "${from[@]}"; do
    normalize_target "$dest" "$base" \
      || { cd_unknown="the command moves with 'cd $dest', which cannot be resolved"; break; }
    resolved=$normalized
    if [ "$first" -eq 1 ]; then
      prev=$resolved
      known=0
      for b in "${prims[@]}"; do [ "$b" != "$resolved" ] || known=1; done
      [ "$known" -eq 1 ] || prims+=("$resolved")
    fi
    first=0
    known=0
    for b in "${bases[@]}"; do [ "$b" != "$resolved" ] || known=1; done
    [ "$known" -eq 0 ] || continue
    [ ${#bases[@]} -lt "$max_bases" ] \
      || { cd_unknown="the command has more cd destinations than the guard follows"; break; }
    bases+=("$resolved")
  done
done

# Each absolute path is judged once: many relative targets from many bases
# often land on the same few paths.
judged=$'\n'
for target in "${targets[@]}"; do
  if [[ $target == /* ]]; then
    from=("$event_cwd")
  else
    [ -z "$cd_unknown" ] \
      || block "'$target' is relative, and $cd_unknown, so where it lands is unknown. Write it with an absolute path, or cd to a literal path."
    from=("${bases[@]}")
  fi
  for base in "${from[@]}"; do
    normalize_target "$target" "$base" \
      || block "unable to normalize write target '$target'"
    absolute=$normalized
    case $judged in *$'\n'"$absolute"$'\n'*) continue ;; esac
    judged=$judged$absolute$'\n'

    # Compare repo-relative inside the owning project, so absolute, repo-root
    # and nested-session targets are judged identically — and a target in
    # another project is judged against that project's list rather than
    # skipped.
    judge_target "$absolute"
  done
done
