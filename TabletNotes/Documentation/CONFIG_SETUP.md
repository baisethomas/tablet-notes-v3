# Configuration Setup Guide

This guide explains how to set up API keys and configuration for TabletNotes.

## Quick Start

1. **Copy the example configuration file:**
   ```bash
   cp TabletNotes/Resources/Config.plist.example TabletNotes/Resources/Config.plist
   ```

2. **Open `Config.plist` and fill in your API keys:**
   - `SupabaseProjectURL`: Your Supabase project URL (e.g., `https://your-project.supabase.co`)
   - `SupabaseAnonKey`: Your Supabase anonymous key (found in your Supabase project settings)
   - `AssemblyAIAPIKey`: Your AssemblyAI API key (get it from https://www.assemblyai.com/dashboard/signup)

3. **Build and run the app** - the configuration will be automatically loaded.

## Security Notes

- ✅ `Config.plist` is excluded from version control (via `.gitignore`)
- ✅ `Config.plist.example` is committed as a template for other developers
- ✅ Never commit `Config.plist` with real API keys
- ✅ The app will fail to launch with clear error messages if keys are missing or invalid

## Getting API Keys

### Supabase
1. Go to https://supabase.com and create a project (or use an existing one)
2. Navigate to Project Settings → API
3. Copy the Project URL and anon/public key
4. Add them to `Config.plist`

### AssemblyAI
1. Sign up at https://www.assemblyai.com/dashboard/signup
2. Navigate to your dashboard
3. Copy your API key
4. Add it to `Config.plist`

## Troubleshooting

**Error: "Failed to load [key] from Config.plist"**
- Make sure `Config.plist` exists in `TabletNotes/Resources/`
- Verify the file is included in your Xcode project target
- Check that the key names match exactly (case-sensitive)

**Error: "[key] is not configured in Config.plist"**
- Make sure you've replaced the placeholder values (those starting with `YOUR_`)
- Verify the values are not empty strings

**Build errors about missing Config.plist**
- Ensure `Config.plist` is added to your Xcode project target
- Check that the file is in the correct location: `TabletNotes/Resources/Config.plist`

