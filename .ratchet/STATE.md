# Ratchet Project State

<!--
Semantic handoff for the current branch/workstream. Keep it short, current, and factual.
Agents update it as meaningful workstream state changes and before handoff.
SAFETY: no secrets, credentials, key ids, personal/customer data, or incident narratives.
Constraints and ticket references only; the history lives in Linear and the PRs.
SCOPE: branch-local; Git integration reconciles branches. Not a session transcript.
-->

## Objective

TabletNotes is live on the App Store (1.0 since 2026-09-11; 1.0.1 with the recording-notes fixes since 2026-09-15). The workstream is post-launch monitoring and the backlog.

## Current phase

Post-launch monitoring. 1.0.1 (build 1) approved and READY_FOR_SALE 2026-09-15. No release in preparation. The Ratchet harness is on `main` (TAB-116).

## Completed

- TAB-119 weekly scripture reminders merged to `main` @ 1f6e8f3 (PR #84, squash, 2026-10-28) after four review rounds. Local notifications scheduled by an idempotent reconciler (`Services/Notification/`), anchored to the recording day (D-20260924-1930, D-20261013-1100, D-20261028-0900). Client-only; lands in the next build. **Device verification is still pending the owner** (permission prompt, banners, tap routing; the manual script is in the PR body).
- TAB-117: added a thin `CODEX.md` adapter that maps the repository's existing risk tiers to Codex models while keeping `AGENTS.md` canonical.
- 1.0 approved and live. The paywall is reachable from the Account tab and Settings in every entitlement state, including the trial (TAB-111, TAB-112).
- Recording notes are now preserved across backgrounding and stop paths (TAB-113, TAB-114; device-verified). History and evidence are in those issues and PRs #76/#77.
- 1.0.1 shipped (TAB-115): TAB-110 client half, TAB-113, TAB-114 all live; all four issues closed 2026-09-15.

## Working on

- Nothing on `main`. In flight on its own branch: TAB-122 job-less sermon reconciliation (`baise/tab-122-reconcile-jobless-sermons`, PR pending owner review); its state is in that branch's copy of this file.

## Next

1. The next release must bump `MARKETING_VERSION` to 1.0.2 or higher before archiving.
2. Watch the owner's daily health check for the first real purchase and for the new build's note-save behavior.
3. Backlog, roughly in order: TAB-103 step 2 (retire the legacy processing path once the durable pipeline has soaked), TAB-33, then TAB-102/104/105 (low).

## Blocked

- None. (App Review is a wait, not a blocker.)

## Important context

- Every release after a live version needs `MARKETING_VERSION` bumped in `TabletNotes.xcodeproj` before archiving; Xcode assigns the build number per version string at upload (see D-20260914-0400 in `DECISIONS.md`).
- The recovery manifest is the source of truth for which note session belongs to the audio being captured. Nothing may clear it or the session while a recording is live (D-20260913-2300).
- Long-lived services are built once at the app root and injected; nothing with side effects is constructed in a SwiftUI view initializer (D-20260914-0000).
- Netlify prod auto-deploys on merge to `main`; env-var changes need a manual `netlify deploy --prod`. Supabase migrations are owner-only.
- Two test failures pre-exist on `main` (listed in `docs/OPERATING-MANUAL.md` §3). A simulator that has been used for manual recording carries orphan audio that makes the `SermonService*` suites fail there. The clean simulator is iPhone 16 Pro / iOS 26.2, id A476D5E8-216E-481B-ADFE-6EB2E52FBEAC; the manual's §3, `AGENTS.md` and the stop hook all name it as of 57e851a (the old 18.5 simulator and runtime were deleted on 2026-10-19). The manual's §3 still says "find another 18.5 one" as the fallback wording; any 18.5-or-newer simulator works.
- Device diagnosis: the app's `NotesLog` category is readable from a phone log stream over USB; the recipe is in the owner's notes and the TAB-113/114 PRs.

## Verification status

- `main` @ 1f6e8f3 (TAB-119 merge; verified on the branch head 13cb373 that was squashed): `xcodebuild build` exit 0; `ScriptureReminderPlannerTests` 40/40 (nine new recording-day anchor tests; six fail with the past-slot drop removed), `ScriptureReminderSchedulerTests` 35/35 (the four race tests, the replacement-then-delete test and the late-summary anchor test each proven to fail with their guard or fix disabled), `SermonServiceDeleteTests` 7/7, `SermonServiceAuthWipeTests` 5/5, `SermonProcessingCoordinatorTests` 4/4, `DurableProcessingWiringTests` 13/13, `CompletedSermonReprocessingGuardTests` 13/13: 117/117, run on an iPhone 16 Pro / iOS 26.2 simulator (A476D5E8-216E-481B-ADFE-6EB2E52FBEAC) because the manual's 18.5 simulator and runtime were deleted while freeing disk space on 2026-10-19. Device verification still pending the owner.

- `main` @ 3a615c5 after TAB-117 / PR #81: `git diff --check` passed and referenced repository files existed; no product code changed, so iOS and backend tests were not required.
- `main` @ d2ac566 (the 1.0.1 archive point): iOS build green on the clean simulator; note/recording suites green (TAB-113: 60/60, TAB-114: 18/18); `npm test` 235/235.
- Harness on `main` @ 0fd39d7 (TAB-116): `.claude/hooks/test-hooks.sh` 261/261 (upstream Ratchet assertions with the ordinary-push examples retargeted to a feature branch, plus the TabletNotes hard-stop/allow assertions: implicit pushes while `main` is checked out or tracked, ANSI-C quoted flags, process substitution, aliases behind global options); the stop gate run from the repo passes idle and runs `npm test` when an API file is present; `npm test` 235/235. No Swift changed, so no iOS build was required.

## Open risks / assumptions

- TAB-119: reminders depend on the summary carrying scripture. Two upstream gaps found on the first device test (2026-10-14) and filed: TAB-120, the summarize model returns narrative without the Scripture References section about a third of the time; TAB-121, the analyzer cannot read spoken references ("Joshua 14, verse 12") or a written one that follows another word ("in Romans 8:28"), so the transcript fallback is weak until it is fixed. Neither is in PR #84's scope.

- App Review may exercise the app on a fresh Sign in with Apple account (trial state); the always-visible Premium row is what addresses that.
- The auto-stop save handler skips the save if the stop event carries no session id. Unreachable while audio is present, but it should fall back rather than skip if that invariant ever changes.
- Crash reporting has been quiet since launch; too early to call it stable.

## Integration note

- Reconciled after the TAB-119 merge (2026-10-28). The squash carried the branch's copy of this file onto `main`; this pass moves TAB-119 to Completed and notes the TAB-122 branch as the only work in flight. The simulator named in `AGENTS.md`, the manual and the stop hook is now the iPhone 16 Pro / iOS 26.2 sim (57e851a, part of the squash).

## Last handoff

- Updated: 2026-10-28 (TAB-119 merged; STATE reconciled on `main`)
- By: agent (Claude Code, Fable)
- Branch/worktree: `main` (reconcile via `baise/ops-state-after-tab-119-merge`)
- Last known-good commit: 1f6e8f3 (main)
