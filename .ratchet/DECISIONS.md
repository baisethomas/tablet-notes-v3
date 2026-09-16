# Ratchet Decision Ledger

<!--
Durable project memory: decisions future agents should not reopen accidentally.
Append-oriented. The agent maintains it. Record durable choices when their rationale would otherwise be lost.
SAFETY: no secrets, credentials, key ids, personal/customer data, incident narratives, or vulnerability mechanics.
Record the constraint and the sanitized "why"; point to the Linear issue or PR for history.
GIT INTEGRATION: parallel branches may add decisions independently; preserve compatible entries at merge, escalate true conflicts.
IDs: `D-YYYYMMDD-HHMM-short-slug` (UTC). Identity is not authority.
Autonomy: low-impact choices stay in code; medium-impact may be recorded by the agent and surfaced; high-impact require explicit human approval before acceptance or execution.
Rules that are already binding text in `docs/OPERATING-MANUAL.md` are not repeated here; this ledger holds the *why* behind choices the manual states as rules, plus choices made after the manual was written.
-->

## Decision format

### D-YYYYMMDD-HHMM-short-slug — short decision title

- **Status:** accepted | proposed | superseded
- **Impact:** low | medium | high
- **Date:** YYYY-MM-DD
- **Decision:**
- **Why:**
- **Rejected / alternatives:**
- **Consequences:**
- **Revisit when:**
- **Approved by:** agent | human name/role

---

## Decisions

### D-20260915-website-first-import — Import the website independently before wider monorepo restructuring

