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
#   not true. Note that these paths remain prohibited by
#   `.agents/docs/git-guideline/safety-boundary.md` regardless: the policy binds whether
#   or not this hook can see the write. The tool-level matchers for Write and
#   Edit have no such gap, because they receive the resolved path.
#
#   False alarms. The Bash scan reads the command as text, so a protected path
#   written after a `>` inside a heredoc or a quoted string looks like a
#   redirection. Refusing a write that was never going to happen is the
#   safe direction to be wrong in, and the message names the pattern that
#   matched, so the way out is obvious.
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
    done < <(
      {
        printf '%s\n' "$command" \
          | grep -oE ">>?[[:space:]]*(\"[^\"]*\"|'[^']*'|[^[:space:];|&<>]+)" \
          | sed -E 's/^>>?[[:space:]]*//' || true
        printf '%s\n' "$command" \
          | tr ';|&' '\n' \
          | grep -E '(^|[[:space:]])(tee|cp|mv|install|sed[[:space:]]+-i)([[:space:]]|$)' \
          | sed -E 's/[[:space:]]*$//' \
          | awk '{print $NF}' || true
      } | sed -E "s/^[\"'](.*)[\"']$/\\1/"
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

  printf '%s\n' "$base"
}

# Resolve the project that owns a path by walking up to the nearest .git.
# Pure shell on purpose: `git -C` needs an existing directory, and a write
# target's parent may not exist yet.
owning_root() {
  local dir=$1
  while [ -n "$dir" ] && [ "$dir" != / ] && [ "$dir" != . ]; do
    [ -e "$dir/.git" ] && { printf '%s\n' "$dir"; return 0; }
    dir=$(dirname "$dir")
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
# Everything here is `local`. Resolving a foreign list into the *global*
# `patterns` array would leave every later target in the same payload judged
# against the wrong list: a multi-target call whose first target lay in another
# project would make protected files writable with exit 0 and no message.
# Nothing in this function may outlive one call.
judge_target() {
  local absolute=$1
  local root rel conf line pattern append_only label whose
  local -a pats=()

  root=$(owning_root "$(dirname "$absolute")") || return 0
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
  [ -f "$conf" ] || return 0

  if [ "$absolute" = "$root" ]; then rel=.; else rel=${absolute#"$root"/}; fi

  while IFS= read -r line; do
    line=${line%%#*}
    line=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -n "$line" ] && pats+=("$line")
  done < "$conf"
  [ ${#pats[@]} -eq 0 ] && return 0

  for pattern in "${pats[@]}"; do
    # An `append-only` prefix means the path may be created but never changed:
    # an existing file is protected, a new one is allowed. Snapshots need this,
    # because the procedure that produces them writes into a protected tree.
    append_only=0
    case "$pattern" in
      "append-only "*) append_only=1; pattern=${pattern#append-only } ;;
    esac

    # shellcheck disable=SC2053 -- pattern is a glob on purpose; * spans '/'.
    if [[ "$rel" == $pattern ]]; then
      if [ "$append_only" -eq 1 ]; then
        [ -e "$root/$rel" ] || continue
        block "'$rel' already exists and is append-only ($label, matched 'append-only $pattern'). Snapshots are immutable — write a new file instead of changing this one."
      fi
      block "'$rel' is on $whose ($label, matched '$pattern'). Ask the user to make this change, or to remove the entry if the rule no longer applies."
    fi
  done
  return 0
}

for target in "${targets[@]}"; do
  absolute=$(normalize_target "$target" "$event_cwd") \
    || block "unable to normalize write target '$target'"

  # Compare repo-relative inside the owning project, so absolute, repo-root
  # and nested-session targets are judged identically — and a target in
  # another project is judged against that project's list rather than skipped.
  judge_target "$absolute"
done
