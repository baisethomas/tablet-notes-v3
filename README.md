# TabletNotes

> AI-powered sermon recording and note-taking app for iOS

TabletNotes is an iOS application that transforms how you engage with sermons. Record audio, take timestamped notes in real-time, and leverage AI to transcribe, summarize, and interact with sermon content through an intelligent chat interface.

## Features

- **Audio Recording** - Record sermons with pause/resume support and real-time duration tracking
- **Timestamped Notes** - Take notes during recording with automatic timestamp linking to audio playback
- **AI Transcription** - Automatic transcription powered by AssemblyAI (both live during recording and post-recording)
- **AI Summaries** - Generate intelligent summaries using OpenAI GPT-4 or Claude
- **Interactive Chat** - Ask questions about sermon content with context-aware AI responses
- **Bible Browser** - Built-in Scripture search and reading functionality
- **Cloud Sync** - Bi-directional sync across devices via Supabase
- **Offline-First** - Full functionality offline with automatic sync when connected
- **Multi-AI Support** - Choose from 8+ AI providers (OpenAI, Anthropic, Google Gemini, Perplexity, Mistral, xAI, Azure, Ollama)
- **Subscription Management** - Freemium model with trial periods and usage-based limits

## Tech Stack

### iOS App
- **SwiftUI** - Modern declarative UI framework
- **SwiftData** - Local persistence layer
- **Combine** - Reactive programming
- **AVFoundation** - Audio recording and playback
- **StoreKit 2** - In-app purchases and subscriptions
- **Supabase Swift SDK** - Cloud database and authentication

### Backend (Serverless)
- **Netlify Functions** - Serverless API endpoints
- **Supabase** - PostgreSQL database, authentication, and file storage
- **AssemblyAI** - Speech-to-text transcription
- **OpenAI/Anthropic** - Chat and summarization
- **Upstash Redis** - Rate limiting and caching

## Architecture

TabletNotes follows a **local-first architecture** with cloud sync:

- **MVVM Pattern** - Clear separation between views and business logic
- **Protocol-Based Services** - Testable, swappable service layer
- **Dependency Injection** - Services injected through view hierarchy
- **Repository Pattern** - Services abstract data access (SwiftData local, Supabase remote)
- **Bi-directional Sync** - Conflict resolution via timestamps

### Data Flow

```
Recording → Transcription → Summarization → Interactive Chat
    ↓           ↓               ↓                ↓
SwiftData → SwiftData → SwiftData → SwiftData (local-first)
    ↓           ↓               ↓                ↓
Supabase ← Supabase ← Supabase ← Supabase (background sync)
```

## Project Structure

```
tablet-notes-v3/
├── TabletNotes/                      # iOS Application
│   ├── App/                          # App entry point
│   │   └── TabletNotesApp.swift      # Main app initialization
│   ├── Models/                       # SwiftData models (7 models)
│   │   ├── Sermon.swift              # Core recording entity
│   │   ├── Transcript.swift          # AI transcription data
│   │   ├── Note.swift                # Timestamped user notes
│   │   ├── Summary.swift             # AI-generated summaries
│   │   └── ChatMessage.swift         # AI chat history
│   ├── Views/                        # SwiftUI screens (~12k lines)
│   │   ├── MainAppView.swift         # Navigation coordinator
│   │   ├── Recording/                # Recording interface
│   │   ├── SermonDetail/             # Sermon playback & details
│   │   ├── Chat/                     # AI chat interface
│   │   └── Settings/                 # App settings
│   ├── Services/                     # Business logic (~9k lines)
│   │   ├── RecordingService.swift    # Audio recording
│   │   ├── TranscriptionService.swift # AI transcription
│   │   ├── SermonService.swift       # Sermon CRUD operations
│   │   ├── SyncService.swift         # Cloud synchronization
│   │   ├── ChatService.swift         # AI chat functionality
│   │   ├── AuthenticationManager.swift # User authentication
│   │   └── SubscriptionService.swift # In-app purchases
│   └── Utils/                        # Helper utilities
│
├── tablet-notes-api/                 # Serverless Backend
│   └── netlify/functions/            # 15 API endpoints
│       ├── transcribe.js             # Start transcription
│       ├── transcribe-status.js      # Poll transcription status
│       ├── summarize.js              # Generate AI summary
│       ├── chat.js                   # AI chat endpoint
│       ├── create-sermon.js          # Create sermon record
│       └── generate-upload-url.js    # Signed URL for audio upload
│
└── Documentation/                    # Setup guides and schemas
```

## Core Services

| Service | Responsibility |
|---------|---------------|
| **RecordingService** | Manages AVAudioRecorder, handles pause/resume, file management |
| **TranscriptionService** | Coordinates AssemblyAI transcription (live & async) |
| **SermonService** | CRUD operations, filtering, archiving, usage limits |
| **SyncService** | Bi-directional sync with conflict resolution |
| **ChatService** | AI chat with sermon context formatting and usage tracking |
| **AuthenticationManager** | Sign in/up, session management, token refresh |
| **SubscriptionService** | StoreKit 2 integration, subscription status |
| **SupabaseService** | API client, token management, file uploads |

