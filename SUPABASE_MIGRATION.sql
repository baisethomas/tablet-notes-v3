-- TabletNotes Supabase Migration Script
-- Safe migration that preserves existing data
-- Run this INSTEAD of SUPABASE_SCHEMA.sql if you have existing data

-- ============================================================================
-- STEP 1: Add missing columns to existing tables (if they don't exist)
-- ============================================================================

-- Add columns to sermons table if they don't exist
DO $$
BEGIN
    -- Add local_id if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='sermons' AND column_name='local_id') THEN
        ALTER TABLE sermons ADD COLUMN local_id UUID;
        -- Backfill with id values for existing records
        UPDATE sermons SET local_id = id WHERE local_id IS NULL;
        ALTER TABLE sermons ALTER COLUMN local_id SET NOT NULL;
    END IF;

    -- Add audio_file_size_bytes if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='sermons' AND column_name='audio_file_size_bytes') THEN
        ALTER TABLE sermons ADD COLUMN audio_file_size_bytes BIGINT;
    END IF;

    -- Add created_at if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='sermons' AND column_name='created_at') THEN
        ALTER TABLE sermons ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    -- Add updated_at if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='sermons' AND column_name='updated_at') THEN
        ALTER TABLE sermons ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
END $$;

-- Add columns to notes table if they don't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='notes' AND column_name='local_id') THEN
        ALTER TABLE notes ADD COLUMN local_id UUID;
        UPDATE notes SET local_id = id WHERE local_id IS NULL;
        ALTER TABLE notes ALTER COLUMN local_id SET NOT NULL;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='notes' AND column_name='created_at') THEN
        ALTER TABLE notes ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='notes' AND column_name='updated_at') THEN
        ALTER TABLE notes ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
END $$;

-- Add columns to transcripts table if they don't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='transcripts' AND column_name='local_id') THEN
        ALTER TABLE transcripts ADD COLUMN local_id UUID;
        UPDATE transcripts SET local_id = id WHERE local_id IS NULL;
        ALTER TABLE transcripts ALTER COLUMN local_id SET NOT NULL;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='transcripts' AND column_name='processing_time_seconds') THEN
        ALTER TABLE transcripts ADD COLUMN processing_time_seconds DOUBLE PRECISION;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='transcripts' AND column_name='created_at') THEN
        ALTER TABLE transcripts ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='transcripts' AND column_name='updated_at') THEN
        ALTER TABLE transcripts ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
END $$;

-- Add columns to summaries table if they don't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='summaries' AND column_name='local_id') THEN
        ALTER TABLE summaries ADD COLUMN local_id UUID;
        UPDATE summaries SET local_id = id WHERE local_id IS NULL;
        ALTER TABLE summaries ALTER COLUMN local_id SET NOT NULL;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='summaries' AND column_name='created_at') THEN
        ALTER TABLE summaries ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='summaries' AND column_name='updated_at') THEN
        ALTER TABLE summaries ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
END $$;

-- ============================================================================
-- STEP 2: Create indexes (if they don't exist)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_sermons_user_id ON sermons(user_id);
CREATE INDEX IF NOT EXISTS idx_sermons_date ON sermons(date DESC);
CREATE INDEX IF NOT EXISTS idx_sermons_updated_at ON sermons(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_notes_sermon_id ON notes(sermon_id);
CREATE INDEX IF NOT EXISTS idx_notes_timestamp ON notes(timestamp);
CREATE INDEX IF NOT EXISTS idx_transcripts_sermon_id ON transcripts(sermon_id);
CREATE INDEX IF NOT EXISTS idx_summaries_sermon_id ON summaries(sermon_id);

-- ============================================================================
-- STEP 3: Add unique constraints (if they don't exist)
-- ============================================================================

DO $$
BEGIN
    -- Unique constraint for user_id + local_id
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'unique_user_local_id') THEN
        ALTER TABLE sermons ADD CONSTRAINT unique_user_local_id UNIQUE(user_id, local_id);
    END IF;

    -- Unique constraint for sermon notes
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'unique_sermon_local_id') THEN
        ALTER TABLE notes ADD CONSTRAINT unique_sermon_local_id UNIQUE(sermon_id, local_id);
    END IF;

    -- Unique constraint for sermon transcript
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'unique_sermon_transcript') THEN
        ALTER TABLE transcripts ADD CONSTRAINT unique_sermon_transcript UNIQUE(sermon_id);
    END IF;

    -- Unique constraint for sermon summary
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'unique_sermon_summary') THEN
        ALTER TABLE summaries ADD CONSTRAINT unique_sermon_summary UNIQUE(sermon_id);
    END IF;
END $$;

-- ============================================================================
-- STEP 4: Create or update RLS policies
-- ============================================================================

-- Enable RLS if not already enabled
ALTER TABLE sermons ENABLE ROW LEVEL SECURITY;
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE transcripts ENABLE ROW LEVEL SECURITY;
ALTER TABLE summaries ENABLE ROW LEVEL SECURITY;

-- Drop old policies if they exist and recreate (to ensure they're correct)
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
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

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
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

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
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

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
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own summaries"
    ON summaries FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================================
-- STEP 5: Create storage bucket (if it doesn't exist)
-- ============================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('sermon-audio', 'sermon-audio', false)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- STEP 6: Storage policies
-- ============================================================================

-- Drop and recreate storage policies
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
    )
    WITH CHECK (
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
-- STEP 7: Create triggers for updated_at
-- ============================================================================

-- Create function if it doesn't exist
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop and recreate triggers
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
-- MIGRATION COMPLETE
-- ============================================================================

-- Verify migration
SELECT
    'Migration complete!' as status,
    (SELECT COUNT(*) FROM sermons) as total_sermons,
    (SELECT COUNT(*) FROM notes) as total_notes,
    (SELECT COUNT(*) FROM transcripts) as total_transcripts,
    (SELECT COUNT(*) FROM summaries) as total_summaries;
