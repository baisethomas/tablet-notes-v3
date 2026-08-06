# TabletNotes v2 — Execution Plan

## Rewrite from scratch, or strangler?

The request was a complete from-scratch rewrite. The audit supports rewriting **the three rotten cores from scratch** — the audio pipeline, the sync state model, and the job orchestration — but doing it *inside this repo*, subsystem by subsystem (a strangler migration), rather than starting a blank project. The reasons are practical, not sentimental:

1. **Existing users' data must survive.** A greenfield app still has to read every current user's SwiftData store, UserDefaults recovery flags, and the live Supabase schema — i.e., it must carry the exact migration complexity a strangler carries, plus App Store continuity risk (same bundle ID, StoreKit entitlements, keychain sessions) with zero incremental shipping.
2. **~40–50% of the system audited as sound** (sync engine shape, backend utils, service protocols, most UI, the whole vendor stack). A blank repo discards verified, production-hardened code to rewrite things that aren't broken.
3. **Each phase below ships independently and reduces crashes on its own.** A big-bang rewrite delivers nothing until everything works, and this app's history (17 named failure modes in CLAUDE.md) shows exactly how expensive re-learning is.
4. Every crash-causing subsystem **is** rewritten from scratch — new files, new design, old ones deleted. What you asked for happens where it's justified.

If, after reading the audit, you still want a literal greenfield project, `02-v2-architecture.md` is written to serve as its blueprint unchanged — the phases below just lose their incremental shipping property.

---

## Phase 0 — Stop the bleeding (days, not weeks; ship before anything else)

Individual TAB issues, one branch each, against current `main`:

| Fix | Files | Kills |
|---|---|---|
| Never wipe local data on auth *transitions*; require user-initiated sign-out + zero-pending-sync + never touch in-flight recording | `SermonService.swift:101-125, 949-1019` | The worst active data-loss path (audit D1) |
| Count audio-download failures as pull failures; don't clear recovery flags on partial restore | `SyncService.swift:317-339`, `SermonService.swift:1107-1110` | D4 |
| Zero-denominator guard + remove `as!` casts in usage bars | `SettingsView.swift:825-915` | Top UI crash |
| Stop HTML-escaping LLM-bound text; add `serviceType` to Joi schema | `summarize.js`, `validator.js` | Bad summaries, dead feature, token waste |
| Fail-closed rate-limit middleware; ownership binding in `transcribe-status` | `rateLimiter.js:369-373`, `transcribe-status.js:77-88` | Fail-open + cross-tenant transcript read |
| Delete `DISABLE_BUCKET_RLS.sql` + stale root SQL | repo root | RLS footgun |

Backend items require `netlify deploy --prod` per §7 of the operating manual (owner-gated).

## Phase 1 — Audio core rewrite (the crash fix; ~1–2 weeks of focused work)

Build `AudioCaptureEngine` + `StreamingTranscriber` + `RecordingSession` (design in 02 §2.2) as new files with unit tests for interruption/route-change/reconnect sequences. `RecordingView` switches to the new `RecordingViewModel`. Delete `RecordingService`, `AssemblyAILiveTranscriptionService`, and the ObjC exception shim's load-bearing role. Server-side: token lifetime matched to session (one-line function change, deployed together).

**Exit criteria:** recording + live captions run through interruption, route change, network drop, backgrounding, and token renewal in `sim-verify` scenarios without a session teardown; captions can degrade and recover while recording continues untouched.

## Phase 2 — Server-side jobs (the "stuck processing" fix; ~1 week backend + client observer)

`processing_jobs` table + `POST /jobs` + AssemblyAI webhook handler + Realtime subscription + reaper (design in 02 §3.1–3.2). Client gains `ProcessingObserver`; polling and both retry queues are deleted once parity is verified. `withDefaults` middleware applied to all thirteen functions in the same pass.

**Exit criteria:** kill the app mid-transcription → transcript and summary still arrive; job visible in Postgres end-to-end; zero client polling in prod logs.

## Phase 3 — Upload durability (~3–5 days)

TUS resumable upload via background `URLSession`, stable per-sermon paths, orphan reaper for legacy objects.

**Exit criteria:** airplane-mode toggle mid-upload resumes, not restarts; upload completes with the app terminated.

## Phase 4 — Sync & persistence rewrite (the data-integrity fix; ~2–3 weeks, the deepest change)

v2 schema (`serverVersion`, tombstones, enum statuses) + `SermonStore` `@ModelActor` + outbox + per-entity versioned merge + delta pull (design in 02 §2.3). SwiftData `MigrationPlan` from v1 schema; UserDefaults shadow stores (`MigrationSafety`, `TranscriptSnapshotStore`, `DataMigration` recovery keys) migrated then deleted; `SermonService` decomposed; store-load failure becomes a recovery screen. Supabase gains version triggers + tombstone columns + the missing indexes (additive, backward-compatible with v1 clients during rollout).

**Exit criteria:** property test — no interleaving of edit/push/ack/pull/crash loses an operation; upgrade-migration verified on-device per `sim-verify` against a real v1 store; restore of a large library completes with per-item failure accounting.

## Phase 5 — UI consolidation (ongoing, low risk, parallelizable)

ViewModels for remaining screens, Observation migration completion, god-file splits, `os.Logger`, router. Ships in small PRs throughout.

---

## Sequencing logic

Phase 1 and Phase 2 are independent and can run in parallel; both attack the symptoms you named (crashes, recording errors). Phase 4 is deliberately *after* the bleeding stops — it's the largest change and needs the calmest ground. Each phase = one or more TAB issues per the house one-issue-one-PR rule; each PR states migration impact and deploy requirements per the operating manual.

## What "done" means for the rewrite as a whole

- Crash-free sessions ≥ 99.8% in Crashlytics with the audio core deployed.
- Zero code paths that can delete un-synced user audio.
- A transcription survives app death at any point after upload completes.
- No `@unchecked Sendable`, no `DispatchQueue` in new code, no polling loops, no UserDefaults persistence of user content.
- Every long-running process inspectable server-side (`processing_jobs` row) or on-device (typed state).
