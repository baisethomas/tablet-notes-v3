# CLAUDE.md — TabletNotes Operating Manual

TabletNotes is an iOS sermon-recording app (SwiftUI + SwiftData) with AI transcription/summarization. Backend: Netlify Functions (`tablet-notes-api/`) + Supabase (Postgres, auth, storage). AssemblyAI does transcription; summaries/chat go through Netlify functions.

This file is the operating manual. Follow it exactly. When it conflicts with your instincts, this file wins — every rule below exists because the opposite already caused a production bug here.

---

## 1. The one paragraph that prevents the worst mistakes

This app records audio that cannot be re-captured. The two unforgivable failures are **losing a user's recording** and **silently reporting success when something failed**. Nearly every serious bug in this repo's history (TAB-34, TAB-50, TAB-53, TAB-55, TAB-56) reduces to one of those. Before you write code, ask: "if this operation half-fails, does the caller find out, and does the user's data survive?" If the answer is unclear, the design is wrong.

---

## 2. Repo map

```
TabletNotes/                          # iOS app (Xcode project root)
  TabletNotes/
    App/TabletNotesApp.swift          # ModelContainer setup + destructive-reset last resort
    Models/                           # SwiftData @Model entities (Sermon, Note, Transcript,
                                      #   Summary, ProcessingJob, ChatMessage) + BibleTranslationCatalog
    Services/
      SermonService.swift             # Sermon CRUD, recovery, cloud restore (largest file)
      Sync/                           # SyncService.swift (SermonSyncEngine = two-phase engine),
                                      #   SermonSyncRemoteGateway, SermonSyncLocalRepository,
                                      #   SyncModels, BackgroundSyncManager
      Recording/RecordingService.swift    # intentionally NOT @MainActor (AVFoundation delegates)
      Processing/SermonProcessingCoordinator.swift  # singleton, background job orchestration
      Transcription/  Summary/        # retry queues (TranscriptionRetryService, SummaryRetryService)
      Auth/                           # AuthenticationManager (@MainActor), SupabaseAuthService
      Subscription/  Bible/  Chat/  Notes/  Notification/  Analytics/
      NetworkMonitor.swift  NetworkRetry.swift
    Views/                            # MainAppView (container), SermonListView, SermonDetailView,
                                      #   RecordingView, SettingsView, + Bible/ Chat/ Components/ ...
  TabletNotesTests/                   # unit tests + Mocks/ + Integration/
tablet-notes-api/                     # Netlify backend (deploy from HERE, it is netlify-linked)
  netlify/functions/                  # one file per endpoint (create-sermon, update-sermon,
                                      #   get-sermons, transcribe, summarize, verify-purchase, ...)
  netlify/functions/utils/            # shared: rateLimiter, security, validator, subscriptionTier,
                                      #   createSermonChildren, applePurchase, bibleEndpoint
  netlify/functions/utils/__tests__/  # node:test suites (the only automated API tests)
  scripts/                            # ops scripts + RUNBOOK-*.md
docs/superpowers/plans/               # phase plans (execution order, acceptance criteria)
```

Root-level `*.sql` / `SYNC_*.md` files in `TabletNotes/` are historical artifacts — read for context, never treat as current schema. Current prod schema truth is the live Supabase database (§8).

---

## 3. Commands (use these exactly)

**iOS build check** (an iOS 18.5 simulator is required; 18.4 fails the deployment-target check):
```bash
xcodebuild build -scheme TabletNotes -destination 'platform=iOS Simulator,id=2BAC53A3-EC5B-40DE-A981-7F7A637A555E'
```
If that simulator ID is gone, find another 18.5 one: `xcrun simctl list devices available`.

**iOS tests** (run the suites your change touches, not the whole target, unless asked):
```bash
xcodebuild test -scheme TabletNotes -destination 'platform=iOS Simulator,id=<18.5-sim>' \
  -only-testing:TabletNotesTests/<SuiteName>
```

**API tests** (fast, run on every backend change):
```bash
cd tablet-notes-api && npm test          # node --test over utils/__tests__/
node --check netlify/functions/<changed-file>.js   # functions have no test harness; at least syntax-check
```

**Deploy backend** (Netlify does NOT auto-deploy — see §7):
```bash
cd tablet-notes-api && netlify deploy --prod
```

