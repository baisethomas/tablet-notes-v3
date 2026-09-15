# Ratchet Project State

<!--
Semantic handoff for the current branch/workstream. Keep it short, current, and factual.
Agents update it as meaningful workstream state changes and before handoff.
SAFETY: no secrets, credentials, key ids, personal/customer data, or incident narratives.
Constraints and ticket references only; the history lives in Linear and the PRs.
SCOPE: branch-local; Git integration reconciles branches. Not a session transcript.
-->

## Objective

TabletNotes 1.0 is live on the App Store (since 2026-09-11). The workstream is post-launch stabilization: ship 1.0.1 with the recording-notes fixes, then move to monitoring and the backlog.

## Current phase

1.0.1 submitted for App Review (2026-09-14 evening PT). Waiting on Apple. The Ratchet harness is on `main` (TAB-116, merged 2026-09-15); this file is now the `main` state.

## Completed

- TAB-117: added a thin `CODEX.md` adapter that maps the repository's existing risk tiers to Codex models while keeping `AGENTS.md` canonical.
- 1.0 approved and live. The paywall is reachable from the Account tab and Settings in every entitlement state, including the trial (TAB-111, TAB-112).
- Recording notes are now preserved across backgrounding and stop paths (TAB-113, TAB-114; device-verified). History and evidence are in those issues and PRs #76/#77.
- `MARKETING_VERSION` bumped to 1.0.1 for the release (TAB-115).
- TAB-110: backend half live since 2026-09-03; client half rides in 1.0.1.

## Working on

- TAB-117 is in PR preparation on `baise/tab-117-add-codex-adapter-to-the-ratchet-harness`; implementation and review are complete.

## Next

1. When Apple approves 1.0.1: close TAB-110, TAB-113, TAB-114, TAB-115. If rejected, bring the Resolution Center text into the working session.
2. Watch the owner's daily health check for the first real purchase and for the new build's note-save behavior.
3. Backlog, roughly in order: TAB-103 step 2 (retire the legacy processing path once the durable pipeline has soaked), TAB-33, then TAB-102/104/105 (low).

## Blocked

- None. (App Review is a wait, not a blocker.)

## Important context

- Every release after a live version needs `MARKETING_VERSION` bumped in `TabletNotes.xcodeproj` before archiving; Xcode assigns the build number per version string at upload (see D-20260914-0400 in `DECISIONS.md`).
- The recovery manifest is the source of truth for which note session belongs to the audio being captured. Nothing may clear it or the session while a recording is live (D-20260913-2300).
- Long-lived services are built once at the app root and injected; nothing with side effects is constructed in a SwiftUI view initializer (D-20260914-0000).
- Netlify prod auto-deploys on merge to `main`; env-var changes need a manual `netlify deploy --prod`. Supabase migrations are owner-only.
- Two test failures pre-exist on `main` (listed in `docs/OPERATING-MANUAL.md` §3). A simulator that has been used for manual recording carries orphan audio that makes the `SermonService*` suites fail there; use the clean 18.5 simulator named in the manual.
- Device diagnosis: the app's `NotesLog` category is readable from a phone log stream over USB; the recipe is in the owner's notes and the TAB-113/114 PRs.

## Verification status

- TAB-117 branch atop `main` @ 9b6ff6d: `git diff --check` passes and referenced repository files exist; no product code changed, so iOS and backend tests were not required.
- `main` @ d2ac566 (the 1.0.1 archive point): iOS build green on the clean simulator; note/recording suites green (TAB-113: 60/60, TAB-114: 18/18); `npm test` 235/235.
- Harness on `main` @ 0fd39d7 (TAB-116): `.claude/hooks/test-hooks.sh` 261/261 (upstream Ratchet assertions with the ordinary-push examples retargeted to a feature branch, plus the TabletNotes hard-stop/allow assertions: implicit pushes while `main` is checked out or tracked, ANSI-C quoted flags, process substitution, aliases behind global options); the stop gate run from the repo passes idle and runs `npm test` when an API file is present; `npm test` 235/235. No Swift changed, so no iOS build was required.

## Open risks / assumptions

- App Review may exercise the app on a fresh Sign in with Apple account (trial state); the always-visible Premium row is what addresses that.
- The auto-stop save handler skips the save if the stop event carries no session id. Unreachable while audio is present, but it should fall back rather than skip if that invariant ever changes.
- Crash reporting has been quiet since launch; too early to call it stable.

## Integration note

- TAB-117 is isolated on its Linear-named feature branch atop 9b6ff6d; unrelated untracked Marketing artifacts were left untouched.

## Last handoff

- Updated: 2026-09-15
- By: agent (Codex)
- Branch/worktree: `baise/tab-117-add-codex-adapter-to-the-ratchet-harness`
- Last known-good commit: 9b6ff6d (main)
