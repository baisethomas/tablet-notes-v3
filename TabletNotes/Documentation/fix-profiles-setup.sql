-- Add missing columns to profiles table (if they don't exist)
-- Note: These will fail if columns already exist, which is fine

DO $$ 
BEGIN
    -- Add subscription_status column if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'subscription_status') THEN
        ALTER TABLE profiles ADD COLUMN subscription_status TEXT DEFAULT 'active';
    END IF;
    
    -- Add monthly usage tracking columns if they don't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'monthly_recording_count') THEN
        ALTER TABLE profiles ADD COLUMN monthly_recording_count INTEGER DEFAULT 0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'monthly_recording_minutes') THEN
        ALTER TABLE profiles ADD COLUMN monthly_recording_minutes INTEGER DEFAULT 0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'current_storage_used_gb') THEN
        ALTER TABLE profiles ADD COLUMN current_storage_used_gb DECIMAL(10,2) DEFAULT 0.0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'monthly_export_count') THEN
        ALTER TABLE profiles ADD COLUMN monthly_export_count INTEGER DEFAULT 0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'last_usage_reset_date') THEN
        ALTER TABLE profiles ADD COLUMN last_usage_reset_date TIMESTAMP WITH TIME ZONE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'subscription_product_id') THEN
        ALTER TABLE profiles ADD COLUMN subscription_product_id TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'subscription_purchase_date') THEN
        ALTER TABLE profiles ADD COLUMN subscription_purchase_date TIMESTAMP WITH TIME ZONE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'subscription_renewal_date') THEN
        ALTER TABLE profiles ADD COLUMN subscription_renewal_date TIMESTAMP WITH TIME ZONE;
    END IF;
END $$;

-- Ensure RLS is enabled
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Create RLS policies (these will fail if they already exist, which is fine)
DO $$ 
BEGIN
    -- Drop existing policies if they exist and recreate them
    DROP POLICY IF EXISTS "Users can view their own profile" ON profiles;
    DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;
    DROP POLICY IF EXISTS "Users can update their own profile" ON profiles;
    DROP POLICY IF EXISTS "Users can delete their own profile" ON profiles;
    
    -- Create the policies
    CREATE POLICY "Users can view their own profile"
        ON profiles FOR SELECT
        USING (auth.uid() = id);

    CREATE POLICY "Users can insert their own profile"
        ON profiles FOR INSERT
        WITH CHECK (auth.uid() = id);

    CREATE POLICY "Users can update their own profile"
        ON profiles FOR UPDATE
        USING (auth.uid() = id)
        WITH CHECK (auth.uid() = id);

    CREATE POLICY "Users can delete their own profile"
        ON profiles FOR DELETE
        USING (auth.uid() = id);
END $$;

-- Create the trigger function (replace if exists)
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO profiles (id, email, name, is_email_verified)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'name', 'User'),
        NEW.email_confirmed_at IS NOT NULL
    );
    RETURN NEW;
EXCEPTION
    WHEN others THEN
        -- Log the error but don't fail the user creation
        RAISE WARNING 'Failed to create profile for user %: %', NEW.id, SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger (replace if exists)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();