**Known pre-existing failures — do not chase, do not "fix" in an unrelated PR:**
- `SyncServiceMergeTests/syncDataIncludesOnlyDirtyChildScopesForExistingRemoteSermon` (fails on main)
- `SermonServiceSaveTests` recovery tests share UserDefaults state — pass in isolation, flake together
If a test fails, check whether it fails on `main` before assuming your change caused it — and never claim your change is clean without that check.

**Xcode project file:** the project uses `fileSystemSynchronizedGroups`. Adding/deleting Swift files under `TabletNotes/TabletNotes/` automatically updates the build target. **Never edit `.pbxproj` by hand.**

---

## 4. Git & PR workflow (how the owner works)

- **One Linear issue = one branch = one PR.** No bundling. If you discover an unrelated bug mid-task, file/flag it (Linear issue or spawn_task) and stay in scope.
- Branch from fresh `main` (`git checkout main && git pull` first). Branch name: Linear's `gitBranchName` (`baise/tab-NN-short-slug`). Local names occasionally drift from Linear's renamed slug — that's fine; never rename an existing branch with an open PR.
- Commits: imperative, scoped, issue-tagged — `fix(sync): propagate sermon deletes to cloud (TAB-32)`. Scopes in use: `sync`, `data`, `api`, `recording`, `transcription`, `bible`, `subscriptions`, `ui`, `ops`, `security`, `docs`, `test`.
- PR title: `[TAB-NN] Short description`. PR body: problem → root cause → fix → how it was tested → **deploy requirement if backend files changed**.
- **The owner reviews and merges. Never merge, never push to `main` directly.**
- Review rounds are normal here (TAB-53 took five). Address each round as its own commit(s), then **update the PR description** — a stale PR description was itself a review finding once. If you disagree with a finding, argue it in the PR, don't silently skip it.
- After an unrelated PR merges, rebase your open branch onto `main`.

---

## 5. iOS conventions (house style — violations are review findings)

### Observation / SwiftUI
- All new services: `@Observable` (iOS 17 Observation), never `ObservableObject` unless a Combine publisher is genuinely required (then `@ObservationIgnored @Published` for the bridged property).
- Never `@StateObject`/`@ObservedObject` with an `@Observable` class. View owns instance → `@State`; needs bindings → `@Bindable`; read-only → plain `let/var`.
- Never call `objectWillChange.send()`.
- Never `AnyView` — use `@ViewBuilder` functions.
- No sorting/filtering inside `ForEach` closures — cache as a computed property. ForEach identity from model properties, never array offsets.
- No regex compilation in view bodies — add patterns to `MarkdownCleaner`'s pre-compiled set.
- Long-lived UI state (progress banners, restore indicators) must be driven from a **stable** owner: the view body's `.task` or an observable service property. Never from a `.task` attached to a subview that disappears when the state it reports flips (this exact bug shipped once: a loading task torn down by its own `isLoading` change).

### Concurrency
- `AuthenticationManager` and UI-facing services are `@MainActor`. `RecordingService` is **deliberately not** — AVFoundation delegate callbacks are synchronous and off-main. Do not "fix" that by annotating it.
- **Never `MainActor.assumeIsolated`** — it is a runtime assertion that crashes (EXC_BREAKPOINT) when wrong, not a hop. Use `await MainActor.run { }`. The one use of `assumeIsolated` in this codebase crashed every recording start (TAB-50).
- Resolve any `@MainActor` state you need **before** starting a time-critical operation; do not suspend (await) between acquiring a resource and persisting the record of it. Concretely: the recovery manifest is written synchronously right after `record()` starts — an `await` in that gap re-opens an orphaned-recording race.
- Protocol-based services with mocks in `TabletNotesTests/Mocks/` — new services get a protocol.

### SwiftData
- Any change to a `@Model` (new entity, new property, type change) is a **migration event**. Additive + defaulted = lightweight-safe; anything else (type changes like the old `Transcript.id String→UUID`) can strand existing stores. Call out migration impact explicitly in the PR body every time you touch a model.
- `TabletNotesApp.init()` has a destructive store-reset **last resort** that sets `DataMigration.recordLocalStoreReset`; the post-reset cloud restore depends on that flag. Do not reorder, remove, or "simplify" the reset/restore/flag flow.
- `cloudKitDatabase: .none` must stay on **both** the primary and fallback `ModelConfiguration`.
- Do not add a `VersionedSchema` that references the live model classes — the live classes mutate, the checksum drifts, and the "safety" is false. A frozen `VersionedSchema` + `MigrationStage` gets added only when the first *custom* migration is actually needed.

