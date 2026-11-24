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

- TAB-126 merged to `main` @ a6ccf89 (PR #91): the Granted AI Help Scout mailbox routes to Linear team LOO and the Granted AI project. The live `SUPPORT_INBOX_ROUTES` env update is operator-reserved; whether it has been applied is not verified here.
- TAB-119 weekly scripture reminders merged to `main` @ 1f6e8f3 (PR #84, squash, 2026-10-28) after four review rounds. Local notifications scheduled by an idempotent reconciler (`Services/Notification/`), anchored to the recording day (D-20260924-1930, D-20261013-1100, D-20261028-0900). Client-only; lands in the next build. **Device verification is still pending the owner** (permission prompt, banners, tap routing; the manual script is in the PR body).
- TAB-117: added a thin `CODEX.md` adapter that maps the repository's existing risk tiers to Codex models while keeping `AGENTS.md` canonical.
- 1.0 approved and live. The paywall is reachable from the Account tab and Settings in every entitlement state, including the trial (TAB-111, TAB-112).
- Recording notes are now preserved across backgrounding and stop paths (TAB-113, TAB-114; device-verified). History and evidence are in those issues and PRs #76/#77.
- 1.0.1 shipped (TAB-115): TAB-110 client half, TAB-113, TAB-114 all live; all four issues closed 2026-09-15.

## Working on

- TAB-138 [PR open, owner review] on `baise/tab-138-evaluation-harness-for-choosing-the-gpt-4o`: an evaluation harness for the summarize/chat model replacement (`gpt-4o-mini` is being retired in January 2027, per the owner) at `tablet-notes-api/scripts/model-eval/`; read its `README.md` for the standards. Runs on 2026-11-22 (12 of the owner's own transcripts, two judges) and 2026-11-23 (30 transcripts, one judge): `gpt-6-luna` with the output cap raised to 5000 tokens passed every gate on the two-judge run; the one-judge run agreed but counts only as provisional under the harness's own two-vendor standard, and neither local run can be re-reported since the review rounds tightened the evidence rules (no hashed judgments, recorded plan or input snapshot), so confirming the result under the final rules needs a new run, which the owner has not yet approved. It runs at about three times the incumbent's latency (p95 about 35 s against the 55 s abort); no candidate works as a model-string-only swap at the current 2000-token cap. No production code changed. The swap itself is out of scope for TAB-138, has no issue yet and needs the owner's choice of model.
- TAB-122 merged to `main` @ 414d6fc (PR #85); the text that follows is that branch's own handoff, written before the merge, and the post-merge check it names (the five sermons gaining job rows) is not verified here. Sermons with a non-terminal stage and no `processing_jobs` row were invisible to both the reaper (iterates jobs) and the client sweep (re-asks only for pending/failed), so they read "processing" forever. Fix: `jobs-reaper-background` runs a step 0 before its job fetch that writes the missing queued row (same payload and idempotency key as `jobs.js`, `ON CONFLICT DO NOTHING`, capped at 10 per sweep, stored path re-authorized with `isOwnedObjectPath`, fails closed on any lookup error, isolated so it never stops the sweep). A sermon that already has a transcript gets its stage advanced instead of a re-billed job. Pure logic in `utils/joblessSermons.js`. Review round 1 (2026-11-23) fixed two findings: a summary stage whose server transcript is under the 50-character floor now stops as `too_short` and one with no server transcript is skipped as `no_transcript` (a job there only failed into `failed_permanent`), and the scan pages (`collectJoblessPlan`) so candidates that can never be acted on cannot fill a fixed window. Open for the owner: the `no_transcript` sermons (12 in prod) stay non-terminal with no job, and the round-1 "should fix" items listed in the PR body are not addressed. Next: owner review, merge on the owner's say-so, then verify the five sermons named in TAB-122 gain job rows. Follow-ups filed: TAB-123 (widen the client sweep to `processing`/`preparing`), TAB-124 (refuse to upload recovered audio with no `moov` atom), TAB-125 (daily health metric counts job-less and dead-job sermons), TAB-139 was filed for Ternary's blocking round-2 finding (the scan read the same first 1,000 candidates every sweep) and is now fixed on this branch instead: past 1,000 candidates the scan starts at a random page and wraps, so every candidate is reached; close TAB-139 when PR #85 merges. Round 3 (Ternary, blocking): a stage repair could land after a client had created a job for that stage; each repair now re-checks for a job first (`applyRepairsUnlessJobAppeared`), which narrows the gap to one round trip, and the atomic fix (a database function, so a migration) is TAB-140.

## Next

1. The next release must bump `MARKETING_VERSION` to 1.0.2 or higher before archiving.
2. Watch the owner's daily health check for the first real purchase and for the new build's note-save behavior.
3. Backlog, roughly in order: TAB-103 step 2 (retire the legacy processing path once the durable pipeline has soaked), TAB-33, then TAB-102/104/105 (low).

4. Redesign (planned 2026-11-22, no code yet): the agreed plan is the Linear project document "Tablet Notes redesign plan"; releases 1.0.2 through 1.4 are parent issues TAB-128 to TAB-132, all in Backlog until the owner says go. Visual direction "D" with a gold accent was chosen from a throwaway prototype (verdict on TAB-128). The prototype lives untracked at `prototypes/redesign-2026-11/` as the visual reference for release 1.1; never commit it (it holds sermon transcript excerpts) and delete it once 1.1 is built.

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

- TAB-122 branch after review round 1, rebased onto `main` @ a6ccf89: `npm test` 291/291 (49 in `joblessSermons.test.js`; disabling the transcript check fails five tests, disabling paging fails five, disabling the rotation fails four, disabling the pre-repair job re-check fails two), `node --check` on the reaper. A read-only prod query on 2026-11-23 predicts 7 transcription jobs, 7 stage repairs, 2 summary jobs, 2 `too_short`, 12 `no_transcript` skips and 23 has-job skips. The reaper's own Supabase wiring has no test (functions have no harness) and has not run in production; that happens on merge.
- TAB-126 (merged as PR #91; this was run on the PR branch before the merge): `cd support-automation && npm test` — 49/49 pass. `rg ec3442ea support-automation` empty. `rrr.sh --base 431c343` on `committed .env.example routes mailbox 371514 to LOO and the Granted AI project` (fix file `support-automation/.env.example`) reported `RRR: PROVEN`; phase 2 failed on GRA team id `ec3442ea-…` vs LOO `60112c28-…`. No cross-routing bug found; `linearProjectId` already reached Linear issue creation.
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

- Updated: 2026-11-23 (TAB-138 evaluation harness; PR #92 open, review rounds 1 to 6 addressed)
- By: agent (Claude Code, Fable)
- Branch/worktree: `baise/tab-138-evaluation-harness-for-choosing-the-gpt-4o`
- Last known-good commit: 414d6fc (main, merged into this branch); branch verified with `npm test` 341/341, which now includes the harness's 50 tests
