# Comprehensive iOS Sync Architecture Analysis - Tablet Notes

## Executive Summary

The app is experiencing a **CRITICAL BUG** where audio syncs across devices but notes, transcripts, and summaries do not. The bug is in the `updateLocalSermon()` method in SyncService.swift which fails to update related data (notes, transcript, summary) when pulling remote sermon changes to an existing local sermon.

---

## 1. SYNC ARCHITECTURE OVERVIEW

### 1.1 High-Level Sync Flow

```
LOCAL DEVICE (iPhone/iPad 1)
    ↓ Record sermon with notes/transcript/summary
    ↓ Mark for sync (needsSync = true)
    ↓ On sync trigger (periodic every 60s or manual)
    ↓
    ├─→ PUSH LOCAL CHANGES
    │   ├─→ Upload audio to Supabase Storage
    │   ├─→ POST create-sermon API (includes notes/transcript/summary)
    │   └─→ Mark sermon as synced
    │
    └─→ PULL CLOUD CHANGES
        ├─→ GET get-sermons API (includes all related data)
        └─→ Update/create local sermons with cloud data

CLOUD (Supabase + Netlify Functions)
    ↓ create-sermon.js: Creates sermon + notes + transcript + summary
    ↓ update-sermon.js: Updates sermon + notes + transcript + summary
    ↓ get-sermons.js: Returns sermon with all related data

REMOTE DEVICE (iPad)
    ↓ Periodic sync triggers
    ↓ GET get-sermons API returns complete sermon data
    ↓ BUG: updateLocalSermon() DOESN'T UPDATE NOTES/TRANSCRIPT/SUMMARY
    ↓ User sees empty notes/transcript/summary on iPad
```

---

## 2. DETAILED DATA MODELS

### 2.1 Local Data Models (SwiftData)

#### Sermon Model
```swift
@Model final class Sermon {
    @Attribute(.unique) var id: UUID
    var title: String
    var audioFileName: String
    var date: Date
    var serviceType: String
    var speaker: String?
    
    @Relationship(deleteRule: .cascade) var transcript: Transcript?
    @Relationship(deleteRule: .cascade) var notes: [Note]
    @Relationship(deleteRule: .cascade) var summary: Summary?
    
    // Sync metadata
    var syncStatus: String // "localOnly", "syncing", "synced", "error"
    var transcriptionStatus: String // "processing", "complete", "failed"
    var summaryStatus: String
    var isArchived: Bool
    
    var lastSyncedAt: Date?
    var remoteId: String? // Maps to Supabase sermon.id
    var updatedAt: Date?
    var needsSync: Bool // Triggers inclusion in next sync
    var userId: UUID? // Foreign key to User
}
```

#### Note Model
```swift
@Model final class Note: Codable {
    @Attribute(.unique) var id: UUID
    var text: String
    var timestamp: TimeInterval // seconds into audio
    @Relationship(inverse: \Sermon.notes) var sermon: Sermon?
    
    var remoteId: String? // Maps to Supabase notes.id
    var updatedAt: Date?
    var needsSync: Bool
}
```

#### Transcript Model
```swift
@Model final class Transcript {
    var text: String
    @Relationship(deleteRule: .cascade) var segments: [TranscriptSegment]
    
    var remoteId: String?
    var updatedAt: Date?
    var needsSync: Bool
}
```

#### Summary Model
```swift
@Model final class Summary {
    @Attribute(.unique) var id: UUID
    var title: String
    var text: String
    var type: String // "devotional", "bullet", "theological"
    var status: String // "pending", "complete", "failed"
    
    var remoteId: String?
    var updatedAt: Date?
    var needsSync: Bool
}
```

### 2.2 Remote Data Models (Codable)

```swift
struct RemoteSermonData: Codable {
    let id: String // Remote ID (Supabase UUID)
    let localId: UUID
    let title: String
    let audioFileURL: URL
    let audioFilePath: String? // Storage path
    let date: Date
    let serviceType: String
    let speaker: String?
    let transcriptionStatus: String
    let summaryStatus: String
    let isArchived: Bool
    let userId: UUID
    let updatedAt: Date
    let notes: [RemoteNoteData]?           // ← CRITICAL: Contains pulled notes
    let transcript: RemoteTranscriptData?  // ← CRITICAL: Contains pulled transcript
    let summary: RemoteSummaryData?        // ← CRITICAL: Contains pulled summary
}

struct RemoteNoteData: Codable {
    let id: String
    let localId: UUID
    let text: String
    let timestamp: TimeInterval
}

struct RemoteTranscriptData: Codable {
    let id: String
    let localId: UUID
    let text: String
    let segments: String?
    let status: String
}

struct RemoteSummaryData: Codable {
    let id: String
    let localId: UUID
    let title: String
    let text: String
    let type: String
    let status: String
}
```