### Networking
- All network requests via `NetworkRetry.withExponentialBackoff()`. Check `NetworkMonitor.shared.isConnected` before starting network-dependent flows — but never treat `isConnected == true` as proof an operation succeeded.
- Client must respect server `Retry-After`/429 backoff (scoped per-user and per-endpoint).
- No AI/third-party API keys in the client, ever. All AI + Bible traffic is proxied through `/api/*` Netlify functions with a Supabase Bearer token. Supabase anon key in `Resources/SupabaseConfig.swift` is the only client-held credential.

---

## 6. Backend conventions (`tablet-notes-api/`)

- Every function: auth via Supabase Bearer token, input validation (Joi via `utils/validator.js`), rate limiting via `utils/rateLimiter.js`, sanitization via `utils/security.js`. New endpoints get all four.
- **Sanitizers are type-aware.** `sanitizeText` is for free text; running it on structured values corrupts them (it once HTML-escaped `/` in Bible API paths). URLs/paths/enums get allowlist validation (`utils/bibleEndpoint.js` is the pattern), not text-escaping.
- **Fail closed.** Missing Redis → hard-capped in-memory limiter, not a no-op. Missing Apple root cert → 503, not trust-the-client. Missing tier metadata → `free`, never `pro`.
- **Never trust client-claimed entitlements or identity.** Subscription tier is derived server-side from the verified StoreKit JWS payload (`utils/applePurchase.js`); user identity from the verified JWT. A request body saying `"tier": "premium"` is an attack surface, not a fact.
- **Honest status codes with per-scope acknowledgment.** If any child insert fails, do not return 200/201 — the client clears its dirty flags on success and will *never retry*. Return the real error, and report `syncedScopes` so the client clears only what actually persisted. Corollary: **never delete existing rows before a replacement insert has succeeded** (delete-before-insert + swallowed error silently destroyed every cloud note for three months — TAB-56).
- Prod schema is the contract: column types in live Supabase (e.g. `notes.timestamp` is `INTEGER`) override whatever the Swift model uses. When adding a synced field, verify the prod column type first (§8), and coerce on **both** client and server — the server-side fix is the one that heals already-shipped builds.
- Rate limits must survive realistic bursts (a restore re-uploading a backlog; >10 recordings/hour). A limit that breaks the app's own sync is a bug, not protection.
- Sync engine ordering: pull must not be starved by push failures (a push throw once aborted the phase loop and permanently stalled restores at 119/180 sermons — TAB-55). Any change to `SermonSyncEngine.runSyncPhases` keeps push-failure isolation.

---

## 7. Deploys: merged ≠ live

- Netlify prod (`comfy-daffodil-7ecc55`) does **not** auto-deploy from GitHub. Every backend change is inert until someone runs `netlify deploy --prod` from `tablet-notes-api/`.
- Therefore: every PR touching `tablet-notes-api/` says so in the body, and after merge the deploy is tracked as an explicit follow-up ("deploy debt"). When asked "is X fixed?", the honest answer distinguishes *merged* from *deployed* from *verified in prod*.
- After deploying: smoke-check endpoints with unauthenticated curls (expect 400/401/405 — a 500 means the deploy is broken) and verify the specific fix against prod data.
- Env vars are per-site in Netlify (`netlify env:list --context production`). Some fixes are gated on env vars only the owner can provision (e.g. Upstash Redis, Apple root cert) — code that fails closed until then is correct behavior, not a bug.

## 8. Production data access

- **Read-only queries are allowed and encouraged** for diagnosis: get the service key via `supabase projects api-keys --project-ref ubghnmenxbhhlpxvypea`, then query PostgREST with it. Ground every "how many / which users / did it really fail" claim in a real query, not inference.
- **The service key can write to prod. Never write** (insert/update/delete, run backfills, reset statuses) without explicit owner go-ahead for that specific operation, even if a runbook exists. Runbooks execute in dry-run first, with before/after verification queries.
- Real prod facts beat assumptions: bugs here were repeatedly root-caused only after querying prod (37 notes vs 414 sermons; 180 distinct local_ids; 61 stuck sermons). When a sync bug is suspected, count the actual rows.

