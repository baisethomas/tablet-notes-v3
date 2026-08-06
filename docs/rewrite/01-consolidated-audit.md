# TabletNotes Rewrite Audit — Consolidated Findings

**Date:** 2026-08-06
**Question asked:** "We've done a lot of hardening. Did we harden bad code? Is the stack itself a bottleneck?"
**Method:** Four independent deep audits — (1) recording/live-transcription pipeline, (2) data & sync layer, (3) backend + services stack, (4) app/UI layer — each with file:line evidence.

---

## The verdict in one paragraph

**Yes — in three specific places, the hardening was competent patching of designs that cannot be made safe.** The recording/live-caption pipeline, the sync dirty-flag state model, and the client-orchestrated backend job flow are architecturally wrong, and every crash-fix commit of the last several months has been scaffolding around them rather than fixing them. The remaining ~40–50% of the system — the sync *engine* shape, the Supabase/AssemblyAI/OpenAI stack choice, the backend utility hygiene, the service protocols, and most of the UI — is sound and worth keeping. The right move is a **from-scratch rewrite of the three rotten cores** with a strangler migration, not a greenfield restart of the whole product (see `03-execution-plan.md` for why).

---

## Part 1 — The three subsystems where we hardened bad code

### 1. The recording + live-caption pipeline (root cause of the crash volume)

**The design defect:** during a live-captioned recording, **two independent audio capture stacks run simultaneously against one shared `AVAudioSession`**:

- `RecordingService` records to disk with `AVAudioRecorder` (`Services/Recording/RecordingService.swift:313`)
- `AssemblyAILiveTranscriptionService` spins up a *second* capture path — its own `AVAudioEngine` + input tap (`Services/Transcription/AssemblyAILiveTranscriptionService.swift:9,533`)

Neither owns the session; each configures/activates it independently and hopes the other's configuration holds (`AssemblyAILiveTranscriptionService.swift:516-531` literally says "Don't reconfigure … RecordingService already set it up"). Every route change (Bluetooth mic, CarPlay, headphones), interruption (call, alarm, Siri), or backgrounding is a race between the two stacks. When the race is lost, `installTap`/`engine.start()` raise **uncatchable Objective-C NSExceptions** and the app dies mid-sermon.

**The hardening that proves the point.** The last ~10 crash-fix commits are all shims around this race, not fixes of it:

- An ObjC exception-catcher shim wrapping `installTap` and `engine.start()` (`fc14ee0`…`195cb20`, `AssemblyAILiveTranscriptionService.swift:656-693`) — needed only because the design makes format races possible.
- WebSocket stale-task identity checks repeated at **seven separate mutation points**, each with a comment explaining a distinct TOCTOU window (`AssemblyAILiveTranscriptionService.swift:288-294, 311, 334, 351, 403, 419, 433, 448, 470, 484, 774`) — needed only because one `@unchecked Sendable` class has its state mutated from four execution contexts (main queue, audio render thread, URLSession delegate queue, ad-hoc `Task`s) with no isolation.
- Manual teardown-ordering rules encoded in comments ("no await between record() and this save", "checked here, on main, immediately before the mutation") — invariants the type system should enforce and doesn't.

**Additional design problems in the same pipeline:**
- 8-minute forced WebSocket teardown/rebuild for token renewal — 12 caption gaps per 100-minute service, each a fresh failure opportunity on church WiFi (`AssemblyAILiveTranscriptionService.swift:33,917-948`; server side `assemblyai-live-token.js:91` requests 600s tokens for 10,800s sessions).
- Connection "established" by sleeping 0.5s (`:272`).
- 1-second polling loop for network state instead of `NWPathMonitor` callbacks (`:41-63`).
- `RecordingService` mixes `@Observable`, five Combine subjects, `Timer`, `NotificationCenter` selectors, and a `DispatchQueue.main.sync` (`RecordingService.swift:451`) that is a textbook deadlock shape.

**Verdict: rewrite.** One capture engine, one session owner, one tap feeding both the disk writer and the streamer, actor-isolated state, generation-counted connections. Detailed design in `02-v2-architecture.md`.

### 2. The sync state model and `SermonService` (root cause of data-loss reports)

The sync *engine* (`SermonSyncEngine` + repository/gateway split, per-scope acks, push/pull phase isolation — TAB-53/55 work) is good and stays. What's rotten is everything around it:

**Live data-loss defects found (severity 1):**