---

## 3. SYNC SERVICE IMPLEMENTATION

### 3.1 Main Sync Methods

#### A. Push Local Changes (Sync Up)

**File**: SyncService.swift, line 85-102

```swift
private func pushLocalChanges() async throws {
    // 1. Fetch all sermons with needsSync=true
    let descriptor = FetchDescriptor<Sermon>(
        predicate: #Predicate<Sermon> { sermon in
            sermon.needsSync == true
        }
    )
    
    // 2. For each sermon:
    for sermon in sermonsToSync {
        try await syncSermonToCloud(sermon)
    }
}

private func syncSermonToCloud(_ sermon: Sermon) async throws {
    // Create SermonSyncData from sermon
    let sermonData = SermonSyncData(
        id: sermon.id,
        title: sermon.title,
        audioFileURL: sermon.audioFileURL,
        date: sermon.date,
        serviceType: sermon.serviceType,
        speaker: sermon.speaker,
        transcriptionStatus: sermon.transcriptionStatus,
        summaryStatus: sermon.summaryStatus,
        isArchived: sermon.isArchived,
        userId: sermon.userId,
        updatedAt: sermon.updatedAt ?? Date()
    )
    
    // If sermon has remoteId, update; otherwise create
    if let remoteId = sermon.remoteId {
        try await updateRemoteSermon(sermon: sermon, remoteId: remoteId, data: sermonData)
    } else {
        let newRemoteId = try await createRemoteSermon(sermon: sermon, data: sermonData)
        sermon.remoteId = newRemoteId
    }
    
    sermon.lastSyncedAt = Date()
    sermon.needsSync = false
    sermon.syncStatus = "synced"
    try modelContext.save()
}
```

**Key Points**:
- Only syncs sermons with `needsSync=true`
- Audio file is uploaded to Supabase Storage via signed URL
- Full sermon object (including notes/transcript/summary) is passed to create/update functions
- Includes related data in API payloads ✓ (FIXED in commit a219d1e)

#### B. Pull Cloud Changes (Sync Down)

**File**: SyncService.swift, line 104-115

```swift
private func pullCloudChanges() async throws {
    guard let currentUser = await authService.currentUser else { return }
    
    // 1. Fetch all remote sermons for user
    let remoteSermons = try await fetchRemoteSermons(for: currentUser.id)
    
    // 2. For each remote sermon:
    for remoteSermon in remoteSermons {
        try await syncSermonFromCloud(remoteSermon)
    }
}

private func syncSermonFromCloud(_ remoteSermon: RemoteSermonData) async throws {
    // 1. Find existing local sermon by remoteId
    let descriptor = FetchDescriptor<Sermon>(
        predicate: #Predicate<Sermon> { sermon in
            sermon.remoteId == remoteId
        }
    )
    let existingSermons = try modelContext.fetch(descriptor)
    
    if let existingSermon = existingSermons.first {
        // 2. Download audio if missing
        if !existingSermon.audioFileExists {
            let localAudioURL = try await downloadAudioFile(...)
            existingSermon.audioFileName = localAudioURL.lastPathComponent
        }
        
        // 3. UPDATE LOCAL SERMON
        if remoteSermon.updatedAt > (existingSermon.updatedAt ?? Date.distantPast) {
            updateLocalSermon(existingSermon, with: remoteSermon)
        }
        
        try modelContext.save()
    } else {
        // 4. CREATE NEW LOCAL SERMON
        try await createLocalSermon(from: remoteSermon)
    }
}
```

---

## 4. THE CRITICAL BUG

### Location
**File**: `SyncService.swift`, lines 241-251