- **Status:** accepted
- **Impact:** medium
- **Date:** 2026-09-15
- **Decision:** TAB-118 imports the website at `apps/website` with a non-squashed subtree, preserving source commit hashes and its local pnpm lockfile. Existing native, backend, infrastructure and support paths remain unchanged for this stage. Integration requires a merge commit.
- **Why:** The live website's Vercel cutover can be verified independently without simultaneously reconfiguring the production API or native build paths.
- **Rejected / alternatives:** Moving every project and consolidating package managers in this issue adds unrelated deployment and dependency risk. Rewriting or squashing source history fails the history-preservation objective.
- **Consequences:** Website documentation lives alongside its source; the wider folder layout and shared packages are follow-up work. Production configuration and merge remain owner-gated under the migration plan.
- **Revisit when:** The website cutover is stable and a separate issue scopes wider repository organization.
- **Approved by:** agent (within the owner's migration planning and delegated preparation request)

### D-20260831-2100-entitlements-server-only — Subscription entitlements are written only by the server

- **Status:** accepted
- **Impact:** high
- **Date:** 2026-08-31
- **Decision:** The client never writes `subscription_*` columns. `verify-purchase` derives tier/status/expiry from the Apple-verified transaction and writes with the service role. Client-side write grants on those columns were removed by migration.
- **Why:** Entitlements are a security boundary and must be server-authored (manual §6, "the trusted client"). Background: TAB-108.
- **Rejected / alternatives:** Client writes with server-side validation — rejected; the column would still be client-authored.
- **Consequences:** Any new entitlement field goes through `verify-purchase`. Access-gating helpers get adversarial tests, not just happy-path ones.
- **Revisit when:** Never silently. Only with a new server-side design.
- **Approved by:** owner

### D-20260831-2200-durable-pipeline-default-on — Durable processing pipeline is the shipped default

- **Status:** accepted
- **Impact:** medium
- **Date:** 2026-08-31
- **Decision:** `feature.durableProcessingPipeline` ships ON; a stored per-device Settings choice wins either way. `feature.resumableUploads` ships OFF until field-log evidence of the resume path is read.
- **Why:** The durable path (server-side jobs + reaper) met its exit criteria in device testing (TAB-72); the legacy client path is the one that produced low-quality fallback summaries (TAB-33).
- **Rejected / alternatives:** Flipping both flags together — rejected; the resume path was unverified.
- **Consequences:** Legacy client processing is retirement-bound (TAB-103 step 2), gated on soak; the TAB-97 status repairs must be extracted before the legacy services are deleted.
- **Revisit when:** TAB-103 step 2, or the first field-log evidence on resumable uploads.
- **Approved by:** owner

### D-20260903-1900-notes-reconcile-with-per-scope-acks — Server reconciles child records on update; partial failure is failure

- **Status:** accepted
- **Impact:** high
- **Date:** 2026-09-03
- **Decision:** `update-sermon` reconciles notes (upsert by id; delete only what the client no longer sends) and reports per-scope `syncedScopes`; the client clears dirty flags only for acknowledged scopes. Never delete existing rows ahead of a replacement insert; never return 2xx on partial failure.
- **Why:** Manual §6 ("honest status codes", "the destructive delete-first"). Background: TAB-56, TAB-110.
- **Rejected / alternatives:** Keeping delete-then-insert inside a transaction — rejected; the function's PostgREST calls are not one transaction, and honest status codes were the missing half regardless.
- **Consequences:** Any new child collection follows the same reconcile + per-scope-ack shape.
- **Revisit when:** A move to server-side transactions (RPC) would allow simplification; the ack contract still stands.
- **Approved by:** owner

### D-20260913-2300-live-session-is-protected-at-the-service — The note service refuses to retire the live recording's session; visible editor text always wins at stop

- **Status:** accepted
- **Impact:** medium
- **Date:** 2026-09-13
- **Decision:** `NoteService.clearSession()` returns `false` and does nothing for the session that `RecordingService` reports as live (via the recovery manifest id); `RecordingNoteSession.finish` honours a refusal and never rotates on it; the recording screen's stop reconciles the primary note to the editor text; every save owner binds to the manifest session id captured at stop.
- **Why:** The service is the one place every path goes through; guarding individual callers had already proven insufficient. Background: TAB-113 / PR #76.
- **Rejected / alternatives:** Only guarding known callers — rejected.
- **Consequences:** `clearSession()` is `@discardableResult` but any caller that rotates or re-keys a session must branch on the result.
- **Revisit when:** If the recording service ever becomes main-actor isolated, the provider seam can become a direct read.
- **Approved by:** owner (merge of PR #76)

### D-20260914-0000-services-built-once-at-app-root — Long-lived services are constructed once in `TabletNotesApp.init` and injected; the recovery scan never touches the live recording

- **Status:** accepted
- **Impact:** medium
- **Date:** 2026-09-14
- **Decision:** `SermonService` and `SyncService` are built in `TabletNotesApp.init` (once per process) and passed to `MainAppView`. `MainAppView.init` constructs nothing with side effects. `recoverInterruptedRecordingIfNeeded` returns when the manifest's session is the recording in progress.
- **Why:** SwiftUI re-runs a view's `init` on every parent re-render; `State(initialValue:)` discards the duplicate but its init-time side effects still run. Background: TAB-114 / PR #77.
- **Rejected / alternatives:** A process-wide "recovery attempted" flag as the sole fix — rejected; it would mask the construction bug and block recovery in tests that build several services.
- **Consequences:** New long-lived services follow the same pattern: construct at the app root, inject, never in a view init.
- **Revisit when:** If the app moves to an environment-injected service container, this becomes the natural place for it.
- **Approved by:** owner (merge of PR #77)

### D-20260914-0400-marketing-version-bump-per-release — Every release after a live version bumps `MARKETING_VERSION` in the project; build numbers stay Xcode-managed

- **Status:** accepted
- **Impact:** low
- **Date:** 2026-09-14
- **Decision:** `MARKETING_VERSION` is bumped (all six build-configuration occurrences) before archiving a release that follows a live version. `CURRENT_PROJECT_VERSION` stays `1`; Xcode's "manage version and build number" assigns the build number per version string at upload.
- **Why:** Apple closes a live version's train to new builds. Managing the build number in the repo would add a second thing to bump for no gain. Background: TAB-115.
- **Rejected / alternatives:** Setting the build number in the repo too — rejected; duplicate-number rejections at upload are the failure mode that invites.
- **Consequences:** Release checklist step one is the version bump PR. The next version after 1.0.1 must be 1.0.2 or higher.
- **Revisit when:** If a CI upload pipeline is adopted, it should own both numbers.
- **Approved by:** owner (merge of PR #78)

### D-20260915-0100-adopt-ratchet — Adopt the Ratchet harness; the operating manual moves to a model-agnostic path

- **Status:** accepted
- **Impact:** medium
- **Date:** 2026-09-15
- **Decision:** `AGENTS.md` is the canonical operating contract. The TabletNotes operating manual moves from `TabletNotes/CLAUDE.md` to `docs/OPERATING-MANUAL.md` with its content unchanged. Root `CLAUDE.md` is a thin Claude Code adapter that imports both. `.ratchet/STATE.md` and `.ratchet/DECISIONS.md` are the shared project memory. Hooks in `.claude/hooks/` enforce the destructive-command hard stops and run verification at stop time.
- **Why:** The owner wants any model to work in this repo through the same contract, memory, and verification (see https://github.com/baisethomas/Ratchet). The manual was already model-agnostic knowledge living under a tool-specific filename; per Ratchet, tool files must be thin adapters.
- **Rejected / alternatives:** Leaving the manual at `TabletNotes/CLAUDE.md` and having `AGENTS.md` point at it — rejected; non-Claude agents would be sent to a file named for another tool. Blocking `gh pr merge` in the guard — rejected for now; the owner delegates merges per PR verbally and the manual's rule already governs it.
- **Consequences:** Claude Code's private auto-memory continues to hold the owner's private pointers; shareable state must also be reflected in `.ratchet/STATE.md`. Stop-time verification runs `npm test` when the API changed and the iOS build when Swift changed (fingerprint-cached, so once per set of edits). Ratchet memory records constraints and ticket references, never incident narratives; the manual's §9 "named failure modes" remain the sanctioned home for lessons learned.
- **Revisit when:** A second agent tool is adopted in earnest and needs its own thin adapter, or the hooks prove too slow in practice.
- **Approved by:** owner (requested the adoption 2026-09-14)

### D-20260915-0625-add-codex-adapter — Add a discoverable Codex adapter with risk-based model routing

- **Status:** accepted
- **Impact:** medium
- **Date:** 2026-09-15
- **Decision:** `CODEX.md` is the thin Codex-specific adapter and `AGENTS.md` points Codex agents to it. The owner-facing model remains host-selected; when delegation is separately authorized, high-risk work routes to `gpt-6-astra`, routine implementation to `gpt-5.6-terra`, and chores to `gpt-5.6-luna`, subject to model availability.
- **Why:** Codex automatically loads `AGENTS.md` but has no automatic `CODEX.md` convention. A canonical pointer makes the adapter operational while keeping shared policy model-independent. Codex also does not automatically inherit Claude Code's hook enforcement or control the root session's model, so the adapter must state those boundaries explicitly.
- **Rejected / alternatives:** Copying all operating rules into `CODEX.md` — rejected as duplicate memory. Treating the Claude hook configuration as active in Codex — rejected because enforcement is harness-specific. Naming `gpt-6-astra` as an agent-selectable root model — rejected because the host or owner selects it.
- **Consequences:** Fresh Codex agents read `CODEX.md` through the canonical read order, apply hard stops even without an intercepting hook, and run verification explicitly. The routing table guides only delegation already authorized by the user or another applicable instruction.
- **Revisit when:** Codex gains a native adapter convention, automatic support for the committed hooks, different available model ids, or root-session model switching.
- **Approved by:** owner (requested the Codex equivalent on 2026-09-15 UTC)
