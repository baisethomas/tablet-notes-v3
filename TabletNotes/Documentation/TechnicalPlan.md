# Tablet App – Technical Plan

## 1. Overview

This document summarizes the technical and architectural plan for the Tablet app, a sermon note-taking application with real-time recording, transcription, AI summarization, and scripture analysis.

---

## 2. Key Decisions & Requirements

- **Transcription**: On-device using iOS SFSpeechRecognizer. Handles 1-minute session limit by auto-restarting sessions seamlessly; user is unaware of session restarts. Transcripts are merged after recording stops.
- **Summarization**: Always generated automatically after transcription, using OpenAI (cloud-based). If a summary job fails, the user can retry from the app. Cloud processing is always on for all users.
- **Data Storage**: Use best-practice Apple technology (SwiftData or Core Data) for local persistence of audio, notes, and transcripts. Notes are timestamped and linked to the audio timeline.
- **Cloud Sync**: Automatic sync to Supabase (no manual trigger). If sync fails, the app retries automatically. Users can delete all their cloud data from within the app.
- **Notifications**: In-app banner is shown when a summary is ready (no email or push notifications for MVP).
- **Analytics**: Use Firebase Analytics for MVP.
- **Testing**: Manual QA and SwiftUI snapshot testing are sufficient for launch.
- **Privacy**: Cloud processing is always on, but users can delete all their cloud data from within the app.

---

## 3. Technical Architecture & File Structure

```
TabletNotes/
├── App/
│   └── TabletNotesApp.swift
├── Features/
│   ├── Authentication/
│   ├── Onboarding/
│   ├── Dashboard/
│   ├── Recording/
│   ├── Transcription/
│   ├── Notes/
│   ├── Settings/
│   └── Subscription/
├── Core/
│   ├── Models/
│   ├── Database/
│   ├── Services/
│   ├── Navigation/
│   └── DI/
├── UI/
│   ├── Components/
│   ├── Styles/
│   └── Helpers/
├── Utils/
│   ├── Extensions/
│   ├── Formatters/
│   ├── Helpers/
│   └── Constants/
├── Resources/
│   ├── Assets.xcassets/
│   ├── Fonts/
│   └── Localizable.strings
└── Tests/
    ├── UnitTests/
    ├── IntegrationTests/
    └── UITests/
```

---

## 4. Main Modules & Responsibilities

### Core Services
- **RecordingService**: Handles AVFoundation audio recording, session management, file storage.
- **TranscriptionService**: Manages SFSpeechRecognizer, auto-restarts sessions, merges transcripts.
- **NoteService**: Manages timestamped notes, links notes to audio timeline.
- **SummaryService**: Handles summary job creation, OpenAI API calls, retry logic, and result storage.
- **SyncService**: Automatic sync of notes, transcripts, and summaries to Supabase; handles retries and conflict resolution.
- **AnalyticsService**: Integrates with Firebase Analytics for event tracking.
- **NotificationService**: Displays in-app banners when summaries are ready.
- **AuthService**: Handles Supabase authentication and user management.
- **CloudDataService**: Handles deletion of all user data from Supabase.

### Data Models
- **User**: Auth info, preferences.
- **Sermon**: Audio file, metadata, service type, timestamps.
- **Note**: Text, timestamp, linked to sermon.
- **Transcript**: Text, timestamps, linked to sermon.
- **Summary**: Text, type (devotional, bullet, theological), status.
- **SyncStatus**: Local/cloud, last sync, error state.

---

## 5. System Flow Diagram (Mermaid)

```
flowchart TD
    A[User starts recording] --> B[Audio saved locally]
    B --> C[SFSpeechRecognizer transcribes in real-time]
    C --> D[Auto-restart session if needed]
    D --> E[Transcripts merged after stop]
    A --> F[User takes timestamped notes]
    F --> G[Notes linked to audio timeline]
    E --> H[Summary job sent to OpenAI (cloud)]
    H --> I[Summary result stored]
    I --> J[In-app banner: "Summary Ready"]
    E --> K[Auto-sync to Supabase (if paid)]
    G --> K
    I --> K
    L[User deletes cloud data] --> M[Supabase data deleted]
    subgraph Analytics
        A
        F
        H
        J
    end
```

---

## 6. Key Flows

- **Recording**: Start → Audio + live transcript + notes → Stop → Merge transcript → Trigger summary → Show banner → Sync
- **Summary**: Always auto-generated after transcription. Retry available if failed.
- **Sync**: Automatic, retries on failure, user can delete all cloud data.
- **Notifications**: In-app banner only for summary readiness.

---

## 7. Best Practices

- Use **SwiftData** (or Core Data if more mature/needed) for local persistence.
- Use **Combine** for all async and state flows.
- Use **Coordinator** for navigation.
- Use **Firebase Analytics** for event tracking.
- All cloud operations (sync, summary) are **automatic** and **transparent** to the user.
- **Manual QA** and **SwiftUI snapshot testing** for launch.

---

## 8. Next Steps

- Use this document as a living reference for engineering and product decisions.
- Update as requirements or best practices evolve. 