### The Buggy Method
```swift
private func updateLocalSermon(_ sermon: Sermon, with remoteData: RemoteSermonData) {
    sermon.title = remoteData.title
    sermon.serviceType = remoteData.serviceType
    sermon.speaker = remoteData.speaker
    sermon.isArchived = remoteData.isArchived
    sermon.transcriptionStatus = remoteData.transcriptionStatus
    sermon.summaryStatus = remoteData.summaryStatus
    sermon.updatedAt = remoteData.updatedAt
    sermon.lastSyncedAt = Date()
    sermon.syncStatus = "synced"
    // ❌ MISSING: Notes, transcript, summary updates!
}
```

### What It Should Do

The method receives `remoteData` which contains:
- `remoteData.notes: [RemoteNoteData]?` 
- `remoteData.transcript: RemoteTranscriptData?`
- `remoteData.summary: RemoteSummaryData?`

But it **IGNORES** this data!

### Compare with createLocalSermon (Lines 283-317) - THIS WORKS!

```swift
private func createLocalSermon(from remoteData: RemoteSermonData) async throws {
    // ... create sermon ...
    
    // ✓ CORRECTLY HANDLES NOTES
    if let remoteNotes = remoteData.notes {
        for noteData in remoteNotes {
            let note = Note(
                id: noteData.localId,
                text: noteData.text,
                timestamp: noteData.timestamp,
                remoteId: noteData.id
            )
            sermon.notes.append(note)
        }
    }
    
    // ✓ CORRECTLY HANDLES TRANSCRIPT
    if let transcriptData = remoteData.transcript {
        let transcript = Transcript(
            text: transcriptData.text,
            segments: [],
            remoteId: transcriptData.id
        )
        sermon.transcript = transcript
    }
    
    // ✓ CORRECTLY HANDLES SUMMARY
    if let summaryData = remoteData.summary {
        let summary = Summary(
            id: summaryData.localId,
            title: summaryData.title,
            text: summaryData.text,
            type: summaryData.type,
            status: summaryData.status,
            remoteId: summaryData.id
        )
        sermon.summary = summary
    }
}
```

### Impact Timeline

1. **iPhone records sermon** (no transcript/summary yet)
   - Sermon: title, audio, notes
   - Status: transcriptionStatus="processing", summaryStatus="processing"
   - Sync: uploads to cloud ✓

2. **Transcript generation completes** 
   - Sermon marked `needsSync=true`
   - Next sync (within 60s): sends transcript to cloud ✓
   - Backend stores transcript in `transcripts` table ✓

3. **iPad pulls changes**
   - GET get-sermons returns complete sermon WITH transcript ✓
   - `syncSermonFromCloud()` called
   - **BUG**: `updateLocalSermon()` ignores the transcript data ❌
   - iPad shows "Transcription Pending" instead of the actual transcript ❌

4. **Summary generation completes**
   - Same flow: sent to cloud ✓ but not synced to iPad ❌

---

## 5. SYNC PAYLOAD ANALYSIS

### 5.1 Push Payload (Create Sermon)

**POST** `/api/create-sermon`

```json
{
  "localId": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Sunday Service",
  "audioFilePath": "user-id/filename.m4a",
  "audioFileUrl": "https://...",
  "audioFileName": "recording.m4a",
  "audioFileSizeBytes": 5242880,
  "date": "2025-11-06T10:00:00Z",
  "serviceType": "Sunday Service",
  "speaker": "Pastor John",
  "transcriptionStatus": "processing",
  "summaryStatus": "processing",
  "isArchived": false,
  "notes": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "text": "Key point about scripture",
      "timestamp": 120.5
    }
  ],
  "transcript": {
    "id": "550e8400-e29b-41d4-a716-446655440002",
    "text": "Full transcribed text...",
    "segments": null,
    "status": "complete"
  },
  "summary": {
    "id": "550e8400-e29b-41d4-a716-446655440003",
    "title": "Summary Title",
    "text": "Summary text...",
    "type": "devotional",
    "status": "complete"
  }
}
```

