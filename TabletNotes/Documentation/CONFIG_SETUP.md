# Configuration Setup Guide

This guide explains how to set up API keys and configuration for TabletNotes.

## Quick Start

The only setup required to build and run the app is creating a `Config.plist` file with your AssemblyAI API key. All other configuration files are already committed to the repository.

1. **Copy the example configuration file:**
   ```bash
   cp TabletNotes/Resources/Config.plist.example TabletNotes/Resources/Config.plist
   ```

2. **Open `Config.plist` and add your AssemblyAI API key:**
   - `AssemblyAIAPIKey`: Your AssemblyAI API key

3. **Build and run the app** — all other config is pre-configured.

## Configuration Files

| File | Contents | In Version Control? |
|------|----------|-------------------|
| `Resources/Config.plist` | AssemblyAI API key | No (gitignored via `*.plist`) |
| `Resources/SupabaseConfig.swift` | Supabase project URL + anon key | Yes (anon key is safe for client-side) |
| `Resources/ApiBibleConfig.swift` | API.Bible key + Bible translation IDs | Yes |
| `Resources/StripeConfig.swift` | Stripe publishable key + product IDs | Yes (archived — not actively used, app uses StoreKit) |
| `Resources/AssemblyAIKey.swift` | Loads AssemblyAI key from Config.plist | No (gitignored) |

### Config.plist (Required Setup)

This is the only file you need to create. It stores sensitive API keys that should not be committed.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AssemblyAIAPIKey</key>
    <string>YOUR_ASSEMBLYAI_API_KEY</string>
</dict>
</plist>
```

### SupabaseConfig.swift (Pre-configured)

Contains the Supabase project URL and anonymous key. The anon key has restricted permissions and is safe for client-side use per Supabase guidelines.

### ApiBibleConfig.swift (Pre-configured)

Contains the API.Bible API key and popular Bible translation IDs (KJV, NASB, NKJV, ESV, NIV, etc.).

### StripeConfig.swift (Archived — Not Active)

Contains Stripe publishable key and product IDs. Currently not used — the iOS app uses Apple In-App Purchases (StoreKit) for subscriptions. Retained for potential future web-based subscription management.

## Getting API Keys

### AssemblyAI (Required)
1. Sign up at https://www.assemblyai.com/dashboard/signup
2. Navigate to your dashboard
3. Copy your API key
4. Add it to `Config.plist`

### Supabase (Pre-configured)
The project's Supabase credentials are already in `SupabaseConfig.swift`. If you need to point to a different Supabase project:
1. Go to https://supabase.com and create a project
2. Navigate to Project Settings → API
3. Copy the Project URL and anon/public key
4. Update `SupabaseConfig.swift`

### API.Bible (Pre-configured)
The API.Bible key is already in `ApiBibleConfig.swift`. If you need a new key:
1. Sign up at https://scripture.api.bible
2. Create an application
3. Copy your API key
4. Update `ApiBibleConfig.swift`

## Security Notes

- `Config.plist` is excluded from version control (`.gitignore` includes `*.plist`)
- `AssemblyAIKey.swift` is excluded from version control
- Supabase anon keys are safe for client-side code (restricted permissions via Row Level Security)
- Never commit secret/service-role keys to the repository
- Stripe secret key is stored only in Netlify environment variables

## Troubleshooting

**Error: "Failed to load AssemblyAIAPIKey from Config.plist"**
- Make sure `Config.plist` exists in `TabletNotes/Resources/`
- Verify the file is included in your Xcode project target
- Check that the key name is exactly `AssemblyAIAPIKey` (case-sensitive)

**Error: "AssemblyAIAPIKey is not configured in Config.plist"**
- Make sure you've replaced `YOUR_ASSEMBLYAI_API_KEY` with your actual key
- Verify the value is not an empty string

**Build errors about missing files**
- Ensure `Config.plist` is added to the Xcode project target
- Check that the file is in the correct location: `TabletNotes/Resources/Config.plist`
