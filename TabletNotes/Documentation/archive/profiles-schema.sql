-- Profiles table for user data
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    name TEXT NOT NULL,
    profile_image_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_email_verified BOOLEAN DEFAULT FALSE,
    subscription_tier TEXT DEFAULT 'premium',
    subscription_status TEXT DEFAULT 'active',
    subscription_expiry TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '14 days'),
    subscription_product_id TEXT,
    subscription_purchase_date TIMESTAMP WITH TIME ZONE,
    subscription_renewal_date TIMESTAMP WITH TIME ZONE,
    monthly_recording_count INTEGER DEFAULT 0,
    monthly_recording_minutes INTEGER DEFAULT 0,
    current_storage_used_gb DECIMAL(10,2) DEFAULT 0.0,
    monthly_export_count INTEGER DEFAULT 0,
    last_usage_reset_date TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies for profiles table
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

-- Database trigger to automatically create profile on user signup
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
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function when a new user is created
CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user();

-- User notification settings table
CREATE TABLE user_notification_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
    transcription_complete BOOLEAN DEFAULT TRUE,
    summary_complete BOOLEAN DEFAULT TRUE,
    sync_errors BOOLEAN DEFAULT TRUE,
    weekly_digest BOOLEAN DEFAULT FALSE,
    product_updates BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS for notification settings
ALTER TABLE user_notification_settings ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_notification_settings
CREATE POLICY "Users can view their own notification settings"
    ON user_notification_settings FOR SELECT
    USING (user_id = auth.uid());

CREATE POLICY "Users can insert their own notification settings"
    ON user_notification_settings FOR INSERT
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own notification settings"
    ON user_notification_settings FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete their own notification settings"
    ON user_notification_settings FOR DELETE
    USING (user_id = auth.uid());