**Backend Processing** (create-sermon.js):
```javascript
// 1. Insert sermon
const { data: sermon } = await supabase.from('sermons').insert(sermonData).select();

// 2. Insert notes if provided
if (body.notes && Array.isArray(body.notes)) {
    const notesData = body.notes.map(note => ({
        local_id: note.id,
        sermon_id: sermon.id,
        text: note.text,
        timestamp: note.timestamp
    }));
    await supabase.from('notes').insert(notesData);
}

// 3. Insert transcript if provided
if (body.transcript) {
    const transcriptData = {
        sermon_id: sermon.id,
        text: body.transcript.text,
        segments: body.transcript.segments,
        status: body.transcript.status
    };
    await supabase.from('transcripts').insert(transcriptData);
}

// 4. Insert summary if provided
if (body.summary) {
    const summaryData = {
        sermon_id: sermon.id,
        title: body.summary.title,
        text: body.summary.text,
        type: body.summary.type,
        status: body.summary.status
    };
    await supabase.from('summaries').insert(summaryData);
}
```

**Status**: ✓ Works correctly - all related data persisted

### 5.2 Push Payload (Update Sermon)

**POST** `/api/update-sermon` (note: uses POST not PUT)

Same structure as create, with `remoteId` identifying the sermon to update.

**Backend Processing** (update-sermon.js):
```javascript
// 1. Update sermon metadata
const updateData = {
    title: body.title,
    service_type: body.serviceType,
    transcription_status: body.transcriptionStatus,
    summary_status: body.summaryStatus,
    is_archived: body.isArchived
};
await supabase.from('sermons').update(updateData).eq('id', body.remoteId);

// 2. Update notes (delete old, insert new)
await supabase.from('notes').delete().eq('sermon_id', body.remoteId);
if (body.notes && body.notes.length > 0) {
    const notesData = body.notes.map(note => ({...}));
    await supabase.from('notes').insert(notesData);
}

// 3. Upsert transcript (update if exists, insert if new)
if (body.transcript) {
    await supabase.from('transcripts').upsert(transcriptData, {
        onConflict: 'sermon_id'
    });
}

// 4. Upsert summary
if (body.summary) {
    await supabase.from('summaries').upsert(summaryData, {
        onConflict: 'sermon_id'
    });
}
```

**Status**: ✓ Works correctly - all related data persisted

### 5.3 Pull Payload (Get Sermons)

**GET** `/api/get-sermons?userId={userId}`

**Backend Query** (get-sermons.js):
```javascript
const { data } = await supabase
    .from('sermons')
    .select(`
        id,
        local_id,
        title,
        audio_file_url,
        audio_file_path,
        date,
        service_type,
        speaker,
        transcription_status,
        summary_status,
        is_archived,
        updated_at,
        notes (id, local_id, text, timestamp),           // ← Join notes
        transcripts (id, local_id, text, segments, status),  // ← Join transcript
        summaries (id, local_id, title, text, type, status)  // ← Join summary
    `)
    .eq('user_id', userId)
    .order('date', { ascending: false });
```

**Response** (mapped to RemoteSermonData):
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "localId": "550e8400-e29b-41d4-a716-446655440000",
    "title": "Sunday Service",
    "audioFileURL": "https://...",
    "audioFilePath": "user-id/filename.m4a",
    "date": "2025-11-06T10:00:00Z",
    "serviceType": "Sunday Service",
    "speaker": "Pastor John",
    "transcriptionStatus": "processing",
    "summaryStatus": "processing",
    "isArchived": false,
    "userId": "user-id",
    "updatedAt": "2025-11-06T12:30:00Z",
    "notes": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440001",
        "localId": "550e8400-e29b-41d4-a716-446655440001",
        "text": "Key point",
        "timestamp": 120.5
      }
    ],
    "transcript": {
      "id": "550e8400-e29b-41d4-a716-446655440002",
      "localId": "550e8400-e29b-41d4-a716-446655440002",
      "text": "Full transcribed text...",
      "segments": null,
      "status": "complete"
    },
    "summary": {
      "id": "550e8400-e29b-41d4-a716-446655440003",
      "localId": "550e8400-e29b-41d4-a716-446655440003",
      "title": "Summary Title",
      "text": "Summary text...",
      "type": "devotional",
      "status": "complete"
    }
  }
]
```

**Status**: ✓ Backend returns complete data, but iOS client ignores it ❌

---

## 6. DATA FLOW SEQUENCE DIAGRAM

```
iPhone (Device A)                 Supabase/Netlify                    iPad (Device B)
    |                                   |                                  |
    |-- Record sermon + notes -----------|                                  |
    |                                    |                                  |
    |-- Trigger sync every 60s ----------|                                  |
    |                                    |                                  |
    |-- POST create-sermon ──────────→  [1] Insert sermon                  |
    |  (with notes, but no transcript)   [2] Insert notes                  |
    |                                    |                                  |
    |                                    |  Every 60s periodic sync triggers|
    |                                    |                                  |
    |-- Transcript completes -------→   |                                  |
    |-- Mark sermon needsSync=true       |                                  |
    |                                    |                                  |
    |-- Next sync (within 60s) ────────→ [3] POST update-sermon            |
    |  POST update-sermon                [4] Upsert transcript             |
    |  (now includes transcript!)        |                                  |
    |                                    |                                  |
    |                                    |←─ [5] GET get-sermons ──────────|
    |                                    |    Returns sermon + notes        |
    |                                    |    + transcript + summary        |
    |                                    |                                  |
    |                                    └──→ Response decoded as          |
    |                                         RemoteSermonData with        |
    |                                         transcript, notes, summary  |
    |                                    |                                  |
    |                                    |←─ [6] syncSermonFromCloud()   --|
    |                                    |    Calls updateLocalSermon()   |
    |                                    |                                  |
    |                                    |    ❌ BUG: Ignores transcript,  |
    |                                    |    notes, and summary data!    |
    |                                    |                                  |
    |                                    |←─ [7] Sermon updated but      --|
    |                                    |    without transcript/notes   |
    |                                    |                                  |
    |                                    |    User sees empty transcript  |
    |                                    |    and notes on iPad           |
