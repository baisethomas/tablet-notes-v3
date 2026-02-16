-- Check if profiles table structure matches expectations
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns 
WHERE table_name = 'profiles' 
ORDER BY ordinal_position;

-- Check if the trigger function exists
SELECT routine_name, routine_definition
FROM information_schema.routines 
WHERE routine_name = 'handle_new_user';

-- Check if the trigger exists
SELECT trigger_name, event_manipulation, action_statement
FROM information_schema.triggers 
WHERE trigger_name = 'on_auth_user_created';

-- Check RLS policies on profiles table
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies 
WHERE tablename = 'profiles';

-- Check if profiles table has RLS enabled
SELECT schemaname, tablename, rowsecurity
FROM pg_tables 
WHERE tablename = 'profiles';

-- Count existing profiles
SELECT COUNT(*) as profile_count FROM profiles;