-- TabletNotes Supabase Database Schema
-- This schema supports cross-device syncing of sermons, notes, transcripts, and summaries

-- ============================================================================
-- SERMONS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS sermons (
    -- Primary identifiers
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    local_id UUID NOT NULL, -- Client-side UUID for local storage
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Sermon metadata
    title TEXT NOT NULL,
    date TIMESTAMPTZ NOT NULL,
    service_type TEXT NOT NULL, -- e.g., "Sunday Service", "Bible Study"
    speaker TEXT,

    -- Audio file
    audio_file_name TEXT NOT NULL,
    audio_file_url TEXT, -- Supabase Storage URL
    audio_file_size_bytes BIGINT,

    -- Processing status
    transcription_status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, complete, failed
    summary_status TEXT NOT NULL DEFAULT 'pending',

    -- Organization
    is_archived BOOLEAN DEFAULT FALSE,

    -- Sync metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Indexes for faster queries
    CONSTRAINT unique_user_local_id UNIQUE(user_id, local_id)
);

-- Index for fetching user's sermons
CREATE INDEX IF NOT EXISTS idx_sermons_user_id ON sermons(user_id);
CREATE INDEX IF NOT EXISTS idx_sermons_date ON sermons(date DESC);
CREATE INDEX IF NOT EXISTS idx_sermons_updated_at ON sermons(updated_at DESC);

-- ============================================================================
-- NOTES TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    local_id UUID NOT NULL,
    sermon_id UUID NOT NULL REFERENCES sermons(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Note content
    text TEXT NOT NULL,
    timestamp DOUBLE PRECISION NOT NULL, -- Time in seconds within the recording

    -- Sync metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT unique_sermon_local_id UNIQUE(sermon_id, local_id)
);

CREATE INDEX IF NOT EXISTS idx_notes_sermon_id ON notes(sermon_id);
CREATE INDEX IF NOT EXISTS idx_notes_timestamp ON notes(timestamp);

-- ============================================================================
-- TRANSCRIPTS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS transcripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    local_id UUID NOT NULL,
    sermon_id UUID NOT NULL REFERENCES sermons(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Transcript content
    text TEXT NOT NULL,
    segments JSONB, -- Array of transcript segments with timestamps

    -- Processing metadata
    status TEXT NOT NULL DEFAULT 'pending',
    processing_time_seconds DOUBLE PRECISION,

    -- Sync metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT unique_sermon_transcript UNIQUE(sermon_id)
);

CREATE INDEX IF NOT EXISTS idx_transcripts_sermon_id ON transcripts(sermon_id);

-- ============================================================================
-- SUMMARIES TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    local_id UUID NOT NULL,
    sermon_id UUID NOT NULL REFERENCES sermons(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Summary content
    title TEXT NOT NULL,
    text TEXT NOT NULL,
    type TEXT NOT NULL, -- e.g., "devotional", "bullet", "theological"

    -- Processing metadata
    status TEXT NOT NULL DEFAULT 'pending',

    -- Sync metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT unique_sermon_summary UNIQUE(sermon_id)
);

CREATE INDEX IF NOT EXISTS idx_summaries_sermon_id ON summaries(sermon_id);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE sermons ENABLE ROW LEVEL SECURITY;
ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE transcripts ENABLE ROW LEVEL SECURITY;
ALTER TABLE summaries ENABLE ROW LEVEL SECURITY;

-- Sermons policies
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
-- STORAGE BUCKETS
-- ============================================================================

-- Create storage bucket for audio files
INSERT INTO storage.buckets (id, name, public)
VALUES ('sermon-audio', 'sermon-audio', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for audio files
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
-- FUNCTIONS & TRIGGERS
-- ============================================================================

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_sermons_updated_at BEFORE UPDATE ON sermons
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_notes_updated_at BEFORE UPDATE ON notes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_transcripts_updated_at BEFORE UPDATE ON transcripts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_summaries_updated_at BEFORE UPDATE ON summaries
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE sermons IS 'Stores sermon recordings with metadata and processing status';
COMMENT ON TABLE notes IS 'User-created notes during sermon recordings';
COMMENT ON TABLE transcripts IS 'AI-generated transcripts of sermon audio';
COMMENT ON TABLE summaries IS 'AI-generated summaries of sermon content';
COMMENT ON COLUMN sermons.local_id IS 'UUID from client device for syncing';
COMMENT ON COLUMN sermons.audio_file_url IS 'URL to audio file in Supabase Storage';
COMMENT ON COLUMN transcripts.segments IS 'JSON array of transcript segments with timestamps';