```

---

## 7. BACKGROUND SYNC MANAGER

**File**: `BackgroundSyncManager.swift`

### Periodic Sync
```swift
private func setupPeriodicSync() {
    // Sync every 60 seconds when app is active
    syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        self?.schedulePeriodicSync()
    }
}

private func schedulePeriodicSync() {
    guard isBackgroundSyncEnabled,
          networkStatus == .connected else { return }
    
    Task {
        await syncService.syncAllData()
    }
}
```

### Network-Triggered Sync
```swift
private func handleNetworkStatusChange(_ path: NWPath) {
    let newStatus: NetworkStatus
    
    if path.status == .satisfied {
        if path.isExpensive {
            newStatus = .expensive // Cellular
        } else {
            newStatus = .connected // WiFi
        }
    } else {
        newStatus = .disconnected
    }
    
    if newStatus != networkStatus {
        networkStatus = newStatus
        
        // Trigger sync when network becomes available
        if newStatus == .connected {
            scheduleImmediateSync()
        }
    }
}
```

### Background Task Handling
```swift
private func startBackgroundSync() {
    backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SyncData") { [weak self] in
        self?.endBackgroundSync()
    }
    
    if networkStatus == .connected {
        Task {
            await performBackgroundSync()
        }
    }
}
```

**Current Sync Frequency**:
- Periodic: Every 60 seconds (when app is active)
- On network connectivity change: Immediate
- Manual: Via SermonService.syncAllData()

---

## 8. IDENTIFIED ISSUES & BUGS

### CRITICAL BUG #1: updateLocalSermon() Ignores Related Data

**Severity**: CRITICAL  
**Affected Users**: All multi-device sync users  
**Impact**: Transcript, summary, and notes don't sync to secondary devices

**Root Cause**: 
```swift
private func updateLocalSermon(_ sermon: Sermon, with remoteData: RemoteSermonData) {
    // Only updates basic sermon metadata
    sermon.title = remoteData.title
    sermon.serviceType = remoteData.serviceType
    // ... more basic fields ...
    
    // ❌ IGNORES remoteData.notes, remoteData.transcript, remoteData.summary
}
```

**Solution**:
Update the method to handle notes, transcript, and summary the same way `createLocalSermon()` does:

```swift
private func updateLocalSermon(_ sermon: Sermon, with remoteData: RemoteSermonData) {
    // ... existing basic field updates ...
    
    // Update notes
    if let remoteNotes = remoteData.notes {
        sermon.notes.removeAll()
        for noteData in remoteNotes {
            let note = Note(
                id: noteData.localId,
                text: noteData.text,
                timestamp: noteData.timestamp,
                remoteId: noteData.id
            )
            sermon.notes.append(note)
        }
    }
    
    // Update transcript
    if let transcriptData = remoteData.transcript {
        let transcript = Transcript(
            text: transcriptData.text,
            segments: [],
            remoteId: transcriptData.id
        )
        sermon.transcript = transcript
    }
    
    // Update summary
    if let summaryData = remoteData.summary {
        let summary = Summary(
            id: summaryData.localId,
            title: summaryData.title,
            text: summaryData.text,
            type: summaryData.type,
            status: summaryData.status,
            remoteId: summaryData.id
        )
        sermon.summary = summary
    }
}
```

---

### ISSUE #2: Transcript Segments Not Preserved

**Severity**: MODERATE  
**Impact**: Transcript segments (timestamped chunks) are lost during sync

**Root Cause** (Both create and update):
```swift
// In createLocalSermon (line 300)
let transcript = Transcript(
    text: transcriptData.text,
    segments: [],  // ← Always empty!
    remoteId: transcriptData.id
)

