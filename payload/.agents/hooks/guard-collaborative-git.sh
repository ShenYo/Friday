#!/usr/bin/env bash

set -euo pipefail

input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""')
command=$(printf '%s' "$input" | jq -r 'if (.tool_input | type) == "object" then .tool_input.command // "" else "" end')

block() {
  echo "BLOCKED: $1" >&2
  exit 2
}

if [[ "$tool_name" == "apply_patch" ]]; then
  patch=$(printf '%s' "$input" | jq -r '
    .tool_input
    | if type == "string" then .
      elif type == "object" or type == "array" then
        [.. | strings | select(test("\\*\\*\\* (Add|Update|Delete) File:"))] | join("\n")
      else empty
      end
  ')
  if [[ -z "$patch" ]]; then
    block "apply_patch payload did not contain patch text; refusing it."
  fi

  if printf '%s\n' "$patch" | grep -Eq '^[[:space:]]*\*\*\* Delete File:'; then
    block "deleting a file with apply_patch is permanently agent-prohibited by the collaborative Git safety boundary. Ask the user to delete it directly."
  fi

  exit 0
fi

blocked_patterns=(
  'git[[:space:]].*push.*(--force-with-lease|--force|-f)([[:space:];|&]|$)'
  'git[[:space:]].*reset[[:space:]]+--hard([[:space:];|&]|$)'
  'git[[:space:]].*clean([[:space:];|&]|$)'
  'git[[:space:]].*branch[[:space:]]+-D([[:space:];|&]|$)'
  'git[[:space:]].*stash[[:space:]]+(clear|drop)([[:space:];|&]|$)'
  'git[[:space:]].*worktree[[:space:]]+remove([[:space:];|&]|$)'
  'git[[:space:]].*remote[[:space:]]+(remove|set-url)([[:space:];|&]|$)'
  '(^|[[:space:];|&])find[[:space:]].*-delete([[:space:];|&]|$)'
  '(^|[[:space:];|&])gh[[:space:]]+repo[[:space:]]+delete([[:space:];|&]|$)'
  '(^|[[:space:];|&])gh[[:space:]]+api.*(-X|--method)[[:space:]]+DELETE([[:space:];|&]|$)'
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
