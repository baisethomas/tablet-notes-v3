-- Fix storage policies for sermon-audio bucket (Version 2)
-- This version allows signed URL creation AND file uploads

-- First, let's check the current policies
SELECT policyname FROM pg_policies WHERE tablename = 'objects' AND policyname LIKE '%sermon%';

-- Drop all existing sermon-audio policies
DROP POLICY IF EXISTS "Users can upload to their own folder" ON storage.objects;
DROP POLICY IF EXISTS "Users can read their own files" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own files" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own files" ON storage.objects;
DROP POLICY IF EXISTS "Public read access to sermon audio" ON storage.objects;

-- Alternative approach: More permissive policies for authenticated users
-- Policy 1: Allow authenticated users to INSERT files
CREATE POLICY "Authenticated users can upload sermon audio"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'sermon-audio'
);

-- Policy 2: Allow authenticated users to SELECT their own files
CREATE POLICY "Authenticated users can read sermon audio"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'sermon-audio'
);

-- Policy 3: Allow authenticated users to UPDATE their own files
CREATE POLICY "Authenticated users can update sermon audio"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
    bucket_id = 'sermon-audio'
);

-- Policy 4: Allow authenticated users to DELETE their own files
CREATE POLICY "Authenticated users can delete sermon audio"
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id = 'sermon-audio'
);

-- Verify the new policies
SELECT policyname, cmd, permissive, roles
FROM pg_policies
WHERE tablename = 'objects'
AND policyname LIKE '%sermon%'
ORDER BY policyname;
