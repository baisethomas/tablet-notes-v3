# TabletNotes v2 — Target Architecture

The premise is unchanged: churchgoers record a sermon, see live captions, take notes during it, and receive a transcript + AI summary afterward (Otter/Fireflies for church). This document specifies the architecture the rewrite builds toward. It is written to work either as a strangler rewrite inside this repo (recommended, see `03-execution-plan.md`) or as the blueprint for a greenfield app — the design is identical; only the migration path differs.

---

## 1. Design principles (each one traceable to a production failure)

1. **One owner per resource.** Exactly one object owns the `AVAudioSession`, one actor owns each WebSocket, one actor owns persistence writes. (Cause of the crash volume: two owners of the audio session.)
2. **The server owns job lifecycles.** The phone requests work and observes results; it is never the process supervisor. (Cause of stuck processing: the phone was the only record of the job.)
3. **Recording is sacred.** The local audio file is append-only from the moment capture starts until cloud existence is *verified*. No code path may delete audio that isn't confirmed in the cloud; the in-flight recording is never eligible for any cleanup. Sign-out does not destroy data.
4. **State machines, not boolean soup.** Every long-lived process (capture, streaming session, upload, processing job, sync) is an explicit enum state machine with defined transitions. No `isRecording` + `isPaused` + `wasInterrupted` + `isConnected` combinations.
5. **Compiler-enforced concurrency.** Swift 6 strict concurrency, actors for shared mutable state, `AsyncStream` for pipelines. Zero `@unchecked Sendable`, zero `DispatchQueue` in new code, zero manual identity checks — staleness is eliminated structurally (a generation token invalidates old callbacks by construction).
6. **Fail loudly to the user, never silently to the log.** Every failure surfaces as typed state the UI renders. `os.Logger` with privacy redaction replaces 673 `print()`s.

---

## 2. iOS app architecture

### 2.1 Layering

```
Views (SwiftUI, dumb)
  └─ ViewModels (@MainActor @Observable, testable, own screen state machines)
       └─ Domain services (RecordingSession, ProcessingObserver, SyncEngine, Auth, Subscription)
            └─ Infrastructure (AudioCaptureEngine, StreamingTranscriber, SermonStore,
                               UploadManager, APIClient, Logger)
```

- **Composition root** in `TabletNotesApp.init()` builds the whole graph once and injects downward. No `.shared` singletons in new code; no service wiring from `onAppear`.
- **Navigation:** a real `NavigationStack` path owned by an `AppRouter`, replacing the flat-enum hand-rolled router. Deep links and state restoration fall out for free.

### 2.2 The audio core — the heart of the rewrite

**`AudioCaptureEngine`** — the *only* object in the app that touches `AVAudioSession` or audio hardware.

```
final actor AudioCaptureEngine {
    enum State { case idle, preparing, recording(RecordingHandle), paused(RecordingHandle), finishing }

    // ONE AVAudioEngine. ONE input tap. Two consumers of the same buffers:
    //   1. Disk writer: AVAudioFile (AAC/m4a), written on every tap callback.
    //      The file grows continuously; a crash at any point loses at most one buffer.
    //   2. Broadcast: AsyncStream<AudioChunk> (downsampled PCM16 mono) for any
    //      number of observers — the live transcriber, a level meter, etc.
    func start(config: RecordingConfig) async throws -> RecordingHandle
    func pause() / resume() / stop() async -> FinishedRecording
    var audioChunks: AsyncStream<AudioChunk>   // consumers attach/detach freely;
                                               // capture NEVER depends on a consumer
}
```

