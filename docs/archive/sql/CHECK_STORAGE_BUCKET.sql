-- Check if sermon-audio bucket exists
SELECT id, name, public, file_size_limit, allowed_mime_types
FROM storage.buckets
WHERE name = 'sermon-audio';

-- Check storage policies for sermon-audio bucket
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'objects'
AND policyname LIKE '%sermon-audio%';
