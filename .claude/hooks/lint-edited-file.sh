#!/usr/bin/env bash
# PostToolUse(Edit|Write) hook (Ratchet): check the file that was just edited so
# the error lands in-loop, whether or not the model would have checked.
#
# TabletNotes adaptation of drop-in/hooks/lint-edited-file.sh. This repo has no
# ESLint config and no SwiftLint, and a per-edit xcodebuild is far too slow, so:
#   - *.js / *.mjs / *.cjs under tablet-notes-api/ → `node --check` (syntax).
#     The Netlify functions have no test harness of their own; a syntax error
#     there ships straight to prod on merge, which is why this is the one
#     thing worth checking on every edit.
#   - Everything else → no-op. Swift is verified by the stop gate's build.
#
# Contract (https://code.claude.com/docs/en/hooks):
#   - input arrives as JSON on stdin; the path is at .tool_input.file_path
#   - exit 2 surfaces stderr back to Claude; exit 0 is silent success

set -uo pipefail

# shellcheck source=lib-payload.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-payload.sh"

input=$(cat)

file=$(payload_field "$input" '.tool_input.file_path' '?.tool_input?.file_path')
case $? in
  1) no_parser_message "lint hook disabled"; exit 2 ;;
  2) echo "lint hook disabled: could not parse the hook payload, so edited files are not being checked. Fix the JSON parser (jq/node)." >&2
     exit 2 ;;
esac

[ -z "$file" ] && exit 0

case "$file" in
  *tablet-notes-api/*.js|*tablet-notes-api/*.mjs|*tablet-notes-api/*.cjs) ;;
  *) exit 0 ;;
esac

[ -f "$file" ] || exit 0

if ! command -v node >/dev/null 2>&1; then
  echo "lint hook disabled: node is not on PATH, so ${file} was not syntax-checked." >&2
  exit 2
fi

# Capture rather than pipe: a pipeline would report tail's status, not node's.
output=$(node --check "$file" 2>&1)
status=$?
[ "$status" -eq 0 ] && exit 0

{
  echo "node --check reported a syntax error in ${file}:"
  printf '%s\n' "$output" | head -30
} >&2
exit 2