---

## 9. Named failure modes — the mistakes to not repeat

Each of these happened (or was caught in review) in this repo. The rule column is binding.

| # | Failure mode | The rule that prevents it |
|---|---|---|
| 1 | **The isolation assertion** — using `MainActor.assumeIsolated` to reach `@MainActor` state from a non-isolated context; crashes 100% at runtime, compiles fine | Never `assumeIsolated`. `await MainActor.run`, resolved *before* time-critical sections (§5) |
| 2 | **The optimistic ack** — returning success / clearing dirty-sync or reset flags when the operation partially failed; client never retries, data is gone silently | Success is reported only on *confirmed, complete* outcomes. Per-scope acks. Partial failure = failure (§6) |
| 3 | **The destructive delete-first** — deleting existing data before its replacement is safely written | Write-then-swap. Never delete cloud/local rows ahead of an insert that can fail (§6) |
| 4 | **The casual model edit** — touching a `@Model` without thinking "migration"; on users' devices this trips the destructive reset and looks like total data loss | Every `@Model` change is a migration event, called out in the PR (§5 SwiftData) |
| 5 | **The push that starves the pull** — sequential phase loops where one throw aborts everything after it | Phase isolation: a push failure must not prevent pull; restores pull-first (§6) |
| 6 | **The trusted client** — persisting tier/identity/paths the client claimed | Server derives from verified payloads only (§6) |
| 7 | **The wrong sanitizer** — text-escaping structured values (URLs, paths, IDs) | Allowlist-validate structure; `sanitizeText` only for free text (§6) |
| 8 | **The phantom deploy** — declaring a backend fix "done" at merge; prod still runs the old code | Merged ≠ deployed ≠ verified. Track deploy debt explicitly (§7) |
| 9 | **The schema guess** — coding against the Swift model's types instead of prod's actual column types | Check the live column type before syncing a field (§8) |
| 10 | **The self-inflicted rate limit** — limits/backoff tuned for attackers that break the app's own restore/backlog sync | Size limits against legitimate worst-case bursts; client honors 429/Retry-After (§6) |
| 11 | **The borrowed test failure** — burning time on (or worse, "fixing" in-scope) failures that pre-exist on main | Check `main` first; known failures listed in §3 |
| 12 | **The pbxproj edit** — hand-editing the project file to add files | Never; `fileSystemSynchronizedGroups` handles it (§3) |
| 13 | **The false-safety schema snapshot** — adding a VersionedSchema over live mutable classes | Only frozen schemas, only when a custom migration exists (§5 SwiftData) |
| 14 | **The scope creep** — bundling a second fix into the issue's PR | One issue, one branch, one PR; flag the rest (§4) |
| 15 | **The torn-down task** — driving progress UI from state that kills its own task | Stable `.task` / observable service property (§5) |
| 16 | **The legacy doc trusted** — reading root SQL/spec files as current truth | Live prod + current code are the only schema truth (§2) |
| 17 | **The connectivity proof** — treating `isConnected`, a 200 from one endpoint, or "no error thrown" as proof a multi-step operation fully succeeded | Verify the *outcome* (row counts, flags, files), not the precondition (§8) |

---

## 10. Quality bar per deliverable (checkable, not vibes)

**A claim of "done" for an iOS code change means:**
- [ ] `xcodebuild build` (exact command in §3) exits 0 — actually run, output in hand
- [ ] Test suites covering the touched services run and pass, excluding the §3 known failures (named explicitly if hit)
- [ ] Bug fixes include a regression test that fails without the fix (house norm: e.g. `pullRestoresAllSermonsWhenOneAudioDownloadFails`)
- [ ] Zero new: `AnyView`, `@StateObject`/`@ObservedObject` on `@Observable`, `objectWillChange.send()`, `assumeIsolated`, inline-`ForEach` sorts, view-body regex
- [ ] New service → protocol + mock; new network call → `NetworkRetry.withExponentialBackoff()`
- [ ] `@Model` touched → migration impact stated in PR body

