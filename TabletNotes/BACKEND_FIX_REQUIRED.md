# Backend Fix: Store Transcript, Summary, and Notes

## ✅ STATUS: IMPLEMENTED

The backend changes described in this document have been **successfully implemented**. Multi-device sync for transcripts, summaries, and notes is now fully functional.

## Problem (Resolved)

The iOS app was correctly **sending** transcript, summary, and notes data to the backend during sync, but the backend was **not storing** them in the database. This caused the data to be lost when the app pulled the sermon back from the cloud.

**This issue has been resolved with the backend updates.**

### Evidence from Logs

**iOS sends complete data:**
```json
{
  "transcript": {
    "text": "Testing. Testing. 1, 2, 3. Testing. Testing. 1, 2, 3. See if this works.",
    "status": "complete"
  },
  "summary": {
    "title": "",
    "text": "I'm sorry, but the provided text does not contain any sermon content...",
    "type": "Sermon",
    "status": "complete"
  }
}
```

**Backend returns null:**
```json
{
  "transcriptionStatus": "complete",
  "summaryStatus": "complete",
  "notes": [],
  "transcript": null,
  "summary": null
}
```

## Root Cause

The Netlify functions (`create-sermon` and `update-sermon`) are:
1. ✅ Receiving the transcript/summary/notes in the request payload
2. ❌ NOT inserting/updating records in the `transcripts`, `summaries`, and `notes` tables
3. ❌ NOT returning these related records when fetching sermons

## Required Backend Changes

### 1. Database Schema (Verify These Tables Exist)

#### `transcripts` table
```sql
CREATE TABLE IF NOT EXISTS public.transcripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sermon_id UUID REFERENCES public.sermons(id) ON DELETE CASCADE,
    local_id UUID NOT NULL,
    text TEXT NOT NULL,
    segments JSONB,
    status TEXT DEFAULT 'complete',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX idx_transcripts_sermon_id ON public.transcripts(sermon_id);
CREATE INDEX idx_transcripts_local_id ON public.transcripts(local_id);
```

#### `summaries` table
```sql
CREATE TABLE IF NOT EXISTS public.summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sermon_id UUID REFERENCES public.sermons(id) ON DELETE CASCADE,
    local_id UUID NOT NULL,
    title TEXT,
    text TEXT NOT NULL,
    type TEXT NOT NULL,
    status TEXT DEFAULT 'complete',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX idx_summaries_sermon_id ON public.summaries(sermon_id);
CREATE INDEX idx_summaries_local_id ON public.summaries(local_id);
```

#### `notes` table
```sql
CREATE TABLE IF NOT EXISTS public.notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sermon_id UUID REFERENCES public.sermons(id) ON DELETE CASCADE,
    local_id UUID NOT NULL,
    text TEXT NOT NULL,
    timestamp DOUBLE PRECISION NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX idx_notes_sermon_id ON public.notes(sermon_id);
CREATE INDEX idx_notes_local_id ON public.notes(local_id);
```

### 2. Update `create-sermon` Function

**Location:** `netlify/functions/create-sermon.js` (or similar)

**Changes Needed:**

```javascript
// After creating the sermon record, add these inserts:

// 1. Insert transcript if provided
if (transcript && transcript.text) {
  const { data: transcriptData, error: transcriptError } = await supabase
    .from('transcripts')
    .insert({
      sermon_id: sermonId,
      local_id: transcript.id || uuidv4(),
      text: transcript.text,
      segments: transcript.segments || null,
      status: transcript.status || 'complete'
    })
    .select()
    .single();

  if (transcriptError) {
    console.error('Error inserting transcript:', transcriptError);
    // Don't fail the whole operation, but log it
  }
}

// 2. Insert summary if provided
if (summary && summary.text) {
  const { data: summaryData, error: summaryError } = await supabase
    .from('summaries')
    .insert({
      sermon_id: sermonId,
      local_id: summary.id || uuidv4(),
      title: summary.title || '',
      text: summary.text,
      type: summary.type || 'Sermon',
      status: summary.status || 'complete'
    })
    .select()
    .single();

  if (summaryError) {
    console.error('Error inserting summary:', summaryError);
    // Don't fail the whole operation, but log it
  }
}

// 3. Insert notes if provided
if (notes && Array.isArray(notes) && notes.length > 0) {
  const notesData = notes.map(note => ({
    sermon_id: sermonId,
    local_id: note.id || uuidv4(),
    text: note.text,
    timestamp: note.timestamp
  }));

  const { error: notesError } = await supabase
    .from('notes')
    .insert(notesData);

  if (notesError) {
    console.error('Error inserting notes:', notesError);
    // Don't fail the whole operation, but log it
  }
}
```

### 3. Update `update-sermon` Function

**Location:** `netlify/functions/update-sermon.js` (or similar)

**Changes Needed:**

