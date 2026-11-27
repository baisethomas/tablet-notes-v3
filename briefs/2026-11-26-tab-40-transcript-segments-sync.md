# Brief: Carry transcript segment timings through sync (TAB-40)

**Project:** Tablet Notes
**Created:** 2026-11-26
**Status:** open

## Task

Fix [TAB-40](https://linear.app/loomlogiclabs/issue/TAB-40/transcript-segments-never-sync-tap-to-seek-broken-on-synced-devices) as the next 1.0.2 foundations item (parent [TAB-128](https://linear.app/loomlogiclabs/issue/TAB-128/redesign-release-102-foundations-analytics-scripture-and-timing-fixes); plan: [Tablet Notes redesign plan](https://linear.app/loomlogiclabs/document/tablet-notes-redesign-plan-968ebcacecea)). Transcript text already syncs, but timing data does not survive a cloud restore, so tap-to-seek is broken on any device other than the recorder. On current `main` @ 7663a0a, push still sends `"segments": NSNull()` from `SermonSyncRemoteGateway`, pull still imports `segments: []` in `SermonSyncLocalRepository` (and `applyTranscriptSnapshot` does not refresh segments on an existing transcript), and `transcriptSyncPayload` silently skips the whole transcript when `TranscriptSnapshotStore` is missing. TAB-40's suggested fix: serialize segments to the existing `transcripts.segments` JSONB on push, deserialize them on pull, and fall back to SwiftData transcript text when the snapshot store is empty.

This is a sync-contract fix, not the sync rewrite. Do not start TAB-74 or any broader persistence rewrite (paused until 1.3). No data-model or schema change: use the existing `transcripts.segments` JSONB. No visual, navigation, or recording-screen changes. Do not bump `MARKETING_VERSION` (TAB-136). Do not start TAB-133.

TAB-128 notes that TAB-40 touches `Services/Sync/` and the `get-sermons` / `update-sermon` contract. That contract is constrained by shipped TAB-93: `get-sermons` currently omits `segments` from the wire, and the client decoder drops jsonb arrays as `nil`, so a single word-timing array cannot fail the entire library import on already-shipped 1.0.1 clients. A complete TAB-40 fix has to let a 1.0.2 client receive and apply segment timings on pull without regressing that 1.0.1 protection. API changes auto-deploy on merge to `main`; the PR must state the deploy note and the 1.0.1 compatibility plan. Record the chosen contract in `.ratchet/DECISIONS.md`. Do not invent a production backfill of rows already stored as null.

Linear (workspace loomlogiclabs, team TAB) is the source of truth.
- Claim TAB-40 before starting: assign or comment, and move it to In Progress.
- The branch and PR include the TAB-40 issue ID.
- New bugs and follow-ups become linked Linear issues before the session ends.
- When the PR opens, move TAB-40 to In Review. Only Baise sets Done.

Do not add new test skips (`-skip-testing` or equivalent) without flagging them in the PR body and in `.ratchet/STATE.md` for Baise to decide. Existing named skips in `.github/workflows/ios.yml` stay unless you actually fix those tests. The Builder should run on Grok and the Verifier on Composer, unless Baise says otherwise.

## Complete means

- [ ] TAB-40 is claimed, a PR is open with the issue ID in the branch and title, and TAB-40 is In Review.
- [ ] Push serializes local transcript segments to the existing `transcripts.segments` JSONB (not `NSNull()` / empty), including when `TranscriptSnapshotStore` is missing and SwiftData still has the transcript.
- [ ] Pull deserializes remote segments onto the local transcript, including a refresh of segments on an already-existing local transcript. A sermon restored onto an empty store has its timing data, so tap-to-seek can work on a non-recorder device.
- [ ] Already-shipped 1.0.1 clients still import a library that includes at least one timed transcript (TAB-93 must not regress). The PR states how 1.0.2 receives segments and how 1.0.1 stays safe, plus the deploy note (API auto-deploys on merge; no migrations).
- [ ] Regression tests cover push, pull, the snapshot-store fallback, and the 1.0.1 compatibility case. `RRR: PROVEN` is in the PR body. Red-before-green is shown: a red commit with CI proof if the failing test is Swift-only, or local/CI test proof otherwise. Any throwaway red branch or draft PR is linked and is not merged.
- [ ] The PR head SHA has a green `ios-simulator` GitHub Actions run. No new test skips were added, or any new skip is flagged in the PR body and in `.ratchet/STATE.md`.
- [ ] The PR head SHA has a green Ternary review check.
- [ ] Ratchet compliance: five-section PR body with a non-empty ASSUMED, `.ratchet/STATE.md` updated (`[open PR #N]`, Last handoff), and medium-impact decisions appended only to `.ratchet/DECISIONS.md`.

## Evidence required

- PR URL and head SHA, plus confirmation TAB-40 is In Review.
- URL of the green `ios-simulator` GitHub Actions run on that head SHA (job name, conclusion, and head SHA).
- URL or screenshot of the green Ternary review check on that same head SHA.
- `RRR: PROVEN` line and the red-before-green proof (red run or local/CI test output, and confirmation any throwaway red branch was not merged).
- Test output for push, pull (including restore onto an empty store / existing-transcript refresh), the snapshot-store fallback, and 1.0.1 compatibility. If a live cloud restore onto a clean simulator was not run, write `skip: <reason>` and show the test that stands in for it.
- The deploy note and 1.0.1 compatibility plan in the PR body, and the DECISIONS.md entry for the chosen contract.
- Confirmation that no new unflagged test skips were added, and that no schema migration or sync rewrite landed.

## Ratchet repos

If the repo has `.ratchet/`, follow its AGENTS.md:
- Update `.ratchet/STATE.md`: tag the PR `[open PR #N]` and update Last handoff.
- Append medium-impact decisions to `.ratchet/DECISIONS.md` (append only; supersede, never edit).
- Write the PR body in five sections: What changed / Shape & why / Verification (split RAN / READ / ASSUMED / INCONCLUSIVE; ASSUMED never empty) / Residue / Handoff.
- Bug fixes include the `RRR: PROVEN` line from rrr.sh.
- Any skipped step is written as `skip: <reason>`.
- The Verifier will fail PRs missing these.

## Reserved for the operator

- merge
- deploy
- send / publish
- pay
- force-push
- production backfill of existing null `transcripts.segments` rows
- making the `ios-simulator` workflow a required status check

## Original intake

> once everything comes back, go ahead and start with the plan

> Yep

(The "Yep" was on 2026-11-26 at 6:51 PM PT, confirming to draft the TAB-40 brief once #101 landed.)

## Notes from the CoS

TAB-120 (#101 @ 7663a0a) and TAB-121 (#102) are merged; this is the remaining 1.0.2 foundations bug before analytics (TAB-133, still waiting on the provider choice) and ship (TAB-136). STATE.md on `main` still describes the TAB-120 branch as open; update it on this PR. `.ratchet/STATE.md` on `main` after a merge is often stale in that way — treat the file on `main` as the starting point, not as live status.
