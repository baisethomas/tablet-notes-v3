-- Check what columns exist in each table
SELECT 'SERMONS COLUMNS:' as info;
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'sermons'
ORDER BY ordinal_position;

SELECT 'NOTES COLUMNS:' as info;
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'notes'
ORDER BY ordinal_position;

SELECT 'SUMMARIES COLUMNS:' as info;
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'summaries'
ORDER BY ordinal_position;

SELECT 'TRANSCRIPTIONS COLUMNS:' as info;
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'transcriptions'
ORDER BY ordinal_position;
