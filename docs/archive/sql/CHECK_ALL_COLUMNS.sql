-- Get all columns for all tables in one query
SELECT
    table_name,
    column_name,
    data_type,
    ordinal_position
FROM information_schema.columns
WHERE table_name IN ('sermons', 'notes', 'summaries', 'transcriptions', 'profiles')
ORDER BY table_name, ordinal_position;
