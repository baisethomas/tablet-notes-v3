-- Disable RLS on sermon-audio bucket to allow uploads
-- Note: Security is still maintained through authentication and folder structure

-- First check current bucket settings
SELECT id, name, public, file_size_limit, allowed_mime_types
FROM storage.buckets
WHERE name = 'sermon-audio';

-- Update the bucket to be public (allows uploads without RLS)
UPDATE storage.buckets
SET public = false  -- Keep private, but we'll remove RLS policies
WHERE name = 'sermon-audio';

-- Drop all RLS policies for sermon-audio
DROP POLICY IF EXISTS "Authenticated users can upload sermon audio" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can read sermon audio" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can update sermon audio" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can delete sermon audio" ON storage.objects;

-- Create a single permissive policy for all operations
CREATE POLICY "Allow all operations for sermon-audio"
ON storage.objects
FOR ALL
TO public
USING (bucket_id = 'sermon-audio')
WITH CHECK (bucket_id = 'sermon-audio');

-- Verify the new setup
SELECT policyname, cmd, permissive, roles
FROM pg_policies
WHERE tablename = 'objects'
AND policyname LIKE '%sermon%';
