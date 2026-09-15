# Ratchet Project State

<!--
Semantic handoff for the current branch/workstream. Keep it short, current, and factual.
Agents update it as meaningful workstream state changes and before handoff.
SAFETY: no secrets, credentials, key ids, personal/customer data, or incident narratives.
Constraints and ticket references only; the history lives in Linear and the PRs.
SCOPE: branch-local; Git integration reconciles branches. Not a session transcript.
-->

## Objective

TAB-118: import the live website into `apps/website` with original history and prepare the existing Vercel project's cutover. iOS 1.0 remains live; 1.0.1 was submitted for App Review separately.

## Current phase

Website import and migration plan prepared on the isolated TAB-118 branch. Production configuration and deployment are unchanged; hosted verification and owner-approved cutover remain pending.

## Completed

- TAB-118 import: source `70d5504` retained as an ancestor of subtree commit `90c27d8`; imported tree exactly matches source. Plan: `docs/superpowers/plans/2026-09-15-website-monorepo-migration.md`.
- TAB-117: added a thin `CODEX.md` adapter that maps the repository's existing risk tiers to Codex models while keeping `AGENTS.md` canonical.
- 1.0 approved and live. The paywall is reachable from the Account tab and Settings in every entitlement state, including the trial (TAB-111, TAB-112).
- Recording notes are now preserved across backgrounding and stop paths (TAB-113, TAB-114; device-verified). History and evidence are in those issues and PRs #76/#77.
- `MARKETING_VERSION` bumped to 1.0.1 for the release (TAB-115).
- TAB-110: backend half live since 2026-09-03; client half rides in 1.0.1.

## Working on

- TAB-118: review handoff and remaining hosted validation; Luna performed exact Git import and named checks, Terra authored website guidance, Astra reviewed cutover/rollback and final documents. Its two sequencing findings were incorporated.

## Next

1. Complete hosted Preview validation and the concrete production approval packet in the migration plan.
2. Owner merges TAB-118 using a MERGE COMMIT (not squash/rebase) to preserve website ancestry. Verify source ancestry on resulting main.
3. Execute approved guarded Vercel repo/root transition, staged Production validation, promotion, and post-cutover checks. Keep old repo/deployment for rollback.
4. Separate release follow-up: on 1.0.1 approval, close TAB-110/113/114/115; retain post-launch stabilization backlog.

## Blocked

- Live Vercel configuration/cutover and PR merge require owner approval. Authenticated Vercel/GitHub access is available. No hosted preview has been created yet.

## Important context

- Correct website Vercel project is `tablet-app-landingpage`; the DIFFERENT `tablet-notes-v3` Vercel project points to the API. Current website root is `.` in old repo; target root is `apps/website` in destination repo. Keep existing domains and environment values. Snapshot and rollback reference are in the plan.
- Website-only migration: keep existing native/backend paths and package managers. No workspace conversion or Android work in TAB-118.
- Every release after a live version needs `MARKETING_VERSION` bumped in `TabletNotes.xcodeproj` before archiving; Xcode assigns the build number per version string at upload (see D-20260914-0400 in `DECISIONS.md`).
- The recovery manifest is the source of truth for which note session belongs to the audio being captured. Nothing may clear it or the session while a recording is live (D-20260913-2300).
- Long-lived services are built once at the app root and injected; nothing with side effects is constructed in a SwiftUI view initializer (D-20260914-0000).
- Netlify prod auto-deploys on merge to `main`; env-var changes need a manual `netlify deploy --prod`. Supabase migrations are owner-only.
- Two test failures pre-exist on `main` (listed in `docs/OPERATING-MANUAL.md` §3). A simulator that has been used for manual recording carries orphan audio that makes the `SermonService*` suites fail there; use the clean 18.5 simulator named in the manual.
- Device diagnosis: the app's `NotesLog` category is readable from a phone log stream over USB; the recipe is in the owner's notes and the TAB-113/114 PRs.

## Verification status

- TAB-118: worker frozen install, explicit TypeScript and Next production build passed on Node 22.14.0 / pnpm 10.15.1; original package/lock unchanged. Root independently verified original-tree equality, source ancestry, TypeScript and production build. Hosted/visual/Production checks remain pending.
- TAB-117 merged in PR #81 at base `3a615c5`.
- Root's isolated port-3028 production server returned expected HTTP 200/content types for homepage, legal routes, OpenGraph and representative launch media; stopped after checks. Hosted preview and visual checks remain pending.
- `main` @ d2ac566 (the 1.0.1 archive point): iOS build green on the clean simulator; note/recording suites green (TAB-113: 60/60, TAB-114: 18/18); `npm test` 235/235.
- Harness on `main` @ 0fd39d7 (TAB-116): `.claude/hooks/test-hooks.sh` 261/261 (upstream Ratchet assertions with the ordinary-push examples retargeted to a feature branch, plus the TabletNotes hard-stop/allow assertions: implicit pushes while `main` is checked out or tracked, ANSI-C quoted flags, process substitution, aliases behind global options); the stop gate run from the repo passes idle and runs `npm test` when an API file is present; `npm test` 235/235. No Swift changed, so no iOS build was required.

## Open risks / assumptions

- App Review may exercise the app on a fresh Sign in with Apple account (trial state); the always-visible Premium row is what addresses that.
- The auto-stop save handler skips the save if the stop event carries no session id. Unreachable while audio is present, but it should fall back rather than skip if that invariant ever changes.
- Crash reporting has been quiet since launch; too early to call it stable.

## Integration note

- TAB-118 is isolated in `/Users/baisethomas/Dev/tablet-notes-tab-118`; original checkout's uncommitted Ratchet and Marketing changes remain untouched. This state is branch-local.

## Last handoff

- Updated: 2026-09-15
- By: agent (Codex)
- Branch/worktree: `baise/tab-118-import-live-website-into-monorepo-and-prepare-vercel-cutover`
- Last known-good import commit: `90c27d8`; website source `70d5504`.
