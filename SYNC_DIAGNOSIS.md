# Sync Diagnosis - Transcript/Summary Not Syncing

## Current Status
- ✅ Audio syncs successfully
- ❌ Transcript does NOT sync
- ❌ Summary does NOT sync
- ❌ Notes do NOT sync

## What We Changed
1. Modified `createRemoteSermon()` to include notes/transcript/summary in payload
2. Modified `updateRemoteSermon()` to include notes/transcript/summary in payload
3. Backend already supports this (create-sermon.js and update-sermon.js)

## Critical Questions to Answer

### Q1: When is the sermon FIRST synced?
**Check:** Does the first sync happen BEFORE or AFTER transcript/summary are attached?

**Timeline:**
```
T+0s:  Recording stops
T+2s:  Sermon saved with transcript=nil, summary=nil, needsSync=true
T+3s:  First sync triggered → createRemoteSermon called
       ❓ Does sermon have transcript/summary at this point?
T+30s: Transcription completes → sermon.transcript = Transcript(...)
T+32s: Sermon updated, needsSync=true again
T+33s: Second sync triggered → updateRemoteSermon called
       ✅ Should include transcript in payload
T+60s: Summary completes → sermon.summary = Summary(...)
T+62s: Sermon updated, needsSync=true again
T+63s: Third sync triggered → updateRemoteSermon called
       ✅ Should include summary in payload
```

### Q2: Is needsSync being set correctly?
**Check `SermonService.swift` line 167:**
```swift
if let currentUser = authManager.currentUser, currentUser.canSync {
    markSermonForSync(sermonID)
    triggerSyncIfNeeded()
}
```

**Requirements:**
- User must have `canSync = true` (Premium tier)
- `markSermonForSync()` sets `needsSync = true`
- `triggerSyncIfNeeded()` calls `syncAllData()`

### Q3: Are the sync payloads actually including the data?
**What to check in logs:**

**For createRemoteSermon:**
```
[SyncService] Including X notes in payload
[SyncService] Including transcript in payload
[SyncService] Including summary in payload: [title]
[SyncService] JSON payload: {... "notes": [...], "transcript": {...}, "summary": {...} }
```

**For updateRemoteSermon:**
```
[SyncService] Updating remote sermon: [title]
[SyncService] Including X notes in update payload
[SyncService] Including transcript in update payload
[SyncService] Including summary in update payload: [title]
[SyncService] Update JSON payload: {... "notes": [...], "transcript": {...}, "summary": {...} }
```

### Q4: Is the backend actually storing the data?
**Check Netlify logs for:**
- `create-sermon` function calls
- `update-sermon` function calls
- Any warnings about failed inserts for notes/transcripts/summaries

**Backend code (create-sermon.js lines 102-166):**
- Lines 102-121: Insert notes if provided
- Lines 123-143: Insert transcript if provided
- Lines 145-166: Insert summary if provided

**Backend code (update-sermon.js lines 110-190):**
- Lines 110-139: Update notes if provided
- Lines 141-164: Upsert transcript if provided
- Lines 166-190: Upsert summary if provided

### Q5: Is the iPad actually requesting the full data?
**Check get-sermons.js lines 40-76:**
```javascript
.select(`
  id, local_id, title, audio_file_url, audio_file_path, ...
  notes (id, local_id, text, timestamp),
  transcripts (id, local_id, text, segments, status),
  summaries (id, local_id, title, text, type, status)
`)
```

## Testing Plan

### Test 1: Check First Sync Timing
1. Record SHORT sermon (10 seconds)
2. Watch logs closely:
   - When is `[SyncService] Creating remote sermon` logged?
   - Is `sermon.transcript` nil or populated at that moment?
   - Check the JSON payload log

### Test 2: Check Update Sync
1. Wait for transcription to complete
2. Watch for `[SyncService] Updating remote sermon`
3. Verify logs show "Including transcript in update payload"
4. Check actual JSON payload includes transcript

### Test 3: Check Backend
1. Open Netlify dashboard
2. Go to Functions → Logs
3. Filter for `create-sermon` and `update-sermon`
4. Check if notes/transcript/summary are being received
5. Look for any SQL errors

### Test 4: Check Database Directly
1. Open Supabase dashboard
2. Go to Table Editor
3. Check `notes` table - any rows for the sermon?
4. Check `transcripts` table - any rows for the sermon?
5. Check `summaries` table - any rows for the sermon?

### Test 5: Check iPad Pull
1. Look at `get-sermons` response in iPad logs
2. Verify response includes nested notes/transcript/summary
3. Check if `createLocalSermon` is being called
4. Verify local SwiftData has the objects

## Most Likely Issue

Based on the timing analysis, I suspect:

**The first sync happens TOO EARLY** - before transcript/summary exist.

**Solution Options:**
1. ✅ Ensure updateRemoteSermon includes full data (DONE)
2. ❓ Verify update is actually being triggered after transcript/summary complete
3. ❓ Check if sync is waiting for BOTH transcript AND summary before first sync
4. ❓ Delay first sync until transcription starts (not ideal)

## Next Steps

1. Record a test sermon on iPhone
2. Capture COMPLETE logs from start to finish
3. Share logs showing:
   - When createRemoteSermon is called
   - When updateRemoteSermon is called (if at all)
   - What payloads were sent
   - What the backend received
4. Check database directly to see what's actually stored
