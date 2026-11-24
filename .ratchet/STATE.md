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

- TAB-138 [PR open, owner review] on `baise/tab-138-evaluation-harness-for-choosing-the-gpt-4o`: an evaluation harness for the summarize/chat model replacement (`gpt-4o-mini` is being retired in January 2027, per the owner) at `tablet-notes-api/scripts/model-eval/`; read its `README.md` for the standards. Runs on 2026-11-22 (12 of the owner's own transcripts, two judges) and 2026-11-23 (30 transcripts, one judge): `gpt-6-luna` with the output cap raised to 5000 tokens passed every gate on the two-judge run; the one-judge run agreed but counts only as provisional under the harness's own two-vendor standard, and neither local run can be re-reported since the review rounds tightened the evidence rules (no hashed judgments, recorded plan or input snapshot), so confirming the result under the final rules needs a new run, which the owner has not yet approved. Those runs also sent each tuned candidate's raised summary token cap to the two chat calls (fixed in review round 8: `params` is now summary-only, `chatParams` is separate), so their chat-contract results for tuned candidates were not measured at production's caps. It runs at about three times the incumbent's latency (p95 about 35 s against the 55 s abort); no candidate works as a model-string-only swap at the current 2000-token cap. No production code changed. The swap itself is out of scope for TAB-138, has no issue yet and needs the owner's choice of model.
- TAB-141 merged to `main` @ c29d65a (PR #93, squash, 2026-11-24), deployed and verified in prod. Every sermon stage write guarded by "only while the stage has not already stopped" was rejected by PostgREST with 400 (`column sermons.<stage column> does not exist`) and wrote nothing: the guard was sent as an `or=(...)` filter with `select=id`, and on an update PostgREST re-applies `or`/`and` filters to the returned rows, which carry only the selected columns. Found on 2026-11-23 when the first reaper sweep after TAB-122 had all 9 of its stage repairs rejected. Four callers share the call: the reaper's job-less repairs, the dead-job `failed_permanent` write-back (`processingJobs.js`), `completeTranscription.js`, and `applyStageStatusWrites` (update-sermon). Fix: `updateWhileStageNotTerminal` in `utils/sermonStatus.js` sends plain filters only (`not.in` the terminal list, then `is.null` if that matched nothing). Do not put an `or`/`and` filter on a PostgREST update that returns a narrower `select`, and do not "fix" it by selecting the filtered column: the filter would then be tested against the new value. The helper throws on a missing or empty `scope`. Its two requests are not one atomic step for a NULL stage column (a concurrent non-terminal write between them skips the write; a terminal state is still never overwritten); TAB-140 covers that.
- TAB-122 merged to `main` @ 414d6fc (PR #85, squash, 2026-11-23) and deployed. Job creation is verified in prod: the first sweep created 9 jobs (7 transcription, 2 summary) as predicted. Its stage repairs (7 to `complete`, 2 to `too_short`) were rejected until TAB-141 shipped and landed on the first sweep after it. TAB-139 closed (fixed inside PR #85). Open: TAB-140 (make "no job exists" and the stage repair one atomic database step; needs a migration), TAB-123/124/125, the 12 `no_transcript` sermons that stay non-terminal with no job, and the round-1 "should fix" items listed in the PR #85 body. Prod also has 23 dead transcription jobs since 2026-08-19 whose sermon never reached `failed_permanent`; that fits TAB-141 but is not proven, and those rows are not healed by the fix (dead jobs are not retried); a backfill would be a prod write that needs the owner's go-ahead.

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

- TAB-141 on `main` @ c29d65a: `npm test` 301/301 before merge (10 new in `stageWriteRequest.test.js`, which run the real Supabase client against a stand-in PostgREST that rejects an `or`/`and` filter the way production did; with the old `or` filter restored 13 tests fail), `node --check` on `sermonStatus.js`, the reaper and `update-sermon.js`. In prod after deploy (read-only, 2026-11-24 06:55 UTC sweep): all 9 pending repairs landed (7 to `transcription_status = complete`, 2 to `summary_status = too_short`), the 9 `PATCH /rest/v1/sermons` requests carrying `not.in.` returned 200, and the Postgres log has no `column sermons.* does not exist` errors since the merge. The `is.null` follow-up request has not run against real PostgREST (no NULL stage columns exist).
- TAB-122 on `main` @ 414d6fc: `npm test` 291/291 before merge. In prod after deploy (read-only, 2026-11-23 21:30 UTC sweep): 9 jobs created, 4 sermons transcribed with summary jobs chained, 1 `no_speech`, 2 summary stages `complete`, 2 jobs failing transcoding; all 9 stage repairs rejected with 400 (TAB-141).
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

- Updated: 2026-11-24 (TAB-138 evaluation harness; PR #92 open, review rounds 1 to 9 addressed; Ternary has no blocking findings)
- By: agent (Claude Code, Fable)
- Branch/worktree: `baise/tab-138-evaluation-harness-for-choosing-the-gpt-4o`
- Last known-good commit: d96db0f (main, merged into this branch); branch verified with `npm test` 384/384 after merging `main`, which includes the harness's 83 tests
