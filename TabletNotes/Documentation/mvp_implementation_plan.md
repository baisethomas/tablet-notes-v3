# TabletNotes MVP Implementation Plan

## Overview

This implementation plan combines the technical requirements from the new prompt with our previous architectural recommendations to create a comprehensive roadmap for building the TabletNotes MVP. The plan focuses on practical next steps for implementation, assuming project setup is already complete.

## Core MVP Features

1. **Real-Time Sermon Recording with On-Device Transcription**
2. **Live Note-Taking During Recording**
3. **AI Sermon Summarization**
4. **Supabase Sync (Paid Feature)**
5. **Email Notification for Completed Summaries**

## Technical Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                      iOS Application                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Recording & │  │ Note-Taking │  │ Local Storage       │  │
│  │Transcription│  │   Module    │  │ - Audio Files       │  │
│  │   Module    │  │             │  │ - Transcriptions    │  │
│  └─────────────┘  └─────────────┘  │ - Notes             │  │
│         │                │         │ - User Preferences  │  │
│         └────────┬───────┘         └─────────────────────┘  │
│                  │                           │              │
│         ┌────────┴───────┐                   │              │
│         │  Sync Manager  │◄──────────────────┘              │
│         └────────┬───────┘                                  │
└─────────────────┬─────────────────────────────────────────┬─┘
                  │                                         │
                  ▼                                         │
┌─────────────────────────────────┐                         │
│         Supabase Backend        │                         │
│ ┌─────────────┐ ┌─────────────┐ │                         │
│ │    Auth     │ │  Database   │ │                         │
│ └─────────────┘ └─────────────┘ │                         │
│                                 │                         │
│ ┌─────────────┐ ┌─────────────┐ │                         │
│ │   Storage   │ │Edge Functions│ │                         │
│ └─────────────┘ └──────┬──────┘ │                         │
└────────────────────────┼────────┘                         │
                         │                                  │
                         ▼                                  │
                ┌─────────────────┐                         │
                │    OpenAI API   │                         │
                └─────────────────┘                         │
                         │                                  │
                         ▼                                  │
                ┌─────────────────┐                         │
                │  Email Service  │◄────────────────────────┘
                │  (Resend API)   │
                └─────────────────┘
```

### Data Flow

1. User records sermon and takes notes on iOS device
2. Audio is processed locally using SFSpeechRecognizer
3. Notes and transcription are stored locally
4. For paid users, data syncs to Supabase
5. Summarization job is queued via Supabase Edge Function
6. OpenAI generates summary
7. User is notified via email when summary is ready
8. User can view summary in app

## Implementation Tasks

### 1. Core Data Models

```swift
// Define core data models for the application

struct Sermon {
    var id: UUID
    var title: String
    var recordingDate: Date
    var serviceType: ServiceType
    var duration: TimeInterval
    var audioFileURL: URL
    var transcriptionStatus: TranscriptionStatus
    var summaryStatus: SummaryStatus
    var syncStatus: SyncStatus
    var isPaid: Bool
}

struct Transcription {
    var id: UUID
    var sermonId: UUID
    var text: String
    var segments: [TranscriptionSegment]
    var lastModified: Date
}

struct TranscriptionSegment {
    var id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var confidence: Float
}

struct Note {
    var id: UUID
    var sermonId: UUID
    var text: String
    var timestamp: TimeInterval
    var lastModified: Date
    var isHighlighted: Bool
    var isBookmarked: Bool
}

struct Summary {
    var id: UUID
    var sermonId: UUID
    var text: String
    var format: SummaryFormat
    var createdAt: Date
    var retryCount: Int
}

enum ServiceType: String, Codable {
    case sundayService
    case bibleStudy
    case midweek
    case conference
    case guestSpeaker
    case other
}

enum TranscriptionStatus: String, Codable {
    case notStarted
    case inProgress
    case completed
    case failed
}

enum SummaryStatus: String, Codable {
    case notStarted
    case queued
    case inProgress
    case completed
    case failed
}

enum SyncStatus: String, Codable {
    case notSynced
    case syncing
    case synced
    case failed
}