## API Endpoints

All endpoints require Supabase authentication token (Bearer).

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/create-sermon` | POST | Create new sermon record |
| `/get-sermons` | GET | Fetch user's sermons |
| `/update-sermon` | POST | Update sermon metadata |
| `/delete-sermon` | DELETE | Delete sermon and associated data |
| `/generate-upload-url` | POST | Get signed URL for audio upload |
| `/transcribe` | POST | Start AssemblyAI transcription |
| `/transcribe-status` | GET | Poll transcription progress |
| `/summarize` | POST | Generate AI summary |
| `/chat` | POST | AI chat with sermon context |
| `/bible-api` | GET | Fetch Bible verses |
| `/assemblyai-live-token` | GET | Token for live transcription |

## Data Models

### Sermon
Main entity representing a recording session.

```swift
- id: UUID
- title: String
- date: Date
- duration: TimeInterval
- audioFileURL: String?
- remoteAudioURL: String?
- notes: [Note]
- transcript: Transcript?
- summary: Summary?
- chatMessages: [ChatMessage]
```

### Sync Metadata
Each model includes sync tracking:
- `remoteId` - Supabase record ID
- `lastSyncedAt` - Last successful sync timestamp
- `needsSync` - Flag for pending changes
- `syncStatus` - Current sync state

## Configuration

### Required Environment Variables

Create a `.env` file in `tablet-notes-api/`:

```bash
# AI Services
ASSEMBLYAI_API_KEY=your_assemblyai_key
OPENAI_API_KEY=your_openai_key
ANTHROPIC_API_KEY=your_anthropic_key

# Supabase
SUPABASE_URL=your_supabase_project_url
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key

# Optional AI Providers
PERPLEXITY_API_KEY=your_perplexity_key
GOOGLE_API_KEY=your_google_key
MISTRAL_API_KEY=your_mistral_key
XAI_API_KEY=your_xai_key
```

### iOS App Configuration

Update hardcoded values in appropriate config files:
- Netlify API base URL (currently hardcoded)
- Supabase credentials (should move to Config.plist)

## Getting Started

### Prerequisites
- Xcode 15+ (for iOS development)
- Node.js 18+ (for Netlify Functions)
- Supabase account
- API keys for AI services

### iOS App Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd tablet-notes-v3
```

2. Open the Xcode project:
```bash
open TabletNotes/TabletNotes.xcodeproj
```

3. Configure signing & capabilities in Xcode

4. Build and run on simulator or device

### Backend Setup

1. Install dependencies:
```bash
cd tablet-notes-api
npm install
```

2. Set up environment variables (see Configuration above)

3. Deploy to Netlify:
```bash
netlify deploy --prod
```

4. Set up Supabase:
   - Create database tables (see `Documentation/` for schema)
   - Configure Row Level Security (RLS) policies
   - Create storage bucket for audio files

## Development

### Running Tests

```bash
# Unit tests
xcodebuild test -scheme TabletNotes -destination 'platform=iOS Simulator,name=iPhone 15'

# UI tests
xcodebuild test -scheme TabletNotesUITests -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Key Architectural Decisions

1. **SwiftData over Core Data** - Simpler model definitions, automatic persistence
2. **Protocol-based services** - Enables easier testing and mock implementations
3. **Local-first design** - Users can work offline, sync happens in background
4. **Serverless backend** - Reduces operational overhead
5. **Multi-AI provider support** - Flexibility and fallback options
6. **Usage-based limits** - Fair subscription model tied to actual resource consumption

### Sync Strategy

- **Immediate local writes** - All operations write to SwiftData first
- **Background sync** - SyncService syncs to Supabase when connected
- **Conflict resolution** - Uses `updatedAt` timestamps (last-write-wins)
- **Retry logic** - Exponential backoff for failed operations
- **RLS policies** - User-scoped security at database level

## Database Schema

### Tables
- `sermons` - Main recordings table
- `transcripts` - AI transcription data
- `transcript_segments` - Word-level timestamped segments
- `summaries` - AI-generated summaries
- `notes` - User notes with timestamps
- `chat_messages` - AI chat history

### Storage
- `sermon-audio` bucket - Audio files with RLS protection

See `Documentation/` for complete schema definitions.

## Subscription Model

### Free Tier
- Limited recordings per month
- Basic transcription
- Limited AI chat messages

### Premium Tier
- Unlimited recordings
- Advanced AI features
- Priority processing
- Extended storage

Usage tracking per user:
- Recording count
- Minutes recorded
- Storage used (GB)
- Chat messages sent

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

[Add your license information here]

## Acknowledgments

- AssemblyAI for transcription services
- OpenAI/Anthropic for AI capabilities
- Supabase for backend infrastructure
- The SwiftUI community

---

**Note:** This is an active development project. Some features may be in progress or require additional configuration.
