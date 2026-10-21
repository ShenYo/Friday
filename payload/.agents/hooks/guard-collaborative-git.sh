#!/bin/bash

set -euo pipefail

block() {
  echo "BLOCKED: $1" >&2
  exit 2
}

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"
export PATH

for required in cat jq grep; do
  command -v "$required" >/dev/null 2>&1 \
    || block "required executable unavailable: $required"
done

input=$(cat) || block "unable to read hook payload"
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null) \
  || block "unable to parse hook payload"

case "$tool_name" in
  Bash)
    command=$(printf '%s' "$input" | jq -er '
      if (.tool_input | type) == "object" and (.tool_input.command | type) == "string"
      then .tool_input.command else error("invalid Bash payload") end
    ' 2>/dev/null) || block "invalid Bash hook payload"
    [[ -n ${command//[[:space:]]/} ]] || block "invalid Bash hook payload"
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

    if printf '%s\n' "$patch" | grep -Eq '^\*\*\* Delete File: .+$'; then
      block "deleting a file with apply_patch is permanently agent-prohibited by the collaborative Git safety boundary. Ask the user to delete it directly."
    fi

    if printf '%s\n' "$patch" | grep -Eq '^\*\*\* (Add|Update) File: .+$' \
      && ! printf '%s\n' "$patch" | grep -Eqv '^\*\*\* (Begin Patch|End Patch|(Add|Update|Delete) File: .+)$|^$'; then
      block "apply_patch Add/Update payload did not contain diff, hunk, or content; refusing it."
    fi

    exit 0
    ;;
  *)
    exit 0
    ;;
esac

blocked_patterns=(
  # Every git rule forbids a quote character between `git` and the subcommand,
  # so a dangerous word inside a commit message is not mistaken for the
  # operation it names: `git commit -m "fix: clean up"` is not `git clean`.
  # A real invocation never has a quote in that position. The gh rules are
  # anchored on their subcommand and need no such guard.
  "git[[:space:]][^'\"]*push[^'\"]*(--force-with-lease|--force|-f)(=|[[:space:];|&]|\$)"
  "git[[:space:]][^'\"]*reset[[:space:]]+--hard([[:space:];|&]|\$)"
  "git[[:space:]][^'\"]*clean([[:space:];|&]|\$)"
  "git[[:space:]][^'\"]*branch[[:space:]]+(-[dD]|--delete)([[:space:];|&]|\$)"
  "git[[:space:]][^'\"]*tag[[:space:]]+(-d|--delete)([[:space:];|&]|\$)"
  "git[[:space:]][^'\"]*push[^'\"]*(--delete|-d)([=[:space:];|&]|\$)"
  "git[[:space:]][^'\"]*push[[:space:]][^'\"]*[[:space:]]:[^[:space:];|&]+([[:space:];|&]|\$)"
  "git[[:space:]][^'\"]*stash[[:space:]]+(clear|drop)([[:space:];|&]|\$)"
  "git[[:space:]][^'\"]*worktree[[:space:]]+remove([[:space:];|&]|\$)"
  "git[[:space:]][^'\"]*remote[[:space:]]+(remove|set-url)([[:space:];|&]|\$)"
  "(^|[[:space:];|&])find[[:space:]][^;|&]*-delete([[:space:];|&]|\$)"
  "(^|[[:space:];|&])gh[[:space:]]+repo[[:space:]]+delete([[:space:];|&]|\$)"
  "(^|[[:space:];|&])gh[[:space:]]+api[^;|&]*(-X(=|[[:space:]]*)DELETE|--method(=|[[:space:]]+)DELETE)([[:space:];|&]|\$)"
  # Human-review checkpoints. Not irreversible; reserved because integrating a
  # change, delegating that decision to CI, or altering a shared review
  # artifact is a person's call however many automated checks passed.
  # Approving a pull request is reserved too but cannot be matched here: the
  # guard sees a command and cannot tell an author from an independent
  # reviewer, so that rule lives in safety-boundary.md and is enforced by
  # instruction rather than by this guard.
  "(^|[[:space:];|&])gh[[:space:]]+pr[[:space:]]+merge([[:space:];|&]|\$)"
  "(^|[[:space:];|&])gh[[:space:]]+pr[[:space:]]+(close|reopen)([[:space:];|&]|\$)"
  "(^|[[:space:];|&])gh[[:space:]]+(pr|repo)[[:space:]][^;|&]*--auto([[:space:];|&=]|\$)"
  # Bypassing the commit-time hooks. Those hooks are where the secret scan and
  # the message checks actually run, so skipping them turns the whole contract
  # back into advice. `-n` is spelled out per subcommand on purpose: for commit
  # it means --no-verify, but for push it means --dry-run, which is harmless
  # and must keep working.
  # The short form may be bundled with other short options (-nm), so match a
  # single-dash cluster containing n. Requiring a space before the dash keeps
  # long options such as --no-edit out of it.
  "git[[:space:]][^'\"]*commit[^'\"]*--no-verify([[:space:];|&]|\$)"
  "git[[:space:]][^'\"]*commit[^'\"]*[[:space:]]-[A-Za-z]*n[A-Za-z]*([[:space:];|&]|\$)"
  "git[[:space:]][^'\"]*push[^'\"]*--no-verify([[:space:];|&]|\$)"
  "git[[:space:]][^'\"]*-c[[:space:]]*core\\.hooksPath([=[:space:]]|\$)"
)

rm_command_pattern="(^|[[:space:];|&'\"])([^[:space:];|&'\"]*/)?rm[[:space:]]+([^;|&]*)"

if [[ "$command" =~ $rm_command_pattern ]]; then
  rm_arguments=${BASH_REMATCH[3]}
  if [[ "$rm_arguments" == --[[:space:]]* ]]; then
    rm_options=""
  else
    rm_options=${rm_arguments%%[[:space:]]--[[:space:]]*}
  fi

  if [[ "$rm_options" =~ (^|[[:space:]])--recursive([[:space:]]|$) ||
    "$rm_options" =~ (^|[[:space:]])-[[:alnum:]]*[rR][[:alnum:]]*([[:space:]]|$) ]]; then
    block "'$command' is permanently agent-prohibited by the collaborative Git safety boundary. Ask the user to run it directly."
  fi
fi

for pattern in "${blocked_patterns[@]}"; do
  if printf '%s\n' "$command" | grep -Eq "$pattern"; then
    block "'$command' is permanently agent-prohibited by the collaborative Git safety boundary. Ask the user to run it directly."
  fi
done
