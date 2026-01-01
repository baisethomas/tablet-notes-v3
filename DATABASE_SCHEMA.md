# Tablet Notes Database Schema Reference

**Last Updated:** 2025-11-05
**Database:** Supabase PostgreSQL
**Storage:** Supabase Storage (bucket: `sermon-audio`)

---

## Core Tables

### `sermons`
Main table for sermon recordings.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key (auto-generated) |
| `local_id` | UUID | NO | - | Device-local UUID for sync |
| `user_id` | UUID | NO | - | FK to auth.users |
| `title` | TEXT | NO | - | Sermon title |
| `date` | TIMESTAMPTZ | NO | - | Recording date |
| `service_type` | TEXT | NO | - | e.g. "Sunday Service", "Bible Study" |
| `speaker` | TEXT | YES | NULL | Speaker name (optional) |
| `audio_file_name` | TEXT | NO | - | Filename only (e.g. "sermon_ABC.m4a") |
| `audio_file_path` | TEXT | YES | - | Full storage path in bucket |
| `audio_file_url` | TEXT | YES | NULL | Public Supabase Storage URL |
| `audio_file_size_bytes` | BIGINT | YES | NULL | File size in bytes |
| `duration` | INTEGER | NO | 0 | Recording duration in seconds |
| `transcription_status` | TEXT | NO | 'pending' | Values: pending, processing, complete, failed |
| `summary_status` | TEXT | NO | 'pending' | Values: pending, processing, complete, failed |
| `is_archived` | BOOLEAN | NO | false | Whether sermon is archived |
| `sync_status` | TEXT | NO | 'localOnly' | Values: localOnly, syncing, synced, error |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | Auto-set on insert |
| `updated_at` | TIMESTAMPTZ | NO | `NOW()` | Auto-updated by trigger |

**Indexes:**
- `idx_sermons_user_id` on `user_id`
- `idx_sermons_date` on `date DESC`
- `idx_sermons_updated_at` on `updated_at DESC`
- `idx_sermons_local_id` on `local_id`

**Unique Constraints:**
- `unique_user_local_id` on `(user_id, local_id)`

**RLS Policies:**
- Users can only view/insert/update/delete their own sermons (filtered by `user_id`)

---

### `transcripts`
Stores AI-generated transcriptions.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `local_id` | UUID | NO | - | Device-local UUID for sync |
| `sermon_id` | UUID | NO | - | FK to sermons.id (CASCADE DELETE) |
| `user_id` | UUID | NO | - | FK to auth.users |
| `text` | TEXT | NO | - | Full transcript text |
| `status` | TEXT | NO | 'complete' | processing, complete, failed |
| `processing_time_seconds` | DOUBLE PRECISION | YES | NULL | Time taken to process |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | Auto-set |
| `updated_at` | TIMESTAMPTZ | NO | `NOW()` | Auto-updated by trigger |

**Indexes:**
- `idx_transcripts_sermon_id` on `sermon_id`
- `idx_transcripts_user_id` on `user_id`

**Unique Constraints:**
- `unique_sermon_transcript` on `sermon_id` (one transcript per sermon)

**RLS Policies:**
- Users can only access their own transcripts

---

### `transcript_segments`
Stores individual segments/words from transcription.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `transcript_id` | UUID | NO | - | FK to transcripts.id (CASCADE DELETE) |
| `text` | TEXT | NO | - | Segment text |
| `start_time` | DOUBLE PRECISION | NO | - | Start time in seconds |
| `end_time` | DOUBLE PRECISION | NO | - | End time in seconds |
| `confidence` | DOUBLE PRECISION | YES | NULL | AssemblyAI confidence score |
| `speaker` | TEXT | YES | NULL | Speaker label (if available) |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | Auto-set |

---

### `summaries`
Stores AI-generated summaries.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `local_id` | UUID | NO | - | Device-local UUID for sync |
| `sermon_id` | UUID | NO | - | FK to sermons.id (CASCADE DELETE) |
| `user_id` | UUID | NO | - | FK to auth.users |
| `title` | TEXT | NO | 'Summary' | AI-generated title |
| `text` | TEXT | NO | - | Summary content |
| `type` | TEXT | NO | - | Service type (matches sermon.service_type) |
| `status` | TEXT | NO | 'processing' | processing, complete, failed |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | Auto-set |
| `updated_at` | TIMESTAMPTZ | NO | `NOW()` | Auto-updated by trigger |

