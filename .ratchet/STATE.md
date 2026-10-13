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

- TAB-117: added a thin `CODEX.md` adapter that maps the repository's existing risk tiers to Codex models while keeping `AGENTS.md` canonical.
- 1.0 approved and live. The paywall is reachable from the Account tab and Settings in every entitlement state, including the trial (TAB-111, TAB-112).
- Recording notes are now preserved across backgrounding and stop paths (TAB-113, TAB-114; device-verified). History and evidence are in those issues and PRs #76/#77.
- 1.0.1 shipped (TAB-115): TAB-110 client half, TAB-113, TAB-114 all live; all four issues closed 2026-09-15.

## Working on

- TAB-119 weekly scripture reminders (branch `claude/sermon-scripture-notifications-07g812`). The owner has approved the plan at `docs/superpowers/plans/2026-09-24-sermon-scripture-notifications.md`. Step 1, the pure planner (`Services/Notification/ScriptureReminderPlanner.swift` plus `TabletNotesTests/Services/ScriptureReminderPlannerTests.swift`), is verified (31/31). Step 2, the scheduler, is written and verified: `Services/Notification/ScriptureReminderScheduler.swift` (protocols `ScriptureReminderNotificationCenter`, `ScriptureVerseFetching`, `ScriptureReminderScheduling`; the live `BibleVerseTextFetcher`) plus `TabletNotesTests/Services/ScriptureReminderSchedulerTests.swift` and `Mocks/MockScriptureReminderNotificationCenter.swift` (18/18; the partial-failure rollback test was mutation-checked). The scheduler takes its notification center and verse fetcher as required init arguments (default arguments are evaluated nonisolated, and `BibleAPIService.init` is main-actor), so the app root builds `BibleVerseTextFetcher(bibleService:)` in step 4. Steps 3 and 4 are done. Permission and the opt-in flag live on the scheduler; `Views/Components/ScriptureReminderViews.swift` holds the Settings row and the opt-in card. Wiring: the scheduler and `BibleVerseTextFetcher` are built once in `TabletNotesApp.init` after the store code (the reset/restore flow is untouched) and passed through `MainAppView` to `SettingsView` and `SermonDetailView`; `SermonProcessingCoordinator` reconciles at the end of every sync pass (the one choke point all lifecycle hooks share), and `SermonService` cancels on delete, archive and user-initiated sign-out through a settable optional. Taps go through `ScriptureReminderTapRouter` (process-wide, installed as the notification delegate in `AppDelegate` before launch finishes) and `MainAppView` routes to the sermon on appear and on change. A DEBUG-only env override `SCRIPTURE_REMINDER_DEBUG_DELAY_SECONDS` fires the run seconds apart for manual checks. **On-device verification is pending the owner**: the simulator has no signed-in session for real summaries, its seeded sermons are outside the 48-hour window, and the permission prompt and the tap need a finger. PR #84 is open with the manual script in its body. Review round 1 (Ternary + Codex, 2026-10-13) is addressed on the branch: the cancel-vs-reconcile race (generation check), the scripture-less-newest-sermon and delete-the-newest cases (the week-owner rule, D-20261013-1100), opt-out preserving the schedule record, and the archive cancel moved to `toggleSermonArchiveStatus`, which is the path the list actually calls. One Ternary finding was argued as incorrect in the PR (older runs are removed only after the add loop completes). Round 2 (Ternary) closed the last unguarded await before the record is written. The owner reviews, runs the device check, and merges on their say-so.

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
- Two test failures pre-exist on `main` (listed in `docs/OPERATING-MANUAL.md` §3). A simulator that has been used for manual recording carries orphan audio that makes the `SermonService*` suites fail there; use the clean 18.5 simulator named in the manual.
- Device diagnosis: the app's `NotesLog` category is readable from a phone log stream over USB; the recipe is in the owner's notes and the TAB-113/114 PRs.

## Verification status

- TAB-119 branch after review round 1 (2026-10-13): `ScriptureReminderPlannerTests` 31/31, `ScriptureReminderSchedulerTests` 33/33 (the three race tests proven to fail with their guard disabled), `SermonServiceDeleteTests` incl. the new archive-toggle and delete cancel tests, `SermonServiceAuthWipeTests`, `SermonProcessingCoordinatorTests`, `DurableProcessingWiringTests`, `CompletedSermonReprocessingGuardTests`: 105/105. Device verification still pending the owner.

- `main` @ 3a615c5 after TAB-117 / PR #81: `git diff --check` passed and referenced repository files existed; no product code changed, so iOS and backend tests were not required.
- `main` @ d2ac566 (the 1.0.1 archive point): iOS build green on the clean simulator; note/recording suites green (TAB-113: 60/60, TAB-114: 18/18); `npm test` 235/235.
- Harness on `main` @ 0fd39d7 (TAB-116): `.claude/hooks/test-hooks.sh` 261/261 (upstream Ratchet assertions with the ordinary-push examples retargeted to a feature branch, plus the TabletNotes hard-stop/allow assertions: implicit pushes while `main` is checked out or tracked, ANSI-C quoted flags, process substitution, aliases behind global options); the stop gate run from the repo passes idle and runs `npm test` when an API file is present; `npm test` 235/235. No Swift changed, so no iOS build was required.

## Open risks / assumptions

- TAB-119: the scripture analyzer drops a reference that follows another word ("in Romans 8:28"). The planner works around the line-break case only. The transcript fallback is therefore weak until the analyzer is fixed; that fix is a separate issue.

- App Review may exercise the app on a fresh Sign in with Apple account (trial state); the always-visible Premium row is what addresses that.
- The auto-stop save handler skips the save if the stop event carries no session id. Unreachable while audio is present, but it should fall back rather than skip if that invariant ever changes.
- Crash reporting has been quiet since launch; too early to call it stable.

## Integration note

- Reconciled after the TAB-117 merge (2026-09-15). Nothing else is in flight; unrelated working-tree changes were left untouched.

## Last handoff

- Updated: 2026-10-13 (TAB-119 PR #84 review rounds 1 and 2 addressed; device verification pending owner)
- By: agent (Claude Code)
- Branch/worktree: `claude/sermon-scripture-notifications-07g812`
- Last known-good commit: 3a615c5 (main)
