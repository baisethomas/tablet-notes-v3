# Android / Google Play Port Plan

**Date:** 2026-07-07
**Status:** Draft — pending owner approval of approach and timing

## Summary

Port TabletNotes to Android as a **native Kotlin + Jetpack Compose app** that reuses the
existing backend (Netlify functions + Supabase + AssemblyAI) unchanged except for one
addition: Google Play purchase verification. The iOS client is ~26k lines of Swift across
98 files, but a large share of the product's complexity (transcription, summarization,
Bible proxy, chat, rate limiting, purchase verification) already lives server-side, so the
Android app is primarily UI + audio recording + local persistence + sync orchestration
against APIs that already exist.

**Recommended timing:** after the iOS launch ships. Phase 2 launch-readiness is still in
flight (TAB-53 acceptance done, TAB-55 rate-limit fix and TAB-56 deploy pending), and
several of those backend fixes are prerequisites for Android too. Starting the port now
would split focus across two unlaunched clients.

## Approach decision

| Option | Verdict |
|---|---|
| **Native Kotlin + Compose** | **Recommended.** Best UX/store fit, no new framework risk, backend does the heavy lifting so the rewrite surface is manageable. Two codebases is the honest long-term cost. |
| Kotlin Multiplatform | Poor fit today: shared logic is currently written in Swift, so KMP means rewriting it in Kotlin *and* refactoring the working iOS app to consume it. Revisit only if the two codebases drift painfully. |
| Flutter / React Native | Requires throwing away the launch-ready SwiftUI app or maintaining it alongside a third stack. Wrong timing. |
| Skip (Swift→Kotlin transpiler) | Tempting given the SwiftUI + @Observable codebase, but SwiftData, AVAudioRecorder delegate callbacks, StoreKit 2, and the recovery-manifest machinery are exactly the parts transpilers handle worst. Too risky as the foundation of a paid product. |

## What transfers as-is (no work)

- All Netlify functions except purchase verification: `create-sermon`, `update-sermon`,
  `get-sermons`, `delete-sermon`, `generate-upload-url`, `transcribe`, `transcribe-status`,
  `summarize`, `chat`, `bible-api`, `assemblyai-live-token`, `delete-account`.
- Supabase schema, RLS, storage buckets, auth backend.
- AssemblyAI integration, AI summary prompts, Bible translation catalog data (port the
  curated list from `BibleTranslationCatalog.swift`).
- The sync protocol itself — `SermonSyncRemoteGateway` shows the client only speaks to the
  Netlify API, so the Android sync engine implements the same two-phase contract.

## Component mapping (iOS → Android)

| iOS | Android |
|---|---|
| SwiftUI + `@Observable` MVVM | Jetpack Compose + ViewModel/StateFlow |
| SwiftData (`Sermon`, `Transcript`, `Summary`, `Note`, `ProcessingJob`) | Room entities, same shapes; keep `local_id` UUID scheme so sync is identical |
| `AVAudioRecorder` + recovery manifest | `MediaRecorder`/`AudioRecord` inside a **foreground service** (`microphone` type — required for recording with screen off) + same recovery-manifest pattern |
| `SermonProcessingCoordinator` background jobs | WorkManager chains |
| StoreKit 2 + `verify-purchase` | Play Billing Library v7 + new backend Google verification |
| Keychain | Android Keystore + EncryptedSharedPreferences |
| Sign in with Apple / Google | Google Sign-In (Credential Manager); Apple sign-in via Supabase OAuth web flow so existing Apple-auth users can log in on Android |
| `NetworkRetry.withExponentialBackoff()` | same policy, OkHttp interceptor or suspend wrapper |
| `NetworkMonitor` | `ConnectivityManager` callback flow |

## Phases

### Phase 0 — Prerequisites (parallel with iOS launch wrap-up)
- Google Play Console developer account ($25 one-time). **Note:** personal accounts must
  run a closed test with 12+ testers for 14 days before production access — start this
  clock early.
- Package name (e.g. `com.tabletnotes.app`), signing key via Play App Signing.
- Data safety form + privacy policy (audio recording + AI processing must be declared).
- Finish deploying the pending backend fixes — **TAB-55 (upload rate limit / pull
  starvation) and TAB-56 (notes timestamp) are Android prerequisites too**, since the
  Android client inherits the same sync semantics.

