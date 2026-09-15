# Ratchet Decision Ledger

<!--
Durable project memory: decisions future agents should not reopen accidentally.
Append-oriented. The agent maintains it. Record durable choices when their rationale would otherwise be lost.
SAFETY: no secrets, credentials, key ids, personal/customer data, or sensitive incident detail.
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

### D-20260831-2100-entitlements-server-only — Subscription entitlements are written only by the server

- **Status:** accepted
- **Impact:** high
- **Date:** 2026-08-31
- **Decision:** The client never writes `subscription_*` columns. `verify-purchase` derives tier/status/expiry from the Apple-verified transaction and writes with the service role; client-side grants were revoked by migration.
- **Why:** A client-writable entitlement was a premium-forging path (TAB-108). Proven live: anon/authenticated PATCH of subscription columns → 42501.
- **Rejected / alternatives:** Client writes with server-side validation — rejected; the column would still be client-authored (manual §6, "the trusted client").
- **Consequences:** Any new entitlement field goes through `verify-purchase`. Tests must cover the attack path, not just the happy path.
- **Revisit when:** Never silently. Only with a new server-side design.
- **Approved by:** owner

### D-20260831-2200-durable-pipeline-default-on — Durable processing pipeline is the shipped default

- **Status:** accepted
- **Impact:** medium
- **Date:** 2026-08-31
- **Decision:** `feature.durableProcessingPipeline` ships ON; a stored per-device Settings choice wins either way. `feature.resumableUploads` ships OFF until device proof of resume-vs-restart is read from field logs.
- **Why:** The durable path (server-side jobs + reaper) survived 92 jobs and app kills with zero stuck sermons in device testing (TAB-72); the legacy client path is the one that produced fake "basic summaries" (TAB-33).
- **Rejected / alternatives:** Flipping both flags together — rejected; resumable uploads had an unverified resume path.
- **Consequences:** Legacy client processing is retirement-bound (TAB-103 step 2), gated on soak; the TAB-97 status repairs must be extracted before the legacy services are deleted.
- **Revisit when:** TAB-103 step 2, or the first field-log evidence on resumable uploads.
- **Approved by:** owner

### D-20260903-1900-notes-never-delete-before-insert — Server reconciles notes on update; never delete-then-insert; partial failure is failure

- **Status:** accepted
- **Impact:** high
- **Date:** 2026-09-03
- **Decision:** `update-sermon` reconciles notes (upsert by id, delete only what the client no longer sends) and reports per-scope `syncedScopes`; the client clears dirty flags only for acknowledged scopes.
- **Why:** Delete-before-insert plus a swallowed error silently destroyed every cloud note for three months (TAB-56); a 2xx on partial failure meant the client never retried (TAB-110).
- **Rejected / alternatives:** Keeping delete-then-insert with a transaction — rejected; PostgREST calls from the function are not one transaction, and honest status codes were the missing half regardless.
- **Consequences:** Any new child collection follows the same reconcile + per-scope-ack shape.
- **Revisit when:** A move to server-side transactions (RPC) would allow simplification; the ack contract still stands.
- **Approved by:** owner

### D-20260913-2300-live-session-is-protected-at-the-service — The note service refuses to retire the live recording's session; visible editor text always wins at stop

- **Status:** accepted
- **Impact:** medium
- **Date:** 2026-09-13
- **Decision:** `NoteService.clearSession()` returns `false` and does nothing for the session that `RecordingService` reports as live (via the recovery manifest id); `RecordingNoteSession.finish` honours a refusal and never rotates on it; the recording screen's stop reconciles the primary note to the editor text; every save owner binds to the manifest session id captured at stop.
- **Why:** Four real sermons lost their note because the live session was cleared underneath the editor (TAB-113). Guarding at the callers had already failed once; the service is the one place every path goes through.
- **Rejected / alternatives:** Only guarding known callers — rejected; the actual caller was unknown for two weeks.
- **Consequences:** `clearSession()` is `@discardableResult` but any caller that rotates or re-keys a session must branch on the result.
- **Revisit when:** If the recording service ever becomes main-actor isolated, the provider seam can become a direct read.
- **Approved by:** owner (merge of PR #76)

### D-20260914-0000-services-built-once-at-app-root — Long-lived services are constructed once in `TabletNotesApp.init` and injected; the recovery scan never touches the live recording

- **Status:** accepted
- **Impact:** medium
- **Date:** 2026-09-14
- **Decision:** `SermonService` and `SyncService` are built in `TabletNotesApp.init` (once per process) and passed to `MainAppView`. `MainAppView.init` constructs nothing with side effects. `recoverInterruptedRecordingIfNeeded` returns when the manifest's session is the recording in progress.
- **Why:** SwiftUI re-runs a view's `init` on every parent re-render; `State(initialValue:)` discards the duplicate but its init-time side effects run. A foreground auth recheck built a throwaway `SermonService` whose per-instance recovery scan deleted the live manifest and cleared the live notes (TAB-114, caught on the phone log).
- **Rejected / alternatives:** A process-wide "recovery attempted" flag — rejected as the sole fix; it would have masked the construction bug and blocked recovery in tests that build several services.
- **Consequences:** New long-lived services follow the same pattern: construct at the app root, inject, never in a view init.
- **Revisit when:** If the app moves to an environment-injected service container, this becomes the natural place for it.
- **Approved by:** owner (merge of PR #77)

### D-20260914-0400-marketing-version-bump-per-release — Every release after a live version bumps `MARKETING_VERSION` in the project; build numbers stay Xcode-managed

- **Status:** accepted
- **Impact:** low
- **Date:** 2026-09-14
- **Decision:** The project file's `MARKETING_VERSION` is bumped (all six build-configuration occurrences) before archiving a release that follows a live version. `CURRENT_PROJECT_VERSION` stays `1`; Xcode's "manage version and build number" assigns the build number per version string at upload.
- **Why:** Apple closes a live version's train; the 1.0.1 upload was rejected twice until the bump (TAB-115). Managing the build number in the repo would add a second thing to bump for no gain.
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
- **Rejected / alternatives:** Leaving the manual at `TabletNotes/CLAUDE.md` and having `AGENTS.md` point at it — rejected; non-Claude agents would be sent to a file named for another tool, and the nested location made it easy to miss from the repo root. Blocking `gh pr merge` in the guard — rejected for now; the owner delegates merges per PR verbally and the manual's rule already governs it.
- **Consequences:** Claude Code's private auto-memory (`~/.claude/projects/…/MEMORY.md`) continues to hold the owner's private pointers; shareable state must also be reflected in `.ratchet/STATE.md`. Stop-time verification runs `npm test` when the API changed and the iOS build when Swift changed (fingerprint-cached, so once per set of edits).
- **Revisit when:** A second agent tool is adopted in earnest and needs its own thin adapter, or the hooks prove too slow in practice.
- **Approved by:** owner (requested the adoption 2026-09-14)