// In updateLocalSermon (after fix)
let transcript = Transcript(
    text: transcriptData.text,
    segments: [],  // ← Always empty!
    remoteId: transcriptData.id
)
```

The backend stores segments as a JSON string in `transcriptData.segments` but the iOS app:
1. Receives it as a string
2. Doesn't deserialize it
3. Creates transcript with empty segments array

**Impact**: Clicking on timestamp in transcript won't work on synced sermons

**Solution**: Deserialize transcript segments when pulling from cloud

---

### ISSUE #3: Sermon Update Timestamp Logic

**Severity**: LOW  
**Impact**: May miss updates in race conditions

**Current Logic** (line 184):
```swift
if remoteSermon.updatedAt > (existingSermon.updatedAt ?? Date.distantPast) {
    updateLocalSermon(existingSermon, with: remoteSermon)
}
```

**Problem**: If local and remote have same `updatedAt`, no update occurs. In case where user edits locally and another device uploads simultaneously, one update is silently dropped.

**Better Approach**: Always update if the remote sermon is newer OR if remote has more data (transcript/summary completed after initial sync)

---

### ISSUE #4: Empty Stub Methods

**Severity**: LOW (Already addressed in commit a219d1e)  
**Location**: Lines 649-659

```swift
private func syncNoteToCloud(_ note: Note, sermonId: String) async throws {
    // Sync note to cloud
}

private func syncTranscriptToCloud(_ transcript: Transcript, sermonId: String) async throws {
    // Sync transcript to cloud
}

private func syncSummaryToCloud(_ summary: Summary, sermonId: String) async throws {
    // Sync summary to cloud
}
```

These are no longer called (removed in commit a219d1e) since data is now included in the main payload, but the stubs remain as dead code.

---

### ISSUE #5: Audio File Download Doesn't Handle Remote Path Correctly

**Severity**: MODERATE  
**Impact**: May fail to download audio files with complex paths

**Location**: `downloadAudioFile()` lines 611-647

**Current Behavior**:
```swift
// Try different bucket names and paths
let bucketOptions = ["sermon-audio", "audio-recordings", "audio-files", "recordings"]
var pathOptions: [String] = []

if let remotePath = remotePath {
    pathOptions.append(remotePath)
}

pathOptions.append(contentsOf: [
    filename,
    "audio-files/\(filename)",
    "recordings/\(filename)"
])
```

**Issue**: Tries many combinations, which is inefficient. Should trust the provided `remotePath`.

---

## 9. BACKEND ANALYSIS

### 9.1 Database Schema Expectations

Based on the backend code:

#### Sermons Table
```
id (UUID, PRIMARY KEY)
local_id (UUID)
user_id (UUID, FOREIGN KEY)
title (TEXT)
date (TIMESTAMP)
service_type (TEXT)
speaker (TEXT, nullable)
audio_file_name (TEXT)
audio_file_url (TEXT, nullable)
audio_file_path (TEXT)
audio_file_size_bytes (INT, nullable)
duration (INT)
transcription_status (TEXT)
summary_status (TEXT)
is_archived (BOOLEAN)
sync_status (TEXT)
created_at (TIMESTAMP)
updated_at (TIMESTAMP)
```

#### Notes Table
```
id (UUID, PRIMARY KEY)
local_id (UUID)
sermon_id (UUID, FOREIGN KEY)
user_id (UUID)
text (TEXT)
timestamp (FLOAT)
```

#### Transcripts Table
```
id (UUID, PRIMARY KEY)
local_id (UUID)
sermon_id (UUID, FOREIGN KEY, UNIQUE)
user_id (UUID)
text (TEXT)
segments (JSONB, nullable)
status (TEXT)
```

#### Summaries Table
```
id (UUID, PRIMARY KEY)
local_id (UUID)
sermon_id (UUID, FOREIGN KEY, UNIQUE)
user_id (UUID)
title (TEXT)
text (TEXT)
type (TEXT)
status (TEXT)
```

### 9.2 API Function Analysis

**create-sermon.js**: ✓ Correctly handles notes, transcript, summary  
**update-sermon.js**: ✓ Correctly handles notes (delete+insert), transcript (upsert), summary (upsert)  
**get-sermons.js**: ✓ Correctly joins all related data

### 9.3 Audio Storage

**Bucket**: `sermon-audio`  
**Path Format**: `{userId}/{filename}.m4a`

Files are uploaded via signed URL (POST to `/api/generate-upload-url`), then referenced by:
- `audio_file_url`: Public HTTPS URL for download
- `audio_file_path`: Storage path for signed operations

---

## 10. DATA FLOW SUMMARY

### Push Flow (Local → Cloud)

```
SermonService.saveSermon()
    ↓