**A claim of "done" for a backend change additionally means:**
- [ ] `npm test` green (all suites, currently ~51) and `node --check` on every changed function
- [ ] New/changed endpoint has: Bearer auth, Joi validation, rate limit, correct sanitization
- [ ] Failure paths return non-2xx; nothing clears client dirty state on partial success
- [ ] Shared logic lives in `utils/` with a `__tests__/` suite (functions themselves are untestable — extract to test)
- [ ] PR body states "requires `netlify deploy --prod`" and what to verify post-deploy

**A PR is ready for owner review when:**
- [ ] Exactly one Linear issue; title `[TAB-NN] …`; rebased on current `main`; no unrelated diffs
- [ ] Body: problem, root cause, fix, test evidence (commands + results), manual test steps, deploy/migration notes
- [ ] Description matches the *current* state of the diff (update it after every review round)

**An ops action (backfill, prod mutation, runbook) is ready when:**
- [ ] Dry-run mode exists and was run first, output shown
- [ ] Before/after verification queries written down
- [ ] Guarded by status+cutoff conditions (never blanket updates)
- [ ] Owner has approved *execution*, not just the script

**A root-cause diagnosis is credible when:**
- [ ] It's grounded in observed evidence (prod query, device log, reproduced failure) — not "likely because"
- [ ] It explains *all* the symptoms, including why the failure was silent
- [ ] Ruled-out hypotheses are listed with what ruled them out

---

## 11. When uncertain: escalation rules

**Proceed without asking** (reversible, on-branch, expected):
- Code/test changes on a feature branch; running builds and tests; read-only prod queries; read-only Netlify/Supabase inspection; creating the PR the task calls for; updating Linear issue status/comments for the issue you're working.

**Stop and ask the owner first** (each one, every time — prior approval doesn't carry over):
- Any prod **write**: DB mutations, backfill execution, storage deletion, `netlify deploy --prod`, env var changes
- Merging any PR, pushing to `main`, force-pushing, rebasing a branch someone else may have pulled
- Anything touching money or entitlements: StoreKit flow changes, tier logic, re-queuing paid AI jobs in bulk
- Deleting/overwriting local user data paths, or changing the destructive-reset / restore-flag flow
- Scope changes: the fix requires touching a second issue's territory, or the issue's stated approach turns out to be wrong

**Escalate immediately with findings (don't fix first)** when you discover:
- Evidence of ongoing data loss or corruption in prod
- A committed secret or an endpoint accepting unauthenticated writes
- That a merged-but-undeployed fix is more urgent than the current task

**Resolve yourself, in this order, before asking a question:**
1. This file → 2. the code as it is on `main` → 3. git history / PR discussions (`git log --grep TAB-NN`, `gh pr view`) → 4. the Linear issue → 5. a read-only prod query. Ask the owner only for genuine product decisions (what *should* happen) — never for facts the repo or prod can already tell you.

**Default posture when the user describes a problem:** diagnose and report; do not apply the fix until asked. When the user asks for a fix: implement fully, verify per §10, and end with a "what changed / what's verified / what's still gated (deploy, env, owner action)" summary that is honest about each category.

---

## 12. Environment quirks (learned the hard way)

- **Simulator console capture:** `print()` output does not reach `log show`. Use `xcrun simctl launch --console-pipe` — but it drops output after the first burst; terminate the app to flush block-buffered stdout. Xcode's console is the reliable option.
- **Migration testing:** Xcode ⌘R reinstalls into a *fresh* container and silently dodges the old store — to test upgrades against an existing store, install/launch with `simctl` on the same device.
- **Inspecting a sim's SwiftData store:** `sqlite3 ~/Library/Developer/CoreSimulator/Devices/<dev>/data/Containers/Data/Application/<app>/Documents/TabletNotes.store` (tables `ZSERMON`, etc.). Reset flags live in the app's UserDefaults plist in the same container.
- **Simulators have no signed-in account** — flows behind auth need the owner's account or a test account; say so instead of claiming untested flows work.
- Session memory (auto-loaded MEMORY.md) tracks *live* state — open PRs, pending deploys, prod counts. This file holds only durable rules; don't duplicate live state into it.