| # | Defect | Trigger | Evidence |
|---|---|---|---|
| D1 | **A failed token refresh wipes every recording and audio file on the device.** Any `authenticated → unauthenticated` transition — including Supabase 5xx, expired refresh token, offline launch — runs `deleteAllLocalUserData()`, which deletes all sermon rows and *every file in AudioRecordings/*, including an in-flight recording. Free-tier users (who cannot sync) lose 100% of their library. | Network condition, not user action | `SermonService.swift:101-125, 916-1019`; `SupabaseAuthService.swift:429-434, 516` |
| D2 | Local notes are deleted because a remote payload omitted them — one truncated `get-sermons` response deletes notes on every device that pulls it (the TAB-56 class of bug, still structurally possible client-side) | Partial backend response | `SermonSyncLocalRepository.swift:447-462` |
| D3 | Edits made during an in-flight push are silently discarded on both sides (dirty flags cleared from a stale snapshot; next pull overwrites local) | Editing during a 60s sync | `SyncService.swift:168-228`; `SermonSyncLocalRepository.swift:82-108, 371-373` |
| D4 | Cloud restore reports success while audio downloads fail, then deletes the recovery catalog that was the only record of those recordings | Any download failure during restore | `SyncService.swift:317-339`; `SermonService.swift:1107-1110` |
| D5 | Entire library (all transcripts + summaries) serialized as JSON into **UserDefaults** as a "migration backup" — tens of MB in the preferences plist; jetsam risk; silently absent if the plist write fails | Large library + migration prep | `MigrationSafety.swift:62-145` |
| D6 | `fatalError` crash-loop if the fallback ModelContainer also fails (disk full, locked WAL) | Disk/container condition | `App/TabletNotesApp.swift:81` |

**Structural causes:** dirty state expressed as five booleans + a stringly-typed status + a `refreshPendingSyncState()` that overwrites intent (this single design choice causes D3 plus the archive-freeze and transcript-stuck bugs); `SermonService` as a 1,558-line god object with ~11 responsibilities including the authority to destroy data; merge logic implemented **twice** with divergent semantics (`SermonService.swift:273-390` vs `SermonSyncLocalRepository.swift:259-347`); three overlapping UserDefaults shadow-persistence layers (`MigrationSafety`, `DataMigration`, `TranscriptSnapshotStore` — transcript sync depends on the UserDefaults cache, *not* the database: `SermonSyncLocalRepository.swift:379-386`); whole-sermon last-write-wins on device clocks (`SyncService.swift:347`); everything on the main actor against one `ModelContext` (no crashes from cross-thread misuse — but the whole persistence layer is a main-thread bottleneck, including full-table fetches and 24-attempt bucket searches per audio file, `SupabaseService.swift:369-424`).

**Verdict: rewrite the state model (outbox + server versions + explicit tombstones), decompose `SermonService`, delete all three UserDefaults shadow stores. Keep the engine's phase structure and per-scope acks.**

### 3. Backend job orchestration (root cause of "processing stuck/failed" errors)

The individual Netlify functions are carefully written — fail-closed tier resolution, server-side JWS receipt verification, careful storage cleanup, per-scope acknowledgments. **But the architecture puts the job lifecycle in the wrong place: the phone.**

- **No server-side record of transcription jobs exists at all.** `transcribe.js:156-176` submits to AssemblyAI and returns the job ID to the client; it is never written to Postgres. Kill the app → the paid, completed transcription is unreachable forever. No reconciliation is possible because the server never knew the job existed.
- **Client foreground-polling instead of webhooks.** The iOS app polls `/transcribe-status` for up to the audio's full duration — ~200 authenticated round trips for a 90-minute sermon — and polling stops the moment iOS suspends the app, so "lock phone after church" = stalled transcription. `validator.js:75-76` even accepts a `webhookUrl` that `transcribe.js` never passes: the webhook plumbing was started and abandoned.
- **The upload is the least resilient transfer possible for the highest-stakes data:** whole file loaded into RAM (`Data(contentsOf:)`), single-shot non-resumable signed PUT, foreground `URLSession` — a 100MB, 2-hour sermon over congested church WiFi that dies at 95% starts from zero, and each retry mints a fresh storage path, leaving orphaned ~100MB objects nothing reaps (`AssemblyAITranscriptionService.swift:184`; `generate-upload-url.js:91,107-109`).
- Six of thirteen functions (the entire sync surface + account deletion + purchase verification) have no rate limiting, no schema validation, no timeout wrapper.
- Transcripts are **HTML-escaped before being sent to OpenAI** — "God's" becomes `God&#x27;s` a thousand times per sermon, degrading every summary and inflating token cost 10-20% (`summarize.js:92-96`, `validator.js:265-272`; the repo's own named failure mode #7, fixed once elsewhere, never applied here).
- The `serviceType` field is silently stripped by Joi (`stripUnknown` + missing key), so the Bible-study/youth/conference prompt differentiation is dead code — every user gets the Sunday-sermon prompt (`summarize.js:72-75`, `validator.js:88-113`).
- `transcribe-status` doesn't bind transcripts to owners (omit `userId` and any authenticated user can read any transcript by ID, `transcribe-status.js:77-88`); per-container circuit breakers that reset on cold start; rate-limit middleware that fails open (`rateLimiter.js:369-373`); non-atomic INCR/EXPIRE; committed SQL that doesn't match prod (the `profiles`/entitlement table has **no schema definition in the repo at all**); `DISABLE_BUCKET_RLS.sql` sitting one `psql -f` away from re-opening a closed cross-tenant leak.

**Verdict: keep the stack, rewrite the orchestration.** Netlify is fine as an API gateway and wrong as a process supervisor — the codebase itself documents fighting the 60s limit repeatedly. Jobs move into Postgres; completion moves to AssemblyAI webhooks + Supabase Realtime; uploads become resumable (TUS) on a background `URLSession` with stable per-sermon paths.

---

## Part 2 — What is *not* rotten (and must not be thrown away)

- **The stack itself: Supabase (Postgres/Auth/RLS/Storage/Realtime), AssemblyAI (async + streaming), OpenAI, Upstash Redis.** Every vendor is the right tool. The bottleneck is architecture, not capacity — no amount of plan upgrades fixes it, and no stack migration is needed.
- **`SermonSyncEngine`'s shape** — phase isolation (a push failure can't starve the pull), per-scope acknowledgment, pull-completeness signal. Painfully earned via TAB-53/55.
- **Backend utilities:** `applePurchase.js` (server-side JWS verification, fail-closed), `subscriptionTier.js` (fails closed on every branch), `storageCleanup.js`, the storage RLS migration.
- **App-layer fundamentals:** protocol-based services with mocks, one `AnyView` in 26k lines, deliberate and documented `@MainActor` decisions, low force-unwrap density, `SummaryService`'s error handling (the pattern the rest should copy).
- **The knowledge in `TabletNotes/CLAUDE.md` §9** — seventeen named production failure modes. A greenfield app would re-learn all seventeen the hard way.
- **UI layer verdict: salvageable.** Its problems (no ViewModel layer, four coexisting DI styles, incomplete Combine→Observation migration, god-files like the 1,560-line `SettingsView`, a NaN-width progress bar and five `as!` casts) are mechanical extractions, not architectural rot.

---

## Part 3 — Why the crashes and errors you're seeing map to these findings

| Symptom you reported | Root cause |
|---|---|
| Recording crashes mid-sermon | Dual capture stacks racing on the shared audio session → uncatchable `installTap`/`engine.start()` NSExceptions (§1.1). The shims reduced frequency; the race remains. |
| "High volume of recording errors" | Live-caption WebSocket forced to reconnect every 8 min; each reconnect is a failure opportunity; failure paths degrade silently or strand sessions (§1.1). Upload failures restart 100MB transfers from zero (§1.3). |
| Processing stuck / summaries missing | No server-side job record + foreground-only polling: backgrounding the app orphans the job (§1.3). |
| Occasional "everything disappeared" reports | D1 (auth-transition wipe), D4 (false restore success), destructive store reset on migration failure (§1.2). |
| Errors persisting despite hardening | The hardening targeted the symptoms (exception shims, stale-task guards, retry queues) because the causes are structural. This is the direct answer to "did we harden bad code": **yes, in these three subsystems.** |

---

## Part 4 — Immediate stop-the-bleeding items (independent of the rewrite)

These are one-file-scale fixes to active data-loss/crash paths and should ship as individual TAB issues **before** rewrite work begins:

1. **D1:** Gate `deleteAllLocalUserData()` behind *user-initiated* sign-out + a zero-pending-sync check; never delete the in-flight recording; never fire on token-refresh failure. (`SermonService.swift:101-125`)
2. **D4:** Count audio-download failures as pull failures; never clear recovery flags on a partial restore. (`SyncService.swift:317-339`)
3. **NaN crash:** zero-denominator guard + remove the five `as!` in `SettingsView.swift:825-915`.
4. **Backend one-liners:** stop HTML-escaping LLM-bound transcripts (`summarize.js:92-96`); add `serviceType` to the Joi schema (`validator.js:88-113`); fix the fail-open rate-limit middleware (`rateLimiter.js:369-373`); require ownership binding in `transcribe-status.js`.
5. **Delete `DISABLE_BUCKET_RLS.sql`** from the repo.
