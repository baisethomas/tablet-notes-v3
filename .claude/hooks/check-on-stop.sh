#!/usr/bin/env bash
# Stop hook (Ratchet): run the repo's verification before Claude is allowed to
# finish, so a red suite surfaces at "done" time instead of after merge.
#
# TabletNotes adaptation of drop-in/hooks/check-on-stop.sh:
#   - `npm test` in tablet-notes-api/ runs when anything under tablet-notes-api/
#     differs from the merge-base with main (committed or not). ~1 s.
#   - The iOS build runs when any Swift/pbxproj/plist under TabletNotes/ differs,
#     and only if the working tree's fingerprint changed since the last GREEN
#     build, so it costs one build per set of edits, not one per stop.
#   - Nothing changed → the gate passes immediately.
#
# Contract (https://code.claude.com/docs/en/hooks):
#   - exit 2 prevents Claude from stopping and feeds stderr back to it
#   - exit 0 allows the stop
#   - exit 1 is NOT blocking, so failures are translated to exit 2
#
# Each command's status is captured directly rather than piped to `tail`: in a
# pipeline the exit status is `tail`'s (0), which would silently pass a red run.
#
# Loop safety: idempotent (re-runs the checks, so it stops blocking as soon as
# they pass) and MAX_BLOCKS caps consecutive blocks per session so an unfixable
# environmental failure cannot trap the conversation.

set -uo pipefail

MAX_BLOCKS=3
IOS_SIM_ID="2BAC53A3-EC5B-40DE-A981-7F7A637A555E"   # clean iOS 18.5 sim named in AGENTS.md

# shellcheck source=lib-payload.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-payload.sh"

input=$(cat)

session=$(payload_field "$input" '.session_id' '?.session_id') || session=""
[ -z "$session" ] && session="nosession"

active=$(payload_field "$input" '.stop_hook_active' '?.stop_hook_active') || active="false"
[ "$active" = "true" ] || active="false"

if ! cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null; then
  if [ "$active" = "true" ]; then
    echo "Stop gate: still cannot enter CLAUDE_PROJECT_DIR (${CLAUDE_PROJECT_DIR:-.}); releasing. Verification did NOT run — do not claim the work is verified." >&2
    exit 0
  fi
  echo "Stop gate: cannot enter CLAUDE_PROJECT_DIR (${CLAUDE_PROJECT_DIR:-.}), so checks did not run. Fix the path or report that verification could not be performed." >&2
  exit 2
fi

# --- What changed? -----------------------------------------------------------
# Union of committed-on-branch changes (vs merge-base with main) and the working
# tree (staged, unstaged, untracked). Outside a git work tree (e.g. the hook
# self-test's temp dirs) there is nothing to diff, so fall back to the generic
# drop-in behaviour: run `npm test` in the project dir if it has a package.json.
changed=""; generic=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  base=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo "")
  if [ -n "$base" ]; then
    changed=$(git diff --name-only "$base" 2>/dev/null)
  else
    changed=$(git diff --name-only HEAD 2>/dev/null)
  fi
  changed="${changed}"$'\n'"$(git ls-files --others --exclude-standard 2>/dev/null)"
else
  generic=1
fi

api_changed=0; ios_changed=0
grep -qE '^tablet-notes-api/' <<<"$changed" && api_changed=1
grep -qE '^TabletNotes/.*\.(swift|pbxproj|plist|entitlements|xcconfig)$' <<<"$changed" && ios_changed=1

# --- Private state dir (retry counter + iOS build fingerprint) ---------------
state_dir="${TMPDIR:-/tmp}/claude-stop-gate.$(id -u)"
if [ -L "$state_dir" ] || { [ -e "$state_dir" ] && [ ! -d "$state_dir" ]; }; then
  echo "Stop gate: ${state_dir} exists but is not a directory; refusing to use it. Checks still ran." >&2
  state_dir=""
else
  mkdir -p "$state_dir" 2>/dev/null
  chmod 700 "$state_dir" 2>/dev/null
  perm=$(ls -ld "$state_dir" 2>/dev/null | cut -c1-10)
  if [ ! -d "$state_dir" ] || [ -L "$state_dir" ] || [ ! -O "$state_dir" ] || [ "$perm" != "drwx------" ]; then
    echo "Stop gate: ${state_dir} is not a private directory owned by this user; running without a retry counter or build cache." >&2
    state_dir=""
  fi