**Indexes:**
- `idx_summaries_sermon_id` on `sermon_id`
- `idx_summaries_user_id` on `user_id`

**Unique Constraints:**
- `unique_sermon_summary` on `sermon_id` (one summary per sermon)

**RLS Policies:**
- Users can only access their own summaries

---

### `notes`
User-created notes during recording.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `local_id` | UUID | NO | - | Device-local UUID for sync |
| `sermon_id` | UUID | NO | - | FK to sermons.id (CASCADE DELETE) |
| `user_id` | UUID | NO | - | FK to auth.users |
| `text` | TEXT | NO | - | Note content |
| `timestamp` | DOUBLE PRECISION | NO | - | Timestamp in recording (seconds) |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | Auto-set |
| `updated_at` | TIMESTAMPTZ | NO | `NOW()` | Auto-updated by trigger |

**Indexes:**
- `idx_notes_sermon_id` on `sermon_id`
- `idx_notes_timestamp` on `timestamp`
- `idx_notes_user_id` on `user_id`

**Unique Constraints:**
- `unique_sermon_local_id_notes` on `(sermon_id, local_id)`

**RLS Policies:**
- Users can only access their own notes

---

## Storage

### Bucket: `sermon-audio`
- **Public:** false (requires authentication)
- **Path Structure:** `{user_id}/{uuid}.m4a`
- **Example:** `94771a20-c9e7-4a85-ad3d-b8ac29a23501/abc123.m4a`

**RLS Policies:**
- Users can upload/view/update/delete only their own audio files
- Path must start with their user_id

---

## Important Notes

### Field Name Conventions
- **Database:** Uses `snake_case` (e.g., `audio_file_name`, `user_id`)
- **iOS Swift:** Uses `camelCase` (e.g., `audioFileName`, `userId`)
- **API Payload:** Uses `camelCase` (e.g., `audioFileName`, `userId`)
- **Backend JS:** Maps `camelCase` → `snake_case` before inserting

### Sync Metadata
Sermons include sync tracking fields:
- `local_id`: Original device UUID
- `sync_status`: Current sync state
- `updated_at`: Last modification time (for conflict resolution)

### Audio File Storage
1. **Upload:** iOS uploads to `sermon-audio` bucket via signed URL
2. **Path:** Stored in `audio_file_path` field
3. **URL:** Public URL stored in `audio_file_url` field
4. **Name:** Filename stored in `audio_file_name` field

### Common Mistakes to Avoid
1. ❌ Using `audio-files` bucket → ✅ Use `sermon-audio`
2. ❌ Sending `duration` as `null` → ✅ Always send `0` if unknown
3. ❌ Using `snake_case` in API → ✅ Use `camelCase` in JSON payloads
4. ❌ Forgetting `user_id` → ✅ Always include for RLS

### Triggers
All tables have `updated_at` triggers that auto-update on any UPDATE operation.

---

## API Payload Examples

### Create Sermon (POST /api/create-sermon)
```json
{
  "localId": "179f207c-2eef-4dd9-a908-8098f3fc4f7a",
  "title": "Sunday Morning Service",
  "date": "2025-11-05T10:00:00Z",
  "serviceType": "Sunday Service",
  "speaker": "John Doe",
  "audioFileName": "sermon_ABC.m4a",
  "audioFilePath": "94771a20-c9e7-4a85-ad3d-b8ac29a23501/sermon_ABC.m4a",
  "audioFileUrl": "https://...supabase.co/storage/v1/object/public/sermon-audio/...",
  "audioFileSizeBytes": 1234567,
  "duration": 3600,
  "transcriptionStatus": "pending",
  "summaryStatus": "pending",
  "isArchived": false
}
```

### Get Sermons (GET /api/get-sermons?userId=...)
**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "a98566c7-9a87-41e3-a310-83582402a261",
      "localId": "179f207c-2eef-4dd9-a908-8098f3fc4f7a",
      "title": "Sunday Morning Service",
      "audioFileURL": "https://...supabase.co/storage/v1/object/public/sermon-audio/...",
      "date": "2025-11-05T10:00:00+00:00",
      "serviceType": "Sunday Service",
      "speaker": "John Doe",
      "transcriptionStatus": "complete",
      "summaryStatus": "complete",
      "isArchived": false,
      "userId": "94771a20-c9e7-4a85-ad3d-b8ac29a23501",
      "updatedAt": "2025-11-05T10:30:00.000+00:00"
    }
  ],
  "timestamp": "2025-11-05T10:30:00.000Z"
}
```
