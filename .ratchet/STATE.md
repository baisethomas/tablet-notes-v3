# Ratchet Project State

<!--
Semantic handoff for the current branch/workstream. Keep it short, current, and factual.
Agents update it as meaningful workstream state changes and before handoff.
SAFETY: no secrets, credentials, key ids, personal/customer data, or sensitive incident detail.
SCOPE: branch-local; Git integration reconciles branches. Not a session transcript.
-->

## Objective

TabletNotes 1.0 is live on the App Store (since 2026-09-11). The workstream is post-launch stabilization: ship 1.0.1 with the recording-notes fixes, then move to monitoring and the backlog.

## Current phase

1.0.1 submitted for App Review (2026-09-14 evening PT). Waiting on Apple. Repo housekeeping (Ratchet adoption) in flight on this branch.

## Completed

- 1.0 approved and live: always-visible Premium row (TAB-111) + honest trial label on the paywall (TAB-112) resolved two 2.1(b) rejections caused by reviewers signing in with Apple and landing on the 14-day trial.
- Notes lost on real-length recordings: fixed in two layers. TAB-113 (stop never drops visible text; the live note session cannot be retired) and TAB-114 (the trigger: foregrounding re-ran `MainAppView.init`, whose throwaway `SermonService` ran the interrupted-recording scan against the live recording, deleting its manifest and clearing its notes; services are now built once at the app root and the scan skips the live session). Both device-verified with the phone log attached.
- TAB-115: `MARKETING_VERSION` bumped to 1.0.1 (a live version closes its train; the upload was rejected until the bump).
- Backend half of TAB-110 (notes reconciled on update, honest `syncedScopes`) live since 2026-09-03; client half rides in 1.0.1.

## Working on

- TAB-116: adopting the Ratchet harness (this branch): `AGENTS.md`, thin `CLAUDE.md`, manual moved to `docs/OPERATING-MANUAL.md`, `.ratchet/` memory, verification hooks.

## Next

1. When Apple approves 1.0.1: close TAB-110, TAB-113, TAB-114, TAB-115. If rejected, paste the Resolution Center text into the working session; the fixes are in-app and verified, so a rejection is most likely metadata or reviewer flow.
2. Watch the daily health check (owner's scheduled task) for the first real purchase and for any notes-less sermon on the new build.
3. Backlog, roughly in order: TAB-103 step 2 (retire the legacy processing path once the durable pipeline has soaked), TAB-33 (fallback-summary insurance or close at retirement), TAB-102/104/105 (low).

## Blocked

- None. (App Review is a wait, not a blocker.)

## Important context

- Every release after a live version needs `MARKETING_VERSION` bumped in `TabletNotes.xcodeproj` before archiving; Xcode assigns the build number per version string at upload, so 1.0.1's first build is "1", not "51".
- The recovery manifest (`active_recording_manifest`) is the source of truth for which note session belongs to the audio being captured. Nothing may clear it or the session while `RecordingService.isRecording` is true.
- `MainAppView.init` re-runs on every parent re-render (e.g. the auth recheck on foreground). Nothing with side effects may be constructed there.
- Netlify prod auto-deploys on merge to `main`; env-var changes need a manual `netlify deploy --prod`. Supabase migrations are owner-only.
- Two test failures pre-exist on `main` (listed in `docs/OPERATING-MANUAL.md` §3). The simulator used for manual recording carries orphan audio that makes `SermonService*` suites fail there; use the clean 18.5 simulator named in the manual.
- Phone-log capture for device diagnosis: `python3 -m pymobiledevice3 syslog live -m TabletNotes` over USB; grep the `NotesLog` message texts (the category label differs under Xcode debug builds).

## Verification status

- `main` @ d2ac566 (the 1.0.1 archive point): iOS build green on the clean simulator; note/recording suites 60/60 (TAB-113) and 18/18 (TAB-114); `npm test` 235/235.
- This branch: `.claude/hooks/test-hooks.sh` 234/234 (210 upstream Ratchet assertions with the ordinary-push examples retargeted to a feature branch, plus 24 TabletNotes hard-stop/allow assertions); the stop gate run from the repo passes idle and runs `npm test` when an API file is present; `npm test` 235/235. No Swift changed, so no iOS build was required.

## Open risks / assumptions

- App Review may open a fresh Sign in with Apple account again; the Premium row is what carried the last review.
- The auto-stop save handler skips the save if the stop event carries no session id. Unreachable while audio is present (the id resolves via manifest or the fallback provider), but it should fall back rather than skip if that invariant ever changes.
- Crashlytics has shown zero issues since launch; too early to call it stable.

## Integration note

- When this branch merges, this file becomes the `main` state. Nothing else is in flight.

## Last handoff

- Updated: 2026-09-14
- By: agent (Claude Code)
- Branch/worktree: `baise/tab-116-adopt-ratchet-harness`
- Last known-good commit: d2ac566 (main)
