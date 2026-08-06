-- Add default UUID generation for sermons.id column
-- This allows INSERTs without explicitly providing an id

-- First check current default
SELECT column_name, column_default, is_nullable
FROM information_schema.columns
WHERE table_name = 'sermons' AND column_name = 'id';

-- Add default if not already set
ALTER TABLE sermons
ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- Verify it was set
SELECT column_name, column_default, is_nullable
FROM information_schema.columns
WHERE table_name = 'sermons' AND column_name = 'id';
