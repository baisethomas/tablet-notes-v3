# Tablet Notes

Native iOS sermon note-taking and sermon intelligence software.

Tablet Notes is designed for people who want to stay engaged during a sermon while still capturing what matters. The app combines audio recording, timestamped personal notes, transcription, AI-assisted summaries, and cloud synchronization in a single iPhone experience.

## Status

**Pre-release testing.** Tablet Notes currently has approximately 15 active test users and is in release hardening while awaiting final approval for public release.

## What it does

- Records sermon audio with pause and resume support
- Lets users take timestamped notes during a recording
- Produces sermon transcripts and AI-assisted summaries
- Supports context-aware interaction with sermon content
- Synchronizes user data through Supabase
- Supports offline-first usage with background synchronization
- Includes subscription and entitlement management for the planned freemium model

## Product focus

Tablet Notes is intentionally built around the sermon experience rather than general meeting transcription. The product combines listening, personal reflection, structured sermon history, and AI-assisted review without turning the service into a screen-first experience.

## Architecture snapshot

- **iOS:** SwiftUI, SwiftData, AVFoundation, StoreKit 2
- **Cloud:** Supabase for authentication, PostgreSQL data, and storage
- **Transcription:** AssemblyAI services in the current repository implementation
- **AI:** OpenAI-backed summarization and contextual features
- **Backend:** Serverless API functions with Redis-backed rate limiting and supporting services

## Current development focus

The current phase is focused on release reliability, data safety, synchronization behavior, recording stability, and incorporating feedback from active testers.

## Technical documentation

The previous detailed repository README has been preserved at [`docs/technical-readme.md`](docs/technical-readme.md) for architecture, setup, API documentation, service descriptions, and development notes.