enum SummaryFormat: String, Codable {
    case devotional
    case bulletPoint
    case theological
}
```

### 2. Recording & Transcription Module

#### Tasks:

1. **Setup Audio Recording**
   - Implement `RecordingService` using AVFoundation
   - Configure audio session for background recording
   - Implement audio interruption handling
   - Save recordings as `.m4a` files in app's documents directory

2. **Implement On-Device Transcription**
   - Create `SpeechRecognitionService` using SFSpeechRecognizer
   - Implement session management for handling ~1 minute recognition limits
   - Add authorization request for speech recognition
   - Create real-time transcription display

3. **Build Recording UI**
   - Create recording controls (start, pause, resume, stop)
   - Implement audio waveform visualization
   - Add recording status indicators
   - Build service type selection modal

```swift
// Sample implementation for SpeechRecognitionService

class SpeechRecognitionService: ObservableObject {
    private let speechRecognizer: SFSpeechRecognizer
    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognitionSubject = PassthroughSubject<TranscriptionUpdate, Error>()
    private var sessionRestartTimer: Timer?
    
    @Published var isRecording = false
    @Published var transcriptionText = ""
    @Published var segments: [TranscriptionSegment] = []
    
    // Session management to handle iOS ~1 minute recognition limits
    private func setupSessionManagement() {
        // Reset recognition task every 50 seconds to avoid timeout
        sessionRestartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            self.restartRecognitionSession()
        }
    }
    
    private func restartRecognitionSession() {
        // Save current state
        let currentText = transcriptionText
        
        // End current session
        recognitionTask?.finish()
        
        // Start new session
        startRecognition()
        
        // Restore state
        transcriptionText = currentText
    }
    
    // Implementation for starting recognition
    func startRecognition() {
        // Implementation details...
    }
}
```

### 3. Note-Taking Module

#### Tasks:

1. **Create Note Editor**
   - Build note editor view with real-time editing
   - Implement auto-save functionality
   - Add timestamp linking to recording position

2. **Implement Note Features**
   - Add highlighting functionality
   - Add bookmarking functionality
   - Create floating action buttons for quick actions

3. **Build Timeline Integration**
   - Link notes to transcription timeline
   - Implement timestamp navigation
   - Create combined view of notes and transcription

```swift
// Sample implementation for NoteEditorViewModel

class NoteEditorViewModel: ObservableObject {
    @Published var noteText: String = ""
    @Published var isHighlighted: Bool = false
    @Published var isBookmarked: Bool = false
    @Published var currentTimestamp: TimeInterval = 0
    
    private let sermonId: UUID
    private let storageService: StorageServiceProtocol
    private var timer: Timer?
    
    init(sermonId: UUID, storageService: StorageServiceProtocol) {
        self.sermonId = sermonId
        self.storageService = storageService
        
        // Setup auto-save
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.saveNote()
        }
    }
    
    func updateTimestamp(_ timestamp: TimeInterval) {
        currentTimestamp = timestamp
    }
    
    func saveNote() {
        let note = Note(
            id: UUID(),
            sermonId: sermonId,
            text: noteText,
            timestamp: currentTimestamp,
            lastModified: Date(),
            isHighlighted: isHighlighted,
            isBookmarked: isBookmarked
        )
        
        storageService.saveNote(note)
    }
}
```

### 4. Local Storage Module

#### Tasks:

1. **Implement Local Storage Service**
   - Create `StorageService` for local data persistence
   - Implement CRUD operations for sermons, transcriptions, and notes
   - Add data migration support

2. **Setup Audio File Management**
   - Implement audio file saving and loading
   - Add cleanup for old recordings (free tier: 30 days)
   - Implement storage space management

3. **Create User Preferences Storage**
   - Store user settings and preferences
   - Save authentication state
   - Manage subscription status

```swift
// Sample implementation for StorageService

class StorageService: StorageServiceProtocol {
    private let container: NSPersistentContainer
    
    init() {
        container = NSPersistentContainer(name: "TabletNotes")
        container.loadPersistentStores { description, error in
            if let error = error {
                print("Failed to load Core Data stack: \(error)")
            }
        }
    }
    
    func saveSermon(_ sermon: Sermon) {
        let context = container.viewContext
        let sermonEntity = SermonEntity(context: context)
        
        // Map Sermon to SermonEntity
        sermonEntity.id = sermon.id
        sermonEntity.title = sermon.title
        sermonEntity.recordingDate = sermon.recordingDate
        // ... other properties
        
        do {
            try context.save()
        } catch {
            print("Failed to save sermon: \(error)")
        }
    }
    