Why this kills the crash class:
- There is no second `AVAudioEngine`, so there is no session-configuration race — the `installTap` format-mismatch NSException becomes unreachable, and the ObjC shim becomes a belt-and-suspenders guard instead of a load-bearing wall.
- Live captions become a pure *consumer*. If the transcriber dies, capture is untouched (today a transcriber failure can take down the session it shares).
- Interruptions and route changes are handled in exactly one place, as state transitions: `.began` → `paused(handle)`, `.ended(shouldResume)` → attempt resume, route change → tap reinstalled *by the single owner* with the new format.
- The recovery manifest (kept: it's a good idea) is written by the engine atomically to a file in Application Support at `start()`, updated on pause/resume, cleared on verified `stop()` — never UserDefaults, never with an `await` between capture start and manifest write.
- Format conversion to PCM16 mono happens once, in the engine, from `buffer.format` (never a cached format).

**`StreamingTranscriber`** — an actor that consumes `audioChunks` and owns the AssemblyAI v3 WebSocket. It never touches audio hardware.

```
actor StreamingTranscriber {
    enum State { case idle, connecting(generation: Int), streaming(generation: Int),
                 degraded(reason: DegradedReason), stopped }
    var transcript: AsyncStream<TranscriptUpdate>   // partial/final turns
}
```

- **Generation counter instead of identity checks.** Every connection increments `generation`; every callback carries the generation it was armed under; the actor drops anything from an older generation *in one place*. The seven hand-written stale-task guards in v1 collapse into a single structural rule.
- **Reconnection is the normal path, not an emergency:** network drop, token expiry, and interruption all funnel into the same `reconnect()` with exponential backoff and jitter, resubscribing to the chunk stream on success. Captions show a "reconnecting…" state; recording is unaffected (Principle 1: they're decoupled).
- **Token lifetime matched to session** (backend §3.4) removes the 8-minute forced teardown entirely; renewal, when needed, opens the new socket *before* closing the old one (make-before-break) instead of a 500ms-sleep gap.
- Degraded mode is a first-class state: captions can be down while recording continues, and the UI says so honestly.

**`RecordingSession`** — a `@MainActor` domain object composing the two: one per recording, a small state machine the `RecordingViewModel` observes. Owns the note-taking session, the elapsed timer (a single `AsyncTimerSequence`, not `Timer` + main-queue hops), duration limits, and hand-off to processing on stop.

### 2.3 Persistence and sync

**`SermonStore` (@ModelActor)** — the single writer to SwiftData. Everything else (ViewModels, sync, processing observers) goes through it. One merge implementation exists. The main actor reads via lightweight snapshots/`@Query`; heavy work (imports, merges, restore) runs on the store's executor, off the main thread.

**Models (v2 schema):**
- `Sermon`, `Note`, `Transcript` (with segments as a codable blob on the transcript — they sync with it atomically), `Summary`, `ChatThread`.
- Every synced entity carries `serverVersion: Int` (assigned by Postgres, monotonic) and `deletedAt: Date?` (tombstone).
- Status fields are enums, not strings.
- A frozen `VersionedSchema` from day one of v2, with a real `MigrationPlan` from the v1 schema (see 03 §Phase 2 for the migration).

**Sync = outbox + versions + tombstones** (keeps the v1 engine's phase isolation and per-scope acks; replaces its state model):

- **Outbox:** every local edit appends a `SyncOperation(entity, id, changedFields, baseVersion)` row *in the same transaction* as the edit. Push drains the outbox; a server ack deletes that specific row. An edit made during an in-flight push is a new row — the lost-update bug (D3) becomes unrepresentable.
- **Merge is per-entity by `serverVersion`,** never whole-sermon `updatedAt`, never device clocks. Conflict (baseVersion stale) → server wins for that field set, local edit is preserved as a new outbox row on top — no silent loss in either direction.
- **Deletes only via tombstones.** A pull payload omitting an entity means nothing; only `deletedAt` deletes locally (kills D2). Deletes push as tombstone operations; the in-memory `deletedRemoteIds` set is deleted.
- **Delta pull:** `GET /sync?since=<cursor>` returns changes + tombstones + a completeness marker, replacing the full-library-every-60s pull.
- **Sign-out** clears the session and in-memory state only. Local purge is a separate, explicit, user-confirmed operation that refuses while unsynced work exists and never touches audio files that aren't verified in cloud storage (kills D1). Auth-state transitions have *no* destructive side effects.
- Store-load failure → a **read-only recovery screen** (export audio, retry, contact support), not `fatalError`, and audio files are never part of any reset.

### 2.4 Upload & processing (client side)

**`UploadManager`** — background `URLSession` + **TUS resumable upload** to Supabase Storage:
- Stable object path per sermon (`{userId}/{sermonLocalId}.m4a`) — retries resume the same object; the orphan-storage leak disappears.
- Survives app suspension/termination (background session delegate); chunked, so church-WiFi drops cost one chunk, not 100MB.
- Never loads the file into memory.

**`ProcessingObserver`** — replaces both retry queues and all polling. Subscribes to Supabase Realtime on the `processing_jobs` table (§3.2); job state changes push to the device. On app launch it reconciles: any local sermon with `status = recorded` and no job row → (re)request processing. The client *requests* and *observes*; it never supervises.

### 2.5 UI layer (mechanical cleanup, mostly incremental)

- ViewModels first for the two screens with real state machines: `RecordingViewModel`, `SermonDetailViewModel` (audio player + timer + edit logic out of the view structs).
- Finish the Observation migration; delete the Combine bridges, dead `cancellables` sets, and the `ChatTabView` subscription leak.
- Split the god-files (`SettingsView` 1,560 lines → settings/paywall/usage modules; legal prose → bundled resources).
- Fix the known latent crashes (NaN progress width, `as!` numeric casts).
- `os.Logger` everywhere with `.private` redaction on user content.

---

## 3. Backend architecture (same stack, jobs move server-side)

Netlify stays as a thin, stateless API gateway. Supabase Postgres becomes the source of truth for job state. AssemblyAI drives completion via webhooks. Nothing polls.

### 3.1 The processing pipeline (the big change)

```
v1: app → /transcribe → AssemblyAI      app polls /transcribe-status (foreground-only)
                                        app → /summarize → OpenAI (55s budget)

v2: app uploads (TUS, background) → app → POST /jobs {sermonId, kind: transcribe+summarize}
    ├─ INSERT processing_jobs row (idempotency key = sermonId+kind)
    ├─ submit to AssemblyAI with webhook_url
    └─ 202 + job row (client is now free to die)

    AssemblyAI → POST /webhooks/assemblyai (signed)
    ├─ verify signature + job row ownership
    ├─ write transcript to Postgres, bump serverVersion
    ├─ enqueue summary stage (same job row, next state)
    └─ summary completes → write summary row → job.status = done

    Postgres change → Supabase Realtime → device updates instantly
    pg_cron / Netlify scheduled function → reap stale jobs, retry with backoff,
                                           reconcile orphaned AssemblyAI jobs
```

### 3.2 New tables (Supabase migrations become the single source of schema truth)

```sql
processing_jobs (
  id uuid pk, user_id uuid not null, sermon_id uuid not null,
  kind text check (kind in ('transcription','summary')),
  status text check (status in ('queued','submitted','running','done','failed','dead')),
  provider_job_id text, attempts int default 0, last_error text,
  idempotency_key text unique,        -- sermon_id + kind: double-tap = same job
  created_at timestamptz, updated_at timestamptz
)
-- plus: profiles gets a committed schema definition (it has none today);
-- server_version bigint + deleted_at on sermons/notes/transcripts/summaries
-- (trigger-maintained monotonic version per row);
-- indexes: (user_id) on notes/transcripts/summaries, (user_id, updated_at) on sermons
```

This one table retroactively fixes: ownership checks on status reads, idempotency, server-side retry, orphan reconciliation, and billing accountability for AssemblyAI jobs.

### 3.3 Endpoint hygiene

- **One composed middleware:** `withDefaults(handler, {auth, schema, limit, timeout})` applied to *every* function — protection becomes opt-out, not 40 hand-written lines of opt-in. (Today 6 of 13 functions have none.)
- Rate-limit middleware fails **closed** (in-memory hard cap fallback), atomic INCR+EXPIRE via a Lua script; circuit-breaker state moves to Upstash or is deleted.
- `chat`: allowlist roles to `user`/`assistant`, cap context length, add the timeout wrapper.
- LLM-bound text is validated (length/encoding) but **never HTML-escaped**; `serviceType` joins the schema so per-service-type prompts actually run.
- Sync endpoints: `GET /sync?since=`, per-scope acks kept, tombstones included, honest non-2xx on partial failure (unchanged principle, now uniformly applied).
- Delete the dead CORS machinery (native client sends no Origin), the dead `SECURITY_CONFIG.timeouts`, all root `*.sql` files, and `DISABLE_BUCKET_RLS.sql`; `supabase/migrations/` becomes authoritative with a full baseline.

### 3.4 Live-caption tokens

`assemblyai-live-token` issues tokens with `expires_in_seconds` matched to `max_session_duration` (or the provider maximum), keeping the tier gate. The 8-minute client-side renewal churn disappears; the client renews only on reconnect.

---

## 4. What stays exactly as-is

Supabase Auth + RLS policies (incl. the storage RLS migration), `applePurchase.js` + `verify-purchase.js` logic (gains idempotency on `transactionId` + rate limit), `subscriptionTier.js`, `storageCleanup.js`, AssemblyAI as the transcription vendor (both modes), OpenAI `gpt-4o-mini` for summaries/chat, Upstash Redis (expanded role), the Bible/scripture feature set, StoreKit flow, and the CLAUDE.md operating rules — §9's seventeen failure modes remain binding on v2 code.

---

## 5. Testing strategy (what makes v2 stay fixed)

- The audio core is designed for simulation: `AudioCaptureEngine` takes an injectable capture source; `StreamingTranscriber` takes an injectable socket. Interruption/route-change/reconnect sequences become unit tests — the exact scenarios that today only reproduce on a phone in a church basement.
- Outbox sync is property-testable: any interleaving of {edit, push, ack, pull, crash} must never lose an operation. This invariant replaces hope.
- Backend: the `withDefaults` wrapper + job state machine live in `utils/` with `node:test` suites; webhook handler tested against recorded AssemblyAI payloads with signature verification.
- On-device verification stays per `sim-verify` (recording, interruption, upgrade-migration scenarios) before any release.