### Phase 1 — Backend: Google purchase verification (~1 week)
- `utils/googlePurchase.js`: verify purchase tokens server-side via the Play Developer API
  (service-account JSON in Netlify env, `androidpublisher` scope), derive tier from the
  verified payload — mirror of `applePurchase.js`'s fail-closed design.
- Extend `verify-purchase.js` to accept `platform: "ios" | "android"` and route
  accordingly; upsert the same `profiles` subscription columns.
- Real-Time Developer Notifications (Pub/Sub) for refunds/renewals = follow-up, same as
  the Apple ASSN follow-up.
- Unit tests in the existing `npm test` suite.

### Phase 2 — Android foundation (~2–3 weeks)
- Project scaffold: Kotlin, Compose, Hilt, Room, OkHttp/Retrofit (or Ktor), Coroutines.
- Auth: Supabase (supabase-kt) email + Google + Apple-web-OAuth; session storage in
  Keystore.
- Room schema mirroring the SwiftData models, including sync-flag fields.
- API client for the Netlify functions with exponential backoff and `retryAfter` respect
  (learn from TAB-55: honor 429s from day one).

### Phase 3 — Sync engine (~2 weeks)
- Port the two-phase engine with the TAB-53/55 lessons baked in from the start:
  **pull-first on fresh install**, per-item error isolation, push failure must not starve
  pull, honest success accounting before clearing any flags.
- Reuse the iOS test scenarios (merge tests, partial-failure pulls) as Kotlin unit tests.

### Phase 4 — Recording + processing (~3 weeks)
- Foreground-service recorder with notification, pause/resume, interruption handling
  (calls, audio focus loss), recovery manifest written synchronously after start.
- Upload via `generate-upload-url`, then transcription/summary job tracking through
  WorkManager, mirroring `ProcessingJob`.
- This is the highest-risk phase: Android audio has more device variance (OEM battery
  killers, audio focus quirks) — budget real-device testing across Samsung/Pixel at least.

### Phase 5 — Feature UI (~3–4 weeks)
- Sermon list (with the TAB-54 disambiguation fixes designed in from the start), detail
  view with transcript/summary/notes tabs, note-taking during recording, Bible browser +
  translation picker (curated catalog), chat, settings, account/onboarding.

### Phase 6 — Billing + tier gating (~1–2 weeks)
- Play Billing products matching the iOS tiers; purchase → backend verify → profile upsert;
  restore/ownership checks on launch; gate AI features by verified tier exactly as iOS does.

### Phase 7 — QA + release (~2–3 weeks, overlaps earlier phases)
- Closed testing track (the mandatory 12-tester/14-day window for personal accounts).
- Cross-platform sync test matrix: record on iOS → view on Android and vice versa;
  fresh-install restore on Android against a real account (the TAB-53 acceptance suite,
  re-run cross-platform).
- Store listing, screenshots, content rating questionnaire, staged rollout to production.

## Estimate

Roughly **12–16 weeks of focused solo effort** for feature parity. A trimmed v1 (record →
transcribe → summarize → notes → sync, deferring Bible browser and chat) could ship in
**8–10 weeks**.

## Risks

1. **Two codebases forever** — every future feature costs 2×. Accept explicitly, or defer
   the port until iOS revenue justifies it.
2. **Android audio reliability** — OEM battery optimizers kill background recorders; the
   foreground-service + recovery-manifest design mitigates but device-matrix testing is
   non-negotiable for a recording app.
3. **Cross-platform sync bugs** — two writers against one cloud store will surface merge
   edge cases the single-platform tests never hit. The per-item isolation and honest
   accounting work from TAB-53/55 is the foundation; add cross-device integration tests.
4. **Play policy** — apps that record audio get extra review scrutiny; the data safety
   declarations must match actual behavior (audio uploaded to AssemblyAI, AI processing).
5. **Timing** — starting before iOS launches risks shipping neither well.

## Open questions for owner

- Ship full parity or trimmed v1 first?
- Start now or after iOS App Store launch?
- Play Console account: personal (12-tester/14-day gate) or organization (needs D-U-N-S)?
