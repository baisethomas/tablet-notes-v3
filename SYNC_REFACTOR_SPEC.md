# Sync Service Refactor Spec

## Goal

Refactor the sermon processing and sync pipeline so that:

- stopping a recording always produces one durable sermon record
- transcription and summary jobs update that same sermon record
- notes, transcript, and summary are never dropped during retries or sync
- opening `SermonDetailView` never creates duplicate work or destructive resyncs
- sync becomes predictable, idempotent, and safe under retries

## Current Problems

### Confirmed failure modes

- `TranscriptionRetryService` creates a new sermon on successful retry instead of updating the existing sermon.
- `SermonDetailView` queues transcription retry on `onAppear`, which can trigger duplicate processing for an existing sermon.
- `SummaryService` is a singleton with shared publishers and a single in-flight request, so summary requests for different sermons can interfere with each other.
- stop-recording processing exists in multiple UI entry points, so workflow logic is duplicated and can drift.
- `SyncService` uses whole-sermon parent sync with last-write-wins replacement of child data.
- backend note sync drops timestamps on create and update, and fetch does not return timestamps.
- retry queues are stored in `UserDefaults` with weak identity and no durable job state in the data model.

### User-facing symptoms explained by the current design

- notes appear to vanish after reopening a sermon because retries and sync are mutating different records
- summaries can disappear because summary state is attached to a shared singleton stream, not a request-scoped operation
- opening the detail view can trigger more processing before sync has settled
- cross-device sync can overwrite child entities because notes, transcript, and summary are merged as one parent blob

## Target Architecture

### 1. Single durable sermon pipeline

Introduce a single coordinator that owns the full post-recording lifecycle:

- `SermonProcessingCoordinator`

Responsibilities:

- create the sermon shell record as soon as recording stops
- snapshot notes exactly once at stop time
- enqueue transcription for that sermon
- enqueue summary only after transcription completes
- persist status transitions on the sermon and child entities
- expose idempotent commands for retry and resume

Views should stop orchestrating workflow logic directly. They should only send intents:

- `startRecording(serviceType:)`
- `stopRecording(sessionId:)`
- `retryTranscription(sermonId:)`
- `retrySummary(sermonId:)`

### 2. Request-scoped processing services

Refactor processing services so they are stateless per request:

- `TranscriptionService`
- `SummaryService`

Target interface shape:

```swift
protocol TranscriptionProcessor {
    func transcribe(sermonId: UUID, audioURL: URL) async throws -> TranscriptionResult
}

protocol SummaryProcessor {
    func summarize(sermonId: UUID, transcript: String, serviceType: String) async throws -> SummaryResult
}
```

Required changes:

- remove shared global completion publishers from `SummaryService`
- remove cross-sermon cancellation behavior
- return result values per request
- keep retry policy outside the raw network client

### 3. Durable job state

Add explicit local job state instead of inferring work from view appearance or `UserDefaults`.

Confirmed direction:

- use a persisted SwiftData job model in the first pass
- migrate legacy `UserDefaults` retry queues into the new store where possible
- retain background retry, but never trigger it from `SermonDetailView.onAppear`

Preferred model:

- `ProcessingJob` SwiftData model or equivalent persisted queue

Minimum fields:

- `id`
- `sermonId`
- `kind` (`transcription`, `summary`)
- `status` (`queued`, `running`, `failed`, `complete`)
- `attemptCount`
- `lastError`
- `createdAt`
- `updatedAt`
- `nextAttemptAt`

Rules:

- one active transcription job per sermon
- one active summary job per sermon
- retries update the same job row
- view open/close does not create jobs

### 4. Repository split for sync

Split sync responsibilities by entity type instead of syncing an entire sermon as a single mutable blob.

Proposed repositories:

- `SermonRepository`
- `NoteRepository`
- `TranscriptRepository`
- `SummaryRepository`
- `SyncRepository` or `SyncEngine`

Each entity should have:

- `remoteId`
- `updatedAt`
- dirty state or sync cursor

Sync rules:

- sync sermon metadata separately from notes/transcript/summary
- sync notes by stable `local_id`, not replace-all semantics
- upsert transcript by sermon
- upsert summary by sermon
- merge child data with entity-level timestamps
- never delete local child data solely because a partial remote response omitted that child

### 5. Single-flight sync engine

`SyncService` should become a serialized engine with one sync run at a time.

Requirements:

- ignore or coalesce overlapping sync triggers
- persist sync checkpoints
- separate push and pull into explicit phases
- only clear dirty flags after successful acknowledgement from backend
- treat remote omissions as partial payloads unless explicitly marked deleted

### 6. Backend contract fixes

Required API changes before or during app refactor:

- preserve note `timestamp` on create
- preserve note `timestamp` on update
- include note `timestamp` in `get-sermons`
- support idempotent upsert by `(user_id, local_id)` where applicable
- return complete child payloads consistently
- avoid delete-all-and-reinsert for notes unless a full replacement contract is explicit

## Proposed Module Boundaries

### App-side

- `Services/Recording/RecordingService`
  - device audio capture only
- `Services/Processing/SermonProcessingCoordinator`
  - workflow orchestration
- `Services/Processing/TranscriptionProcessor`
  - AssemblyAI file transcription
- `Services/Processing/SummaryProcessor`
  - summarize transcript
- `Services/Processing/ProcessingJobStore`
  - persisted queue and retries
- `Services/Sync/SyncEngine`
  - push/pull orchestration
- `Services/Sync/*Repository`
  - entity-specific serialization and merging

### View responsibilities after refactor

- start and stop recording
- show current sermon/job state
- trigger explicit retries through coordinator
- never create or mutate background workflow state directly

## Data Model Changes

### Sermon

Keep:

- `id`
- `remoteId`
- `updatedAt`
- `transcriptionStatus`
- `summaryStatus`
- `needsSync`

Add:

- `processingState` if useful as a single high-level display state
- `lastProcessingError`

### Note

Keep and use consistently:

- `id`
- `remoteId`
- `timestamp`
- `updatedAt`
- `needsSync`

### Transcript

Keep and use consistently:

- `id`
- `remoteId`
- `updatedAt`
- `needsSync`

### Summary

Keep and use consistently:

- `id`
- `remoteId`
- `updatedAt`
- `needsSync`

### New

- `ProcessingJob`

## Implementation Plan

### Phase 0: Safety net

- add integration tests for recording stop -> transcription -> summary -> sync
- add regression tests for reopening a pending sermon
- add tests for note timestamp round-trip through backend
- add tests for concurrent summary requests for different sermons

### Phase 1: Backend contract repair

- fix `create-sermon.js` to store note timestamps
- fix `update-sermon.js` to store note timestamps
- fix `get-sermons.js` to return note timestamps
- add or verify upsert semantics for child records

### Phase 2: Stop duplicate sermon creation

- change `PendingTranscription` to store `sermonId`
- update `TranscriptionRetryService` to apply results to the existing sermon
- remove any code path that creates a new sermon during retry
- make `SermonDetailView` call explicit retry commands only
- keep background retry at app/network level, not view-appearance level

### Phase 3: Centralize workflow orchestration

- introduce `SermonProcessingCoordinator`
- move stop-recording workflow out of `RecordingView` and `MainAppView`
- persist sermon shell before async work begins
- snapshot notes once at stop time
- in the first pass, route all new post-recording transcription through the coordinator instead of direct UI-owned processing

### Phase 4: Replace singleton summary flow

- convert `SummaryService` to request-scoped async API
- remove shared publisher coordination logic from `SermonService`
- remove summary retry logic that depends on global status streams

### Phase 5: Refactor sync engine

- introduce single-flight sync execution
- split entity serialization and merge logic into repositories
- move from sermon-level overwrite behavior to child-level upsert/merge
- only update local state from remote when merge rules say it is safe

### Phase 6: Cleanup

- remove obsolete retry queues in `UserDefaults`
- remove duplicated workflow code in views
- tighten logging around sermon lifecycle and sync phases
- document recovery and conflict rules

## Testing Plan

### Integration tests

- record with notes, then stop, then verify sermon shell exists before transcription completes
- transcription success updates the existing sermon and preserves notes
- summary success updates the existing sermon and preserves transcript and notes
- reopening `SermonDetailView` during pending transcription does not create duplicate sermons
- reopening `SermonDetailView` during pending summary does not restart or cancel unrelated work
- sync push then pull preserves notes, transcript, summary, and status
- same sermon across two devices does not lose child data after repeated syncs

### Backend tests

- note timestamp create/update/get round-trip
- idempotent create/update with repeated requests
- partial payload does not erase child entities unintentionally

## Risks

- SwiftData relationship mutation is already brittle in this area, so migrations must be incremental
- moving retry state from `UserDefaults` to SwiftData needs careful migration for existing users
- sync merge behavior will surface hidden data inconsistencies already present in remote data

## Out of Scope For Initial Refactor

- redesigning live transcription UX
- changing AssemblyAI provider strategy
- large visual changes in sermon detail or recording screens

## Immediate First Slice

The first implementation slice should be:

1. introduce `ProcessingJob` and `SermonProcessingCoordinator`
2. route new recording completion through the coordinator
3. replace legacy transcription retry duplication with sermon-ID-based job processing
4. move summary generation onto durable job queueing from the service layer
5. remove automatic retry-on-appear from `SermonDetailView`
6. fix backend note timestamp create/update/get
7. add regression tests for duplicate-sermon creation and note preservation

This slice should reduce the current data-loss behavior before the larger sync redesign lands.