    // Implementation for other CRUD operations...
}
```

### 5. Supabase Integration

#### Tasks:

1. **Setup Supabase Client**
   - Initialize Supabase client
   - Configure API endpoints
   - Implement error handling and retry logic

2. **Implement Authentication**
   - Create sign-up and login flows
   - Add password reset functionality
   - Implement token refresh and session management

3. **Build Sync Manager**
   - Create bidirectional sync for notes and transcriptions
   - Implement conflict resolution
   - Add background sync capabilities
   - Create sync status indicators

```swift
// Sample implementation for SupabaseService

class SupabaseService {
    private let supabaseClient: SupabaseClient
    
    init() {
        supabaseClient = SupabaseClient(
            supabaseURL: URL(string: "YOUR_SUPABASE_URL")!,
            supabaseKey: "YOUR_SUPABASE_KEY"
        )
    }
    
    func signUp(email: String, password: String) async throws -> User {
        let response = try await supabaseClient.auth.signUp(
            email: email,
            password: password
        )
        return response.user
    }
    
    func signIn(email: String, password: String) async throws -> Session {
        let response = try await supabaseClient.auth.signIn(
            email: email,
            password: password
        )
        return response.session
    }
    
    func syncSermon(_ sermon: Sermon) async throws {
        try await supabaseClient
            .from("sermons")
            .upsert(sermon)
            .execute()
    }
    
    // Implementation for other sync operations...
}
```

### 6. AI Summarization

#### Tasks:

1. **Create Summarization Service**
   - Implement OpenAI API integration
   - Create summary generation logic
   - Add support for different summary formats

2. **Build Job Queue System**
   - Implement job queue for summary generation
   - Add automatic retry logic (3 attempts with exponential backoff)
   - Create job status tracking

3. **Implement Edge Functions**
   - Create Supabase Edge Function for summarization
   - Add webhook for summary completion
   - Implement error handling and logging

```swift
// Sample implementation for SummarizationService

class SummarizationService {
    private let supabaseService: SupabaseService
    
    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
    }
    
    func queueSummaryJob(sermonId: UUID, format: SummaryFormat) async throws {
        // Get transcription
        let transcription = try await supabaseService.getTranscription(sermonId: sermonId)
        
        // Queue job in Supabase
        try await supabaseService.functions.invoke(
            functionName: "generate-summary",
            invokeOptions: .init(
                body: [
                    "sermon_id": sermonId.uuidString,
                    "transcription": transcription.text,
                    "format": format.rawValue
                ]
            )
        )
    }
    
    func getSummaryStatus(sermonId: UUID) async throws -> SummaryStatus {
        let response = try await supabaseService
            .from("summaries")
            .select()
            .eq("sermon_id", value: sermonId.uuidString)
            .single()
            .execute()
        
        guard let summary = try? response.decoded(as: Summary.self) else {
            return .notStarted
        }
        
        return SummaryStatus(rawValue: summary.status) ?? .notStarted
    }
}
```

### 7. Email Notification System

#### Tasks:

1. **Setup Email Service**
   - Integrate with Resend API
   - Create email templates
   - Implement email sending logic

2. **Build Notification Triggers**
   - Create webhook for summary completion
   - Implement notification service
   - Add deep linking to app

```javascript
// Sample Edge Function for email notification

// supabase/functions/notify-summary-complete/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { Resend } from 'https://esm.sh/resend@0.15.0'

const resend = new Resend(Deno.env.get('RESEND_API_KEY'))

serve(async (req) => {
  const { sermon_id, user_email, sermon_title } = await req.json()
  
  try {
    await resend.emails.send({
      from: 'TabletNotes <notifications@tabletnotes.app>',
      to: user_email,
      subject: `Your sermon summary for "${sermon_title}" is ready`,
      html: `
        <h1>Your sermon summary is ready!</h1>
        <p>Your AI-generated summary for "${sermon_title}" is now available in the app.</p>
        <p><a href="tabletnotes://sermon/${sermon_id}">Tap here to view it</a></p>
      `
    })
    
    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { 'Content-Type': 'application/json' },
      status: 500
    })
  }
})
```

### 8. User Interface Implementation

#### Tasks:

1. **Build Main Navigation**
   - Implement tab-based navigation
   - Create sermon list view
   - Build sermon detail view

2. **Create Recording Flow**
   - Implement recording screen
   - Build transcription view
   - Create note-taking interface

3. **Implement Settings & Account**
   - Build settings screen
   - Create account management
   - Implement subscription options

```swift
// Sample implementation for main app structure

@main
struct TabletNotesApp: App {
    @St
(Content truncated due to size limit. Use line ranges to read in chunks)