SwiftData: Insert/Update Sermon + Notes + Transcript + Summary
    ↓
Mark sermon: needsSync=true, updatedAt=Date()
    ↓
BackgroundSyncManager (every 60s)
    ↓
SyncService.syncAllData()
    ↓
SyncService.pushLocalChanges()
    ↓
For each sermon with needsSync=true:
    ↓
    ├─ SyncService.syncSermonToCloud()
    │   ├─ Prepare SermonSyncData (basic fields only)
    │   ├─ If no remoteId:
    │   │   └─ createRemoteSermon(sermon:) [PASSES FULL SERMON]
    │   │       ├─ Upload audio to Supabase Storage (signed URL)
    │   │       └─ POST create-sermon API WITH notes/transcript/summary
    │   │           ✓ Backend inserts into 4 tables
    │   │           ✓ Returns new remoteId
    │   │       └─ sermon.remoteId = newRemoteId
    │   │
    │   └─ Else (has remoteId):
    │       └─ updateRemoteSermon(sermon:) [PASSES FULL SERMON]
    │           └─ POST update-sermon API WITH notes/transcript/summary
    │               ✓ Backend updates sermon + upserts transcript/summary
    │               ✓ Backend deletes and re-inserts notes
    │
    ├─ Mark sermon: needsSync=false, syncStatus="synced"
    └─ Save to SwiftData
```

### Pull Flow (Cloud → Local)

```
SyncService.syncAllData()
    ↓
SyncService.pullCloudChanges()
    ↓
fetchRemoteSermons(userId)
    ↓
SupabaseService.fetchRemoteSermons()
    ↓
GET get-sermons?userId={id}
    ↓
Backend returns array of RemoteSermonData WITH notes, transcript, summary
    ↓
For each remoteSermon:
    ↓
    ├─ Find existing local sermon by remoteId
    │   │
    │   ├─ If found AND remoteSermon.updatedAt > local.updatedAt:
    │   │   └─ updateLocalSermon() ❌ BUG: Ignores notes/transcript/summary!
    │   │       └─ Updates: title, serviceType, speaker, transcriptionStatus, etc.
    │   │       └─ SwiftData: Save changes
    │   │
    │   └─ Else if not found:
    │       └─ createLocalSermon() ✓ Correctly creates notes/transcript/summary
    │           ├─ Download audio file
    │           ├─ Create Note objects for notes
    │           ├─ Create Transcript object (with empty segments)
    │           ├─ Create Summary object
    │           └─ SwiftData: Insert sermon + related objects
