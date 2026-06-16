# Configuration Setup Guide

This guide explains the API keys and configuration TabletNotes uses.

## Quick Start

No per-developer secret setup is required to build and run the app. All
third-party API keys for paid/metered services (AssemblyAI, OpenAI) live in
the **Netlify backend environment**, not in the client. The committed config
files below hold only client-safe values.

Build and run the `TabletNotes` scheme — no `Config.plist` or key file to
create.

## Configuration Files

| File | Contents | In Version Control? |
|------|----------|-------------------|
| `Resources/SupabaseConfig.swift` | Supabase project URL + anon key | Yes (anon key is safe for client-side) |
| `Resources/ApiBibleConfig.swift` | API.Bible key + Bible translation IDs | Yes (see note below) |

### SupabaseConfig.swift (Pre-configured)

Contains the Supabase project URL and anonymous key. The anon key has
restricted permissions (Row Level Security) and is safe for client-side use
per Supabase guidelines.

### ApiBibleConfig.swift (Pre-configured)

Contains the API.Bible key and popular Bible translation IDs (KJV, NASB,
NKJV, ESV, NIV, etc.).

> **Note:** the committed API.Bible key is being migrated off the client to
> the backend proxy (`bible-api.js`) — see TAB-48. Until that lands, the key
> ships in the client and must be rotated if exposed.

## Backend-managed keys (not in the client)

These are configured as Netlify environment variables on the API project, not
in the iOS app:

- `ASSEMBLYAI_API_KEY` — transcription (file + live session tokens). The app
  calls `/api/transcribe`, `/api/transcribe-status`, and
  `/api/assemblyai-live-token` with a Supabase Bearer token; AssemblyAI is
  never contacted directly from the client.
- `OPENAI_API_KEY` — summarization via `/api/summarize`.
- `BIBLE_API_KEY` — used by the `bible-api.js` proxy (see TAB-48).
- `SUPABASE_SERVICE_ROLE_KEY`, `UPSTASH_REDIS_REST_URL/TOKEN` — server-only.

## Payments

The iOS app uses **Apple In-App Purchases (StoreKit)** for subscriptions.
There is no Stripe integration in the client.

## Security Notes

- No AssemblyAI/OpenAI key ships in the IPA — all metered AI access is
  proxied through the authenticated Netlify backend.
- Supabase anon keys are safe for client-side code (restricted via Row Level
  Security).
- Never commit secret/service-role keys to the repository.
