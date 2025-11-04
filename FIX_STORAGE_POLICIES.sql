-- Fix storage policies for sermon-audio bucket
-- This allows authenticated users to upload/access their own audio files

-- Drop existing policies if they exist (to avoid conflicts)
DROP POLICY IF EXISTS "Users can upload to their own folder" ON storage.objects;
DROP POLICY IF EXISTS "Users can read their own files" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own files" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own files" ON storage.objects;
DROP POLICY IF EXISTS "Public read access to sermon audio" ON storage.objects;

-- Policy 1: Allow authenticated users to INSERT (upload) files to their own folder
CREATE POLICY "Users can upload to their own folder"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'sermon-audio'
    AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Policy 2: Allow users to SELECT (read) their own files
CREATE POLICY "Users can read their own files"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'sermon-audio'
    AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Policy 3: Allow users to UPDATE their own files
CREATE POLICY "Users can update their own files"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
    bucket_id = 'sermon-audio'
    AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Policy 4: Allow users to DELETE their own files
CREATE POLICY "Users can delete their own files"
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id = 'sermon-audio'
    AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Verify policies were created
SELECT policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'objects'
AND policyname LIKE '%sermon%'
ORDER BY policyname;