```

---

## 11. TESTING SCENARIOS

### Scenario 1: Cross-Device Sync with Transcript

**Setup**: iPhone and iPad, same user account

**Steps**:
1. iPhone: Record sermon "Sunday Service"
2. iPhone: Transcript completes automatically (transcriptionStatus="complete")
3. iPhone: Sync triggers (manual or automatic)
4. iPad: Open app, sync triggers
5. iPad: View sermon "Sunday Service"

**Expected**: iPad shows complete transcript ✓  
**Actual**: iPad shows "Transcription Pending" ❌

**Root Cause**: updateLocalSermon() ignores transcript data

---

### Scenario 2: Cross-Device Sync with Notes

**Setup**: iPhone and iPad, same user account

**Steps**:
1. iPhone: Record sermon with notes: ["Good point", "Remember this"]
2. iPhone: Sync triggers
3. iPad: Open app, sync triggers
4. iPad: View sermon details

**Expected**: iPad shows both notes ✓  
**Actual**: iPad shows no notes ❌

**Root Cause**: updateLocalSermon() ignores notes

---

### Scenario 3: Cross-Device Sync with Summary

**Setup**: iPhone and iPad, same user account

**Steps**:
1. iPhone: Record sermon
2. iPhone: Summary generates (summaryStatus="complete")
3. iPhone: Sync triggers
4. iPad: Open app, sync triggers
5. iPad: View sermon

**Expected**: iPad shows summary ✓  
**Actual**: iPad shows "Summary Pending" ❌

**Root Cause**: updateLocalSermon() ignores summary

---

## 12. RECOMMENDATIONS

### IMMEDIATE (Critical)

1. **Fix updateLocalSermon()** to handle notes, transcript, and summary
   - Add code to handle notes similar to createLocalSermon()
   - Add code to deserialize and handle transcript segments
   - Add code to handle summary

2. **Test fix** with multi-device scenario
   - Record on Device A with transcript/notes/summary
   - Sync to cloud
   - Pull on Device B
   - Verify all data appears

### SHORT TERM (Important)

3. **Fix transcript segments deserialization**
   - Backend stores as JSON string, need to parse into TranscriptSegment objects
   - Handle null/empty cases

4. **Improve sync status UI**
   - Show actual sync progress/errors
   - User feedback for what's syncing

5. **Add logging for debugging**
   - Log when updateLocalSermon() is called
   - Log what data is received vs. what's being ignored

### MEDIUM TERM (Enhancement)

6. **Implement conflict resolution**
   - What if both devices edit simultaneously?
   - Current: last write wins, silently drops first edit

7. **Optimize sync frequency**
   - Currently 60 seconds for periodic sync
   - Could be longer when battery is low
   - Could be shorter for critical operations

8. **Add offline capability**
   - Queue sync operations when offline
   - Retry when connection restored

### LONG TERM (Architecture)

9. **Implement true real-time sync**
   - Current: Polling every 60 seconds
   - Better: WebSocket for real-time updates

10. **Improve segment handling**
    - Properly deserialize transcript segments
    - Store with timestamps for seeking

---

## 13. CODE REFERENCES

### Key Files

| File | Lines | Purpose |
|------|-------|---------|
| SyncService.swift | 35-83 | Main sync orchestration |
| SyncService.swift | 85-102 | Push local changes |
| SyncService.swift | 104-197 | Pull cloud changes |
| SyncService.swift | 241-251 | **BUG: updateLocalSermon()** |
| SyncService.swift | 253-326 | createLocalSermon() (works correctly) |
| SyncService.swift | 342-510 | createRemoteSermon() |
| SyncService.swift | 512-605 | updateRemoteSermon() |
| SupabaseService.swift | 342-432 | fetchRemoteSermons() |
| BackgroundSyncManager.swift | 1-210 | Periodic sync trigger |
| SermonService.swift | 73-173 | saveSermon() - marks needsSync |

### Backend Files

| File | Lines | Purpose |
|------|-------|---------|
| create-sermon.js | 1-189 | Create sermon + related data |
| update-sermon.js | 1-210 | Update sermon + related data |
| get-sermons.js | 1-107 | Fetch sermons with joins |

---

## 14. CONCLUSION

The TabletNotes sync system has a well-designed architecture with proper separation between push (upload) and pull (download) operations. The backend correctly handles notes, transcripts, and summaries in both create and update operations.

However, **a critical bug in the iOS client** (`updateLocalSermon()`) causes the pull operation to ignore related data, resulting in notes, transcripts, and summaries not appearing on secondary devices after sync.

The fix is straightforward: update `updateLocalSermon()` to handle the notes, transcript, and summary data that the backend is correctly returning and the RemoteSermonData structure is correctly containing.

**Current Status**: Recent commit a219d1e fixed the push side (now includes transcript/summary in update payloads), but the pull side still has the bug that prevents these updates from being properly incorporated into the local database on secondary devices.