fi

write_state() {  # write_state <path> <content> — fresh mktemp + rename, never follow a symlink
  local path="$1" content="$2" tmpf
  [ -z "$state_dir" ] && return 1
  tmpf=$(umask 077; mktemp "${state_dir}/.tmp.XXXXXX" 2>/dev/null) || return 1
  if printf '%s\n' "$content" > "$tmpf" 2>/dev/null && mv -f "$tmpf" "$path" 2>/dev/null; then return 0; fi
  rm -f "$tmpf" 2>/dev/null; return 1
}
read_state() {  # read_state <path> — regular, owned, non-symlink file only
  local path="$1"
  [ -n "$path" ] && [ -f "$path" ] && [ ! -L "$path" ] && head -c 200 "$path" 2>/dev/null | tr -d '\n'
}

counter=""; ios_cache=""
if [ -n "$state_dir" ]; then
  key=$(printf '%s' "$session" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -d' ' -f1)
  [ -z "$key" ] && key="fallback"
  counter="$state_dir/$key"
  ios_cache="$state_dir/ios-green-$(printf '%s' "$PWD" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -d' ' -f1)"
fi

# --- Checks ------------------------------------------------------------------
fail=0
report=""

if [ "$generic" -eq 1 ] && [ -f package.json ]; then
  if ! out=$(npm test --silent 2>&1); then
    fail=1
    report="${report}--- npm test ---"$'\n'"$(printf '%s' "$out" | tail -25)"$'\n'
  fi
fi

if [ "$api_changed" -eq 1 ]; then
  if ! out=$(cd tablet-notes-api && npm test --silent 2>&1); then
    fail=1
    report="${report}--- npm test (tablet-notes-api) ---"$'\n'"$(printf '%s' "$out" | tail -25)"$'\n'
  fi
fi

if [ "$ios_changed" -eq 1 ]; then
  # Fingerprint = HEAD + content hash of every changed/untracked iOS file.
  fp=$( { git rev-parse HEAD 2>/dev/null; git diff HEAD -- TabletNotes 2>/dev/null; git ls-files --others --exclude-standard TabletNotes 2>/dev/null | while IFS= read -r f; do [ -f "$f" ] && cat "$f"; done; } | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -d' ' -f1)
  if [ -n "$fp" ] && [ "$(read_state "$ios_cache")" = "$fp" ]; then
    : # already green for exactly this tree
  else
    if ! out=$(cd TabletNotes && xcodebuild build -scheme TabletNotes -destination "platform=iOS Simulator,id=${IOS_SIM_ID}" 2>&1); then
      fail=1
      report="${report}--- xcodebuild build (TabletNotes) ---"$'\n'"$(printf '%s' "$out" | grep -E 'error:|\*\* BUILD' | grep -vE 'DTDK|passcode' | tail -25)"$'\n'
    else
      [ -n "$fp" ] && write_state "$ios_cache" "$fp"
    fi
  fi
fi

if [ "$fail" -eq 0 ]; then
  [ -n "$counter" ] && rm -f "$counter"
  exit 0
fi

# --- Bounded blocking --------------------------------------------------------
prev=0
raw=$(read_state "$counter" | tr -dc '0-9'); [ -n "$raw" ] && prev=$raw
blocks=$((prev + 1))
persisted=0
write_state "$counter" "$blocks" && persisted=1

if [ "$persisted" -eq 0 ] && [ "$active" = "true" ]; then
  echo "Verification is still failing, but the stop-gate counter cannot be persisted, so the retry cap cannot be enforced. Releasing rather than trapping the session — report the failure honestly instead of claiming success." >&2
  exit 0
fi

if [ "$blocks" -gt "$MAX_BLOCKS" ]; then
  [ -n "$counter" ] && rm -f "$counter"
  echo "Verification still failing after ${MAX_BLOCKS} attempts; releasing the stop gate. Report the failure honestly rather than claiming success." >&2
  exit 0
fi

{
  echo "Verification failed — do not report this work as done."
  printf '%s' "$report"
} >&2
exit 2
