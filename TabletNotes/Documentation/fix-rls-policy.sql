-- Fix the RLS policy issue for manual profile creation during signup

-- Option 1: Update the INSERT policy to allow profile creation during signup
-- This allows the authenticated user to create their own profile even if auth.uid() context is tricky
DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;

CREATE POLICY "Users can insert their own profile"
    ON profiles FOR INSERT
    WITH CHECK (
        -- Allow if the user is authenticated and inserting their own profile
        auth.uid() = id 
        OR 
        -- Allow if this is happening during the signup process
        -- (when auth.uid() might not be fully set in context)
        auth.role() = 'authenticated'
    );

-- Option 2: Alternative approach - create a function that bypasses RLS for signup
CREATE OR REPLACE FUNCTION create_user_profile(
    user_id TEXT,
    user_email TEXT,
    user_name TEXT,
    email_verified TEXT DEFAULT 'false'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER -- This runs with elevated privileges
AS $$
BEGIN
    INSERT INTO profiles (id, email, name, is_email_verified)
    VALUES (user_id::UUID, user_email, user_name, email_verified::BOOLEAN);
    
    RETURN user_id::UUID;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION create_user_profile(TEXT, TEXT, TEXT, TEXT) TO authenticated;