-- TabletNotes Supabase Migration Script (FINAL - Matches Actual Schema)
-- Safe migration that preserves existing data
-- Works with your actual column names

-- ============================================================================
-- STEP 1: Rename transcriptions to transcripts (for code consistency)
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'transcriptions')
       AND NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'transcripts') THEN
        ALTER TABLE transcriptions RENAME TO transcripts;
        RAISE NOTICE 'Renamed transcriptions to transcripts';
    END IF;
END $$;

-- ============================================================================
-- STEP 2: Add missing columns to sermons table
-- ============================================================================

DO $$
BEGIN
    -- Add local_id (maps to id for existing records)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='sermons' AND column_name='local_id') THEN
        ALTER TABLE sermons ADD COLUMN local_id UUID;
        UPDATE sermons SET local_id = id WHERE local_id IS NULL;
        ALTER TABLE sermons ALTER COLUMN local_id SET NOT NULL;
        RAISE NOTICE 'Added local_id to sermons';
    END IF;

    -- Rename recording_date to date (for consistency with iOS model)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sermons' AND column_name='recording_date')
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sermons' AND column_name='date') THEN
        ALTER TABLE sermons RENAME COLUMN recording_date TO date;
        RAISE NOTICE 'Renamed recording_date to date';
    END IF;

    -- Add audio_file_name (extract from audio_file_path)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='sermons' AND column_name='audio_file_name') THEN
        ALTER TABLE sermons ADD COLUMN audio_file_name TEXT;
        -- Extract filename from path
        UPDATE sermons SET audio_file_name =
            CASE
                WHEN audio_file_path IS NOT NULL AND audio_file_path != ''
                THEN regexp_replace(audio_file_path, '.*/', '')
                ELSE 'unknown.m4a'
            END
        WHERE audio_file_name IS NULL;
        RAISE NOTICE 'Added audio_file_name to sermons';
    END IF;

    -- Add audio_file_url (for Supabase Storage URLs)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='sermons' AND column_name='audio_file_url') THEN
        ALTER TABLE sermons ADD COLUMN audio_file_url TEXT;
        RAISE NOTICE 'Added audio_file_url to sermons';
    END IF;

    -- Add audio_file_size_bytes
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='sermons' AND column_name='audio_file_size_bytes') THEN
        ALTER TABLE sermons ADD COLUMN audio_file_size_bytes BIGINT;
        RAISE NOTICE 'Added audio_file_size_bytes to sermons';
    END IF;
END $$;

-- ============================================================================
-- STEP 3: Add missing columns to notes table
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='notes' AND column_name='local_id') THEN
        ALTER TABLE notes ADD COLUMN local_id UUID;
        UPDATE notes SET local_id = id WHERE local_id IS NULL;
        ALTER TABLE notes ALTER COLUMN local_id SET NOT NULL;
        RAISE NOTICE 'Added local_id to notes';
    END IF;
END $$;

-- ============================================================================
-- STEP 4: Add missing columns to transcripts table
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='transcripts' AND column_name='local_id') THEN
        ALTER TABLE transcripts ADD COLUMN local_id UUID;
        UPDATE transcripts SET local_id = id WHERE local_id IS NULL;
        ALTER TABLE transcripts ALTER COLUMN local_id SET NOT NULL;
        RAISE NOTICE 'Added local_id to transcripts';
    END IF;

    -- Rename 'text' to 'text' is already correct, check for status
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='transcripts' AND column_name='status') THEN
        ALTER TABLE transcripts ADD COLUMN status TEXT DEFAULT 'complete';
        RAISE NOTICE 'Added status to transcripts';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='transcripts' AND column_name='processing_time_seconds') THEN
        ALTER TABLE transcripts ADD COLUMN processing_time_seconds DOUBLE PRECISION;
        RAISE NOTICE 'Added processing_time_seconds to transcripts';
    END IF;
END $$;

-- ============================================================================
-- STEP 5: Add missing columns to summaries table
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='summaries' AND column_name='local_id') THEN
        ALTER TABLE summaries ADD COLUMN local_id UUID;
        UPDATE summaries SET local_id = id WHERE local_id IS NULL;
        ALTER TABLE summaries ALTER COLUMN local_id SET NOT NULL;
        RAISE NOTICE 'Added local_id to summaries';
    END IF;

    -- Add title column (for new AI-generated titles)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='summaries' AND column_name='title') THEN
        ALTER TABLE summaries ADD COLUMN title TEXT NOT NULL DEFAULT 'Summary';
        RAISE NOTICE 'Added title to summaries';
    END IF;

    -- Rename 'format' to 'type' (for consistency with iOS model)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='summaries' AND column_name='format')
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='summaries' AND column_name='type') THEN
        ALTER TABLE summaries RENAME COLUMN format TO type;
        RAISE NOTICE 'Renamed format to type in summaries';
    END IF;
END $$;

