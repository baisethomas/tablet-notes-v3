# Phase 2: Sync, Auth Isolation & Reliability — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix cross-device sync integrity, auth data isolation, backend abuse gaps, and recover stuck production sermons — one Linear issue per branch/PR, reviewed before merge.

**Architecture:** Work in dependency order: secure local data boundaries first (TAB-36), then sync CRUD correctness (TAB-32 → TAB-35 → TAB-34), backend hardening (TAB-37), ops backfill (TAB-39). Quick UI honesty (TAB-42) can ship early in parallel.

**Tech Stack:** SwiftUI + SwiftData (iOS), Netlify Functions + Supabase (backend), Linear for issue tracking.

---

## Recommended execution order

| Order | Issue | Why this order |
|------:|-------|----------------|
| **0** | Deploy Phase 1 API | TAB-22/23/24/29 fixes must be live before TAB-39 backfill or client recovery works in prod |
| **1** | [TAB-36](https://linear.app/loomlogiclabs/issue/TAB-36) | **Security first** — orphan sermon reassignment is a cross-user data leak on shared devices |
| **2** | [TAB-42](https://linear.app/loomlogiclabs/issue/TAB-42) | Small UI-only PR; no sync conflicts; improves trust during transcription |
| **3** | [TAB-32](https://linear.app/loomlogiclabs/issue/TAB-32) | Delete propagation is isolated; high user-visible impact |
| **4** | [TAB-35](https://linear.app/loomlogiclabs/issue/TAB-35) | Pull dedup before testing push/create fixes across devices |
| **5** | [TAB-34](https://linear.app/loomlogiclabs/issue/TAB-34) | Largest sync change; benefits from TAB-35 merge + stable delete path |
| **6** | [TAB-37](https://linear.app/loomlogiclabs/issue/TAB-37) | Backend-only; deploy independently; protects cost before backfill re-queues AI |
| **7** | [TAB-39](https://linear.app/loomlogiclabs/issue/TAB-39) | Ops/script after app + API reliability fixes are deployed |

**Merge order matches build order.** Rebase each branch onto `main` after the prior PR merges.

---

## Git workflow (all issues)

- **Base branch:** `main` (always pull before branching)
- **Branch names:** use Linear `gitBranchName` (already created locally):
  - `baise/tab-36-sign-out-leaves-all-local-data-orphan-sermons-reassigned-to`
  - `baise/tab-42-summary-tab-shows-no-summary-available-while-transcription`
  - `baise/tab-32-sermon-deletes-never-propagate-to-cloud-ghost-sermons`
  - `baise/tab-35-pull-matches-by-remoteid-only-duplicateunique-constraint`
  - `baise/tab-34-non-atomic-remote-create-orphan-audio-silent-partial-child`
  - `baise/tab-37-backend-rate-limiting-silently-off-without-redis-no-server`
  - `baise/tab-39-backfill-recover-the-61-production-sermons-stuck-without`
- **One issue = one branch = one PR.** No bundling.
- **Commit style:** imperative, scoped (`fix(sync): propagate sermon deletes to cloud`)
- **PR title:** `[TAB-XX] Short description`
- **Do not merge** until reviewed (owner merges)
- **After each merge:** rebase remaining branches onto `main`

```bash
git checkout main && git pull origin main
git checkout baise/tab-XX-...
git rebase main
# implement, commit, push
gh pr create --title "[TAB-XX] ..." --body "..."
```

---

## TAB-36 — Sign-out data isolation & orphan reassignment fix

**Branch:** `baise/tab-36-sign-out-leaves-all-local-data-orphan-sermons-reassigned-to`

**Problem:** Sign-out clears auth only. `migrateExistingSermons` assigns all `userId == nil` rows to the next sign-in — cross-user leak.

**Approach:**
1. **Remove blind orphan migration** in `SermonService.migrateExistingSermons` — never assign nil-userId sermons to an arbitrary new user.
2. **Scope reads by userId** — audit `fetchSermons` / list queries to filter by `authManager.currentUser?.id`.
3. **Sign-out wipe policy** — on sign-out (not account deletion), call `SermonService.deleteAllLocalUserData()` or a lighter variant that clears SwiftData + audio + recovery manifests for the signed-out session. Coordinate with `AccountView.signOut()` and `SupabaseAuthService.signOut()`.
4. **Sign-in** — fresh local store for new user; pull from cloud via existing sync.

**Files:**
- Modify: `TabletNotes/TabletNotes/Services/SermonService.swift` (~660–680, ~613)
- Modify: `TabletNotes/TabletNotes/Services/Auth/SupabaseAuthService.swift` (~274–291)
- Modify: `TabletNotes/TabletNotes/Views/AccountView.swift` (~335–341)
- Modify: `TabletNotes/TabletNotes/Services/Auth/AuthenticationManager.swift` (wire local wipe callback)
- Test: `TabletNotes/TabletNotesTests/Services/` — add sign-out isolation test with mock sermons from two userIds

**Acceptance:**
- [ ] User A signs out; User B signs in — User A's sermons are not visible
- [ ] No sermon gets `userId` reassigned without explicit same-user recovery proof
- [ ] Sign-out clears local audio + SwiftData (or scopes so nothing leaks)

---

## TAB-42 — Summary tab pending state (quick win)

**Branch:** `baise/tab-42-summary-tab-shows-no-summary-available-while-transcription`

**Problem:** `summaryStatus == "pending"` shows "No summary available" during normal transcription.

**Approach:**
1. In `SermonDetailView` summary tab (~407–436), branch on `transcriptionStatus` + `summaryStatus`:
   - Transcription not complete → "Transcribing… your summary will be generated next"
   - Transcription complete, summary pending/processing → existing processing UI
2. Fix `ContentView` / list status chip — don't show green "Ready" when transcription is still pending.

**Files:**
- Modify: `TabletNotes/TabletNotes/Views/SermonDetailView.swift`
- Modify: `TabletNotes/TabletNotes/Views/ContentView.swift` (or status helper)

**Acceptance:**
- [ ] Fresh recording → summary tab shows waiting message, not empty state
- [ ] After transcription completes, normal summary processing UI appears

---

## TAB-32 — Propagate sermon deletes to cloud

**Branch:** `baise/tab-32-sermon-deletes-never-propagate-to-cloud-ghost-sermons`

**Problem:** `SermonService.deleteSermon` is local-only; `delete-sermon.js` exists but is never called. Pull resurrects deleted sermons.

**Approach:**
1. Add `deleteRemoteSermon(remoteId:)` to `SermonSyncRemoteGatewayProtocol` + implementation — `DELETE /.netlify/functions/delete-sermon?sermonId=...` with Bearer token (endpoint already exists).
2. Add `SyncService.deleteSermon(_:)` or call gateway from `SermonService` when user has sync + `remoteId`.
3. Update `deleteSermon`:
   - If premium sync + `remoteId` present → await remote delete, then local delete
   - On remote failure → keep local row OR soft-delete with retry flag (prefer: block delete + show error so user knows cloud copy remains)
4. **Pull side:** if remote sermon list omits a local `remoteId`, optionally prune local row (future enhancement; not required if delete API is reliable).

**Files:**
- Modify: `TabletNotes/TabletNotes/Services/Sync/SermonSyncRemoteGateway.swift`
- Modify: `TabletNotes/TabletNotes/Services/Sync/SyncService.swift`
- Modify: `TabletNotes/TabletNotes/Services/SermonService.swift` (~849–862)
- Modify: `TabletNotes/TabletNotes/Views/SermonListView.swift` (async delete + error alert)
- Reference: `tablet-notes-api/netlify/functions/delete-sermon.js`

**Acceptance:**
- [ ] Delete on device A → device B pull no longer shows sermon
- [ ] Offline delete queues and pushes on next sync (or surfaces error — pick one, document in PR)

---

## TAB-35 — Pull dedup by localId

**Branch:** `baise/tab-35-pull-matches-by-remoteid-only-duplicateunique-constraint`

**Problem:** Pull only matches `remoteId`. Local row with same UUID but unset `remoteId` causes duplicate insert / unique constraint.

**Approach:**
1. Add `findSermon(localId: UUID)` to `SermonSyncLocalRepositoryProtocol`.
2. In `pullSermonFromCloud` (`SyncService.swift` ~172–218):
   - Try `findSermon(remoteId:)` first (existing)
   - Else try `findSermon(localId: remoteSermon.localId)` → link `remoteId`, merge fields, skip create
   - Else create new local row
3. Mirror push-side 409 handling logic for consistency.

**Files:**
- Modify: `TabletNotes/TabletNotes/Services/Sync/SermonSyncLocalRepository.swift`
- Modify: `TabletNotes/TabletNotes/Services/Sync/SyncService.swift` (~172–218)
- Test: unit test — local sermon without remoteId + pull same localId → single row with remoteId set

**Acceptance:**
- [ ] Failed push + successful pull does not duplicate
- [ ] `remoteId` linked on existing local row

---

## TAB-34 — Atomic remote create

**Branch:** `baise/tab-34-non-atomic-remote-create-orphan-audio-silent-partial-child`

**Problem:** Audio uploads before API create; partial child inserts return 201 anyway.

**Approach (backend first):**
1. **`create-sermon.js`:** Wrap notes/transcript/summary inserts in transaction semantics — if any child insert fails, return 5xx and do not return success. Include `syncedScopes` in response body.
2. **Orphan audio cleanup:** On sermon row insert failure after upload, delete uploaded storage object.
3. **Client (`SermonSyncRemoteGateway.createRemoteSermon`):** Only clear dirty flags for scopes the server acknowledged. On failure after upload, leave sermon dirty for retry; optionally delete orphan via cleanup endpoint.

**Files:**
- Modify: `tablet-notes-api/netlify/functions/create-sermon.js` (~102–214)
- Modify: `TabletNotes/TabletNotes/Services/Sync/SermonSyncRemoteGateway.swift` (~23–122)
- Modify: `TabletNotes/TabletNotes/Services/Sync/SermonSyncLocalRepository.swift` (`markSermonSynced` scopes)
- Test: API test — child insert failure returns non-2xx

**Acceptance:**
- [ ] Create failure does not leave client thinking sync succeeded
- [ ] No orphan audio without corresponding sermon row (best-effort cleanup)

---

## TAB-37 — Backend rate limiting & tier enforcement

**Branch:** `baise/tab-37-backend-rate-limiting-silently-off-without-redis-no-server`

**Problem:** Rate limiter no-ops without Redis; AI endpoints don't check tier; live token defaults to `pro`.

**Approach:**
1. **Verify Netlify env:** document required `UPSTASH_REDIS_*` vars; add startup warning log if missing.
2. **`rateLimiter.js`:** Fail closed or use conservative in-memory limiter when Redis absent (dev only).
3. **Shared tier helper:** read `profiles.subscription_tier`, default `'free'`.
4. Apply to `transcribe.js`, `summarize.js`, `assemblyai-live-token.js`.
5. Enforce product rules (e.g. live transcription = premium only).

**Files:**
- Modify: `tablet-notes-api/netlify/functions/utils/rateLimiter.js`
- Modify: `tablet-notes-api/netlify/functions/transcribe.js`
- Modify: `tablet-notes-api/netlify/functions/summarize.js`
- Modify: `tablet-notes-api/netlify/functions/assemblyai-live-token.js`
- Create: `tablet-notes-api/netlify/functions/utils/subscriptionTier.js` (shared helper)

**Acceptance:**
- [ ] Redis configured in prod (manual checklist in PR)
- [ ] Missing tier metadata defaults to `free`, not `pro`
- [ ] Free user blocked from premium-only endpoints (per product spec)

---

## TAB-39 — Production backfill (ops)

**Branch:** `baise/tab-39-backfill-recover-the-61-production-sermons-stuck-without`

**Prerequisites:** Phase 1 merged + deployed; TAB-22/23 client in App Store build; TAB-37 deployed (cost protection).

**Approach:**
1. Add script `tablet-notes-api/scripts/backfill-stuck-sermons.js` (service role):
   - Query stuck sermons by status
   - Reset `transcription_status` / `summary_status` to re-queueable states
   - Optionally invoke transcribe/summarize for rows with storage audio
2. Document runbook in PR (dry-run SQL, execute, verify counts).
3. Verification query:
   ```sql
   SELECT transcription_status, summary_status, count(*)
   FROM sermons GROUP BY 1, 2;
   ```

**Acceptance:**
- [ ] Stuck counts trend to zero after backfill + client recovery
- [ ] Runbook reviewed before production execution

---

## PR review checklist (for owner)

For each PR:
- [ ] Single Linear issue linked in title/body
- [ ] Rebased on latest `main`
- [ ] No unrelated changes
- [ ] Manual test steps documented
- [ ] Backend PRs note Netlify deploy requirement

---

## Out of scope (Phase 3 backlog)

- **TAB-38** — Free tier cross-device product decision (docs, not code)
- **TAB-46** — Duration=0, sync status UI honesty
- **TAB-33** — Basic summary fallback (if still open)