```javascript
// After updating the sermon record, handle related data:

// 1. Update or insert transcript
if (transcript && transcript.text) {
  // Try to update existing transcript first
  const { data: existingTranscript } = await supabase
    .from('transcripts')
    .select('id')
    .eq('sermon_id', remoteId)
    .single();

  if (existingTranscript) {
    // Update existing
    await supabase
      .from('transcripts')
      .update({
        text: transcript.text,
        segments: transcript.segments || null,
        status: transcript.status || 'complete',
        updated_at: new Date().toISOString()
      })
      .eq('id', existingTranscript.id);
  } else {
    // Insert new
    await supabase
      .from('transcripts')
      .insert({
        sermon_id: remoteId,
        local_id: transcript.id || uuidv4(),
        text: transcript.text,
        segments: transcript.segments || null,
        status: transcript.status || 'complete'
      });
  }
}

// 2. Update or insert summary
if (summary && summary.text) {
  const { data: existingSummary } = await supabase
    .from('summaries')
    .select('id')
    .eq('sermon_id', remoteId)
    .single();

  if (existingSummary) {
    // Update existing
    await supabase
      .from('summaries')
      .update({
        title: summary.title || '',
        text: summary.text,
        type: summary.type || 'Sermon',
        status: summary.status || 'complete',
        updated_at: new Date().toISOString()
      })
      .eq('id', existingSummary.id);
  } else {
    // Insert new
    await supabase
      .from('summaries')
      .insert({
        sermon_id: remoteId,
        local_id: summary.id || uuidv4(),
        title: summary.title || '',
        text: summary.text,
        type: summary.type || 'Sermon',
        status: summary.status || 'complete'
      });
  }
}

// 3. Replace notes (delete old, insert new)
if (notes && Array.isArray(notes)) {
  // Delete existing notes for this sermon
  await supabase
    .from('notes')
    .delete()
    .eq('sermon_id', remoteId);

  // Insert new notes if any
  if (notes.length > 0) {
    const notesData = notes.map(note => ({
      sermon_id: remoteId,
      local_id: note.id || uuidv4(),
      text: note.text,
      timestamp: note.timestamp
    }));

    await supabase
      .from('notes')
      .insert(notesData);
  }
}
```

### 4. Update `get-sermons` Function

**Location:** `netlify/functions/get-sermons.js` (or similar)

**Changes Needed:**

```javascript
// When fetching sermons, include related data:

const { data: sermons, error } = await supabase
  .from('sermons')
  .select(`
    *,
    transcript:transcripts(*),
    summary:summaries(*),
    notes(*)
  `)
  .eq('user_id', userId)
  .order('date', { ascending: false });

// Then format the response to match the expected structure:
const formattedSermons = sermons.map(sermon => ({
  id: sermon.id,
  localId: sermon.local_id,
  title: sermon.title,
  audioFileURL: sermon.audio_file_url,
  audioFilePath: sermon.audio_file_path,
  date: sermon.date,
  serviceType: sermon.service_type,
  speaker: sermon.speaker,
  transcriptionStatus: sermon.transcription_status,
  summaryStatus: sermon.summary_status,
  isArchived: sermon.is_archived,
  userId: sermon.user_id,
  updatedAt: sermon.updated_at,

  // Include related data
  transcript: sermon.transcript?.length > 0 ? {
    id: sermon.transcript[0].id,
    localId: sermon.transcript[0].local_id,
    text: sermon.transcript[0].text,
    segments: sermon.transcript[0].segments,
    status: sermon.transcript[0].status
  } : null,

  summary: sermon.summary?.length > 0 ? {
    id: sermon.summary[0].id,
    localId: sermon.summary[0].local_id,
    title: sermon.summary[0].title,
    text: sermon.summary[0].text,
    type: sermon.summary[0].type,
    status: sermon.summary[0].status
  } : null,

  notes: sermon.notes?.map(note => ({
    id: note.id,
    localId: note.local_id,
    text: note.text,
    timestamp: note.timestamp
  })) || []
}));

return {
  statusCode: 200,
  body: JSON.stringify({
    success: true,
    data: formattedSermons,
    timestamp: new Date().toISOString()
  })
};
```

## iOS Workaround (Temporary)

The iOS app has been updated with a **temporary workaround** that preserves local transcript/summary/notes data when the backend returns null. This prevents data loss but means the data won't sync between devices until the backend is fixed.

**File:** `TabletNotes/Services/Sync/SyncService.swift`
**Lines:** 255-337

The workaround logs warnings like:
```
⚠️ Preserving local transcript (remote has no transcript - likely backend bug)
⚠️ Preserving local summary (remote has no summary - likely backend bug)
⚠️ Preserving N local notes (remote has no notes - likely backend bug)
```

## Testing the Backend Fix

After implementing the backend changes:

1. **Create a new sermon** on Device A with:
   - Notes during recording
   - Wait for transcription
   - Wait for summary

2. **Check the database** directly:
   ```sql
   -- Check sermon was created
   SELECT * FROM sermons WHERE id = 'sermon-id';

   -- Check transcript was stored
   SELECT * FROM transcripts WHERE sermon_id = 'sermon-id';

   -- Check summary was stored
   SELECT * FROM summaries WHERE sermon_id = 'sermon-id';

   -- Check notes were stored
   SELECT * FROM notes WHERE sermon_id = 'sermon-id';
   ```

3. **Fetch from API** to verify the response includes all data:
   ```bash
   curl -H "Authorization: Bearer <token>" \
     "https://your-api.netlify.app/api/get-sermons?userId=<user-id>"
   ```

4. **Test on Device B**:
   - Open app (should trigger sync)
   - Verify sermon appears with transcript, summary, and notes

## Priority

🔴 **HIGH PRIORITY** - This is a critical bug preventing multi-device sync from working properly. Users are losing their transcripts and summaries when switching devices.

## Questions?

If you need help implementing these changes or have questions about the database schema, please reach out!