-- ============================================================================
-- STEP 6: Create indexes for better query performance
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_sermons_user_id ON sermons(user_id);
CREATE INDEX IF NOT EXISTS idx_sermons_date ON sermons(date DESC);
CREATE INDEX IF NOT EXISTS idx_sermons_updated_at ON sermons(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_sermons_local_id ON sermons(local_id);

CREATE INDEX IF NOT EXISTS idx_notes_sermon_id ON notes(sermon_id);
CREATE INDEX IF NOT EXISTS idx_notes_timestamp ON notes(timestamp);
CREATE INDEX IF NOT EXISTS idx_notes_user_id ON notes(user_id);

CREATE INDEX IF NOT EXISTS idx_transcripts_sermon_id ON transcripts(sermon_id);
CREATE INDEX IF NOT EXISTS idx_transcripts_user_id ON transcripts(user_id);

CREATE INDEX IF NOT EXISTS idx_summaries_sermon_id ON summaries(sermon_id);
CREATE INDEX IF NOT EXISTS idx_summaries_user_id ON summaries(user_id);

-- ============================================================================
-- STEP 7: Add unique constraints
-- ============================================================================

DO $$
BEGIN
    -- Unique constraint for user_id + local_id
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_user_local_id') THEN
        ALTER TABLE sermons ADD CONSTRAINT unique_user_local_id UNIQUE(user_id, local_id);
        RAISE NOTICE 'Added unique constraint for sermons user_id + local_id';
    END IF;

    -- Unique constraint for sermon notes
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_sermon_local_id_notes') THEN
        ALTER TABLE notes ADD CONSTRAINT unique_sermon_local_id_notes UNIQUE(sermon_id, local_id);
        RAISE NOTICE 'Added unique constraint for notes';
    END IF;

    -- Unique constraint for sermon transcript
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_sermon_transcript') THEN
        ALTER TABLE transcripts ADD CONSTRAINT unique_sermon_transcript UNIQUE(sermon_id);
        RAISE NOTICE 'Added unique constraint for transcripts';
    END IF;

    -- Unique constraint for sermon summary
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_sermon_summary') THEN
        ALTER TABLE summaries ADD CONSTRAINT unique_sermon_summary UNIQUE(sermon_id);
        RAISE NOTICE 'Added unique constraint for summaries';
    END IF;
END $$;

-- ============================================================================
-- STEP 8: Enable RLS and create policies
-- ============================================================================

-- Enable RLS
ALTER TABLE sermons ENABLE ROW LEVEL SECURITY;
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE transcripts ENABLE ROW LEVEL SECURITY;
ALTER TABLE summaries ENABLE ROW LEVEL SECURITY;

-- Sermons policies
DROP POLICY IF EXISTS "Users can view their own sermons" ON sermons;
DROP POLICY IF EXISTS "Users can insert their own sermons" ON sermons;
DROP POLICY IF EXISTS "Users can update their own sermons" ON sermons;
DROP POLICY IF EXISTS "Users can delete their own sermons" ON sermons;

CREATE POLICY "Users can view their own sermons"
    ON sermons FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own sermons"
    ON sermons FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own sermons"
    ON sermons FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own sermons"
    ON sermons FOR DELETE
    USING (auth.uid() = user_id);

-- Notes policies
DROP POLICY IF EXISTS "Users can view their own notes" ON notes;
DROP POLICY IF EXISTS "Users can insert their own notes" ON notes;
DROP POLICY IF EXISTS "Users can update their own notes" ON notes;
DROP POLICY IF EXISTS "Users can delete their own notes" ON notes;

CREATE POLICY "Users can view their own notes"
    ON notes FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own notes"
    ON notes FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own notes"
    ON notes FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own notes"
    ON notes FOR DELETE
    USING (auth.uid() = user_id);

-- Transcripts policies
DROP POLICY IF EXISTS "Users can view their own transcripts" ON transcripts;
DROP POLICY IF EXISTS "Users can insert their own transcripts" ON transcripts;
DROP POLICY IF EXISTS "Users can update their own transcripts" ON transcripts;
DROP POLICY IF EXISTS "Users can delete their own transcripts" ON transcripts;

CREATE POLICY "Users can view their own transcripts"
    ON transcripts FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own transcripts"
    ON transcripts FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own transcripts"
    ON transcripts FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own transcripts"
    ON transcripts FOR DELETE
    USING (auth.uid() = user_id);

-- Summaries policies
DROP POLICY IF EXISTS "Users can view their own summaries" ON summaries;
DROP POLICY IF EXISTS "Users can insert their own summaries" ON summaries;
DROP POLICY IF EXISTS "Users can update their own summaries" ON summaries;
DROP POLICY IF EXISTS "Users can delete their own summaries" ON summaries;

CREATE POLICY "Users can view their own summaries"
    ON summaries FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own summaries"
    ON summaries FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own summaries"
    ON summaries FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own summaries"
    ON summaries FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================================
-- STEP 9: Create storage bucket for audio files
-- ============================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('sermon-audio', 'sermon-audio', false)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- STEP 10: Storage policies
-- ============================================================================

DROP POLICY IF EXISTS "Users can upload their own audio files" ON storage.objects;
DROP POLICY IF EXISTS "Users can view their own audio files" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own audio files" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own audio files" ON storage.objects;

CREATE POLICY "Users can upload their own audio files"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'sermon-audio'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Users can view their own audio files"
    ON storage.objects FOR SELECT
    USING (
        bucket_id = 'sermon-audio'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Users can update their own audio files"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'sermon-audio'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Users can delete their own audio files"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'sermon-audio'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

-- ============================================================================
-- STEP 11: Create/update triggers for updated_at
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_sermons_updated_at ON sermons;
DROP TRIGGER IF EXISTS update_notes_updated_at ON notes;
DROP TRIGGER IF EXISTS update_transcripts_updated_at ON transcripts;
DROP TRIGGER IF EXISTS update_summaries_updated_at ON summaries;

CREATE TRIGGER update_sermons_updated_at BEFORE UPDATE ON sermons
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_notes_updated_at BEFORE UPDATE ON notes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_transcripts_updated_at BEFORE UPDATE ON transcripts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_summaries_updated_at BEFORE UPDATE ON summaries
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- MIGRATION COMPLETE - Show summary
-- ============================================================================

SELECT
    '✅ Migration complete!' as status,
    (SELECT COUNT(*) FROM sermons) as total_sermons,
    (SELECT COUNT(*) FROM notes) as total_notes,
    (SELECT COUNT(*) FROM transcripts) as total_transcripts,
    (SELECT COUNT(*) FROM summaries) as total_summaries;
