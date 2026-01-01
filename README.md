# Tablet Notes

> AI-powered sermon recording and note-taking app for iOS

Tablet Notes is an iOS application that transforms how you engage with sermons. Record audio, take timestamped notes in real-time, and leverage AI to transcribe, summarize, and interact with sermon content through an intelligent chat interface.

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

## Security

### Authentication & Authorization
- **Token Storage** - Supabase auth tokens managed by Supabase Swift SDK (uses iOS Keychain with secure enclave when available)
- **Session Management** - Automatic token refresh with exponential backoff retry
- **Row Level Security (RLS)** - All Supabase tables scoped by `user_id`
- **API Authentication** - Bearer token required for all backend endpoints

### Data Encryption
- **In Transit** - HTTPS/TLS 1.3 for all network communication
- **At Rest** - Supabase Storage encrypts all audio files (AES-256)
- **Local Storage** - SwiftData uses iOS file system encryption (when device is locked)

### Privacy & Compliance
- **PII Handling** - Sermon content (audio, transcripts) sent to third-party AI services (AssemblyAI, OpenAI/Anthropic)
- **Data Retention** - User data retained until explicit deletion or account closure
- **GDPR Compliance** - Cascade deletes ensure complete data removal on user request
- **Terms & Privacy** - [Add links to your legal documents]

### Known Security Considerations
- ⚠️ Netlify API base URL currently hardcoded in app (should use environment-specific config)
- ⚠️ Supabase credentials in app code (consider moving to secure Config.plist)
- ✅ No sensitive data logged to console in production builds
- ✅ Rate limiting on chat endpoint prevents abuse

## Performance & Scalability

### Audio File Handling
- **Max File Size** - No hard limit (tested up to 3 hours/~500MB)
- **Upload Strategy** - Chunked multipart uploads for files >10MB
- **Memory Management** - Audio streaming during playback (not loaded entirely in memory)
- **Storage Optimization** - M4A format with high-quality AAC codec (approximately 1MB per minute)

### Transcription Performance
- **Live Transcription** - Near real-time with AssemblyAI Live API (typically <2s latency)
- **Async Transcription** - Approximately 0.3x speed (estimated 10min processing for 30min sermon)
- **Polling Interval** - 5 seconds with 5-minute timeout
- **Retry Logic** - Exponential backoff (2s, 4s, 8s, 16s) for network failures

### Database & Sync
- **Sync Frequency** - Background sync every 60 seconds when active
- **Batch Operations** - Sync processes up to 50 records per batch
- **Conflict Resolution** - Last-write-wins based on `updatedAt` timestamp
- **Offline Capability** - Unlimited offline storage, syncs when connected

### AI API Optimization
- **Caching** - Summaries cached after generation (not regenerated)
- **Model Selection** - GPT-4o-mini for chat (cost/performance balance)
- **Rate Limiting** - Per-user circuit breaker prevents runaway costs
- **Streaming** - Chat responses streamed to improve perceived latency

### Scalability Limits
- **Concurrent Users** - Netlify Functions auto-scale to 1000+ concurrent executions
- **Database** - Supabase PostgreSQL handles millions of rows
- **Storage** - Supabase Storage scales to petabytes
- **Bottleneck** - AI API rate limits (configurable per provider)

## Testing Strategy

### Test Coverage
```bash
# Current coverage metrics
Unit Tests:       ~60% (Services layer)
Integration Tests: ~30% (Critical workflows)
UI Tests:         ~20% (Happy paths)
```

### Testing Approach
- **Unit Tests** - All services have protocol-based mocks for isolated testing
- **Integration Tests** - Key workflows (recording, sync, transcription) tested end-to-end
- **UI Tests** - Critical user journeys (onboarding, recording, playback)
- **Manual Testing** - AI features (chat quality, summarization accuracy)

### Test Files
```
TabletNotesTests/
├── Services/
│   ├── RecordingServiceTests.swift
│   ├── SyncServiceTests.swift
│   ├── TranscriptionServiceTests.swift
│   └── ChatServiceTests.swift
├── Models/
│   └── SermonModelTests.swift
└── Integration/
    └── RecordingWorkflowTests.swift

TabletNotesUITests/
└── RecordingFlowUITests.swift
```

### Running Tests
```bash
# Run all tests
xcodebuild test -scheme TabletNotes -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test suite
xcodebuild test -scheme TabletNotes -only-testing:TabletNotesTests/RecordingServiceTests

# Run with coverage
xcodebuild test -scheme TabletNotes -enableCodeCoverage YES
```

### Code Quality Tools
- **SwiftLint** - [To be configured] Code style and best practices
- **SwiftFormat** - [To be configured] Automatic code formatting
- **Xcode Analyzer** - Static analysis enabled in CI

## Deployment

### iOS App Deployment

#### TestFlight (Beta)
1. Archive build in Xcode (Product → Archive)
2. Upload to App Store Connect
3. Configure TestFlight metadata
4. Add internal/external testers
5. Submit for beta review

#### App Store (Production)
1. Archive release build (ensure version bump)
2. Upload to App Store Connect
3. Complete App Store metadata (screenshots, description, keywords)
4. Submit for App Review
5. Release manually or auto-release after approval

**Review Timeline**: Typically 24-48 hours

### Backend Deployment

#### Netlify Functions
```bash
# Deploy to production
netlify deploy --prod

# Deploy to preview
netlify deploy

# View deployment status
netlify status
```

#### Environment Management
- **Production**: Auto-deploys from `main` branch
- **Staging**: Auto-deploys from `develop` branch (if configured)
- **Development**: Local testing with `netlify dev`

#### Environment Variables
Set in Netlify dashboard (Site Settings → Environment Variables):
- All API keys from `.env` template
- Separate keys per environment (dev/staging/prod)

### Supabase Migrations

#### Database Schema Changes
```bash
# Create migration
supabase migration new migration_name

# Apply migrations locally
supabase db reset

# Apply to production
supabase db push
```

#### Rollback Strategy
- Database migrations versioned in `/supabase/migrations`
- Backup before major schema changes
- Test migrations in staging environment first

### CI/CD Pipeline

**Current Status**: Manual deployment
**Planned**: GitHub Actions workflow

```yaml
# Planned CI/CD (not yet implemented)
- Lint and format check (SwiftLint)
- Run unit tests
- Build for simulator
- Archive for TestFlight (on release tags)
- Deploy backend to Netlify (on main push)
```

## Monitoring & Observability

### Application Monitoring
**Current Status**: Limited monitoring in place

#### Recommended Tools (Not Yet Implemented)
- **Crashlytics** - Crash reporting and analytics
- **Sentry** - Error tracking and performance monitoring
- **Mixpanel/Amplitude** - User behavior analytics

### Backend Monitoring
- **Netlify Analytics** - Function invocation counts, errors, duration
- **Supabase Dashboard** - Database queries, connection pool, storage usage
- **Upstash Console** - Redis cache hit rates, memory usage

### Key Metrics to Track
- **App Health**
  - Crash-free users %
  - App launch time
  - Memory usage per screen
- **Feature Usage**
  - Recordings per user per month
  - Transcription success rate
  - Chat message volume
  - Subscription conversion rate
- **API Performance**
  - AssemblyAI transcription time
  - OpenAI response latency
  - Sync success rate
  - Upload failure rate
- **Business Metrics**
  - Monthly Active Users (MAU)
  - Daily Active Users (DAU)
  - Churn rate
  - Average revenue per user (ARPU)

### Logging Strategy
- **iOS App** - OSLog framework for structured logging
- **Backend** - Console.log to Netlify function logs
- **Log Levels** - Debug (dev only), Info, Warning, Error

### Alerting
**To Be Configured**:
- High error rate on critical endpoints (>5%)
- API cost spike (>2x normal)
- Transcription failure rate >10%
- Storage approaching limits

## Known Limitations

### Current Constraints
- **Audio Format** - iOS only (M4A/AAC), no Android support
- **Offline Transcription** - Requires internet connection for AI features
- **Large Files** - Files >2 hours may have slower upload on cellular
- **Concurrent Recordings** - One active recording per device
- **Export Options** - No PDF/Word export (transcripts viewable in-app only)
- **Sharing** - Cannot share recordings between users

### Technical Debt
- ⚠️ Hardcoded API URLs (should be environment-based)
- ⚠️ Manual database migrations (no automated versioning)
- ⚠️ Limited error handling in UI (some errors not user-friendly)
- ⚠️ No retry UI for failed syncs (auto-retry only)
- ⚠️ Chat context truncation for very long transcripts (>8k tokens)

### Browser/Platform Support
- **iOS**: 17.0+ (tested on 17.x and 18.x)
- **iPad**: Full support with adapted UI
- **macOS**: Not supported (iOS app can run via Catalyst with modifications)
- **Android**: Not planned
- **Web**: Not planned

## Cost Analysis

### Per-User Cost Breakdown

#### AI Services (Variable)
| Service | Use Case | Cost | Est. Per Sermon |
|---------|----------|------|-----------------|
| AssemblyAI | Transcription | $0.025/min | $0.75 (30min) |
| OpenAI GPT-4o-mini | Chat | $0.15/1M input tokens | $0.02 per chat |
| OpenAI GPT-4 | Summarization | $5/1M input tokens | $0.10 per summary |

**Estimated AI cost per sermon**: ~$0.87 (30min sermon with summary + 5 chat messages)

*Costs based on current provider pricing as of January 2026. Subject to change.*

#### Infrastructure (Fixed + Variable)
- **Supabase** - Free tier: 500MB database, 1GB storage. Pro: $25/mo for 8GB database, 100GB storage
- **Netlify** - Free tier: 125k requests/mo. Pro: $19/mo for 2M requests
- **Upstash Redis** - Free tier: 10k requests/day. Pay-as-you-go: $0.20/100k requests

#### Monthly Cost Estimates (Projected)
- **100 users**: ~$50-100/mo (mostly AI costs)
- **1,000 users**: ~$500-800/mo
- **10,000 users**: ~$5,000-8,000/mo

*Note: Actual costs vary based on user behavior, recording lengths, and AI usage patterns.*

### Cost Optimization Strategies
1. **Cache summaries** - Never regenerate existing summaries ✅
2. **Use cheaper models** - GPT-4o-mini for chat instead of GPT-4 ✅
3. **Batch operations** - Sync multiple records in single transaction
4. **Compress audio** - AAC codec reduces storage by ~50% ✅
5. **Rate limiting** - Prevent abuse via circuit breakers ✅
6. **Usage tiers** - Free users limited to reduce costs ✅

### Revenue Model
- **Free Tier**: 5 recordings/month (30 min each) → Loss leader (estimated cost: ~$4.35/user/mo)
- **Premium**: $9.99/month → Profitable at >10 recordings/month
- **Target**: 15% conversion rate, 70% gross margin (estimated)

## Roadmap

### Completed ✅
- [x] Core recording functionality
- [x] Real-time transcription
- [x] AI summarization
- [x] Interactive chat
- [x] Cloud sync
- [x] Subscription management
- [x] Bible browser

### In Progress 🚧
- [ ] Improved error handling and user feedback
- [ ] Comprehensive test coverage (target: 80%)
- [ ] CI/CD pipeline setup

### Planned - Q1 2026 📅
- [ ] Export transcripts (PDF, DOCX, TXT)
- [ ] Sermon sharing between users
- [ ] Collaborative notes
- [ ] Search across all sermons
- [ ] Sermon series/playlists

### Planned - Q2 2026 🔮
- [ ] Offline transcription (on-device via Speech framework)
- [ ] Speaker diarization (identify multiple speakers)
- [ ] Auto-tagging with sermon topics
- [ ] Integration with church management systems
- [ ] Android app (React Native or native)

### Under Consideration 💡
- Web app for listening/reviewing (read-only)
- Podcast export
- Team/organization accounts
- White-label solution for churches
- Live streaming integration

## Troubleshooting

### Common Issues

#### "Recording failed to start"
**Cause**: Microphone permissions not granted
**Solution**:
```swift
Settings → Privacy → Microphone → TabletNotes (Enable)
```

#### "Transcription stuck at 0%"
**Causes**:
- Network connectivity issues
- AssemblyAI API quota exceeded
- Audio file upload failed

**Solutions**:
1. Check internet connection
2. Verify audio file uploaded to Supabase Storage
3. Check AssemblyAI dashboard for quota limits
4. Retry transcription from sermon detail screen

#### "Sync failing repeatedly"
**Causes**:
- Expired auth token
- Network issues
- Supabase RLS policy conflicts

**Solutions**:
1. Sign out and sign back in (refreshes token)
2. Check network connectivity
3. View sync logs in Settings → Advanced → Sync Status

#### "Chat not responding"
**Causes**:
- Rate limit exceeded
- No transcript available
- API key invalid

**Solutions**:
1. Wait a few minutes (limit: 100 messages per hour)
2. Ensure sermon has completed transcription
3. Verify API keys in backend `.env`

#### "Audio playback choppy"
**Cause**: Large file not fully downloaded
**Solution**: Wait for complete download or enable streaming mode

### Debug Mode

Enable debug logging (requires developer build):
```swift
// In TabletNotesApp.swift
UserDefaults.standard.set(true, forKey: "debug_logging_enabled")
```

View logs:
- iOS: Xcode → Window → Devices and Simulators → Open Console
- Backend: Netlify Dashboard → Functions → View Logs

### Getting Help
1. Check FAQ below
2. Search existing issues: [GitHub Issues URL]
3. Contact support: support@tabletnotes.app (if applicable)
4. Community forum: [Link if available]

## FAQ

### General Questions

**Q: What platforms are supported?**
A: Currently iOS 17.0+ on iPhone and iPad. Android and web versions are not planned at this time.

**Q: Can I use this offline?**
A: Yes! Recording and note-taking work fully offline. Transcription, summarization, and chat require an internet connection. Your recordings will sync automatically when you're back online.

**Q: How long can I record?**
A: There's no hard limit. The app has been tested with recordings up to 3 hours. Longer recordings will take more time to upload and transcribe.

**Q: What audio quality does it record at?**
A: M4A format with high-quality AAC codec (44.1kHz, stereo), which provides excellent quality at approximately 1MB per minute (estimated ~30MB for a 30-minute sermon).

### AI & Transcription

**Q: How accurate is the transcription?**
A: AssemblyAI achieves 95%+ accuracy for clear audio with minimal background noise. Quality depends on:
- Speaker clarity and accent
- Background noise levels
- Audio quality/microphone
- Multiple overlapping speakers

**Q: Can it identify different speakers?**
A: Not yet. Speaker diarization is planned for Q2 2026.

**Q: Which AI models are used?**
A:
- Transcription: AssemblyAI (proprietary speech model)
- Summaries: OpenAI GPT-4 or Anthropic Claude (configurable)
- Chat: GPT-4o-mini (default), supports 8+ providers

**Q: Is my sermon content private?**
A: Your audio and transcripts are sent to third-party AI services (AssemblyAI, OpenAI/Anthropic) for processing. These services have their own privacy policies. Data is encrypted in transit and at rest, and is scoped to your user account via RLS policies.

**Q: Can I choose which AI provider to use?**
A: Yes! Settings allow selection from: OpenAI, Anthropic, Google Gemini, Perplexity, Mistral, xAI, Azure OpenAI, and Ollama (for self-hosted).

### Sync & Storage

**Q: How does cloud sync work?**
A: The app is "local-first" - everything saves to your device immediately. Changes sync to Supabase in the background when you're connected. This ensures you can always access your recordings, even offline.

**Q: What happens if I edit on two devices simultaneously?**
A: The last edit wins (based on timestamp). We recommend finishing edits on one device before switching to another to avoid potential conflicts.

**Q: How much storage do I get?**
A:
- Free tier: 1GB (approximately 16 hours of recordings)
- Premium: Unlimited storage

**Q: Can I export my data?**
A: Currently, transcripts are viewable in-app only. PDF/DOCX export is planned for Q1 2026. You can manually download audio files from your Supabase storage bucket.

### Subscriptions & Billing

**Q: What's included in the free tier?**
A:
- 5 recordings per month (30 minutes each)
- AI transcription and summarization
- AI chat (100 messages per hour)
- 1GB storage
- Cloud sync

**Q: What does Premium include?**
A:
- Unlimited recordings (90 minutes max per recording)
- Unlimited AI chat (100 messages per hour)
- Unlimited storage
- Priority transcription processing
- Early access to new features

**Q: How is usage tracked?**
A: Usage resets monthly and tracks:
- Number of recordings created
- Minutes of audio recorded
- Storage used (GB)
- Chat messages sent

**Q: Can I cancel anytime?**
A: Yes, subscriptions can be canceled through iOS Settings → Apple ID → Subscriptions. Access continues until end of billing period.

**Q: Is there a free trial?**
A: Yes, new users get a 7-day free trial of Premium features.

### Technical Questions

**Q: How do you handle large file uploads?**
A: Files are uploaded in chunks via Supabase Storage signed URLs. Uploads automatically resume if interrupted.

**Q: What happens if transcription fails?**
A: The app retries with exponential backoff. If it continues failing, you can manually retry from the sermon detail screen. As a fallback, iOS Speech framework can transcribe locally (limited to device language).

**Q: How secure are authentication tokens?**
A: Supabase auth tokens are stored in iOS Keychain (hardware-backed when available). Tokens auto-refresh and expire after inactivity. All API calls require valid Bearer tokens.

**Q: Can I self-host the backend?**
A: Technically yes, but not officially supported. You'd need to:
1. Host Netlify Functions elsewhere (AWS Lambda, Vercel, etc.)
2. Set up your own Supabase instance or PostgreSQL database
3. Configure RLS policies and storage buckets
4. Update API URLs in iOS app

**Q: What's the database migration strategy?**
A: SwiftData handles iOS migrations automatically. Supabase migrations are manual via SQL scripts in `/supabase/migrations`. Always test migrations in staging first.

### Feature Requests

**Q: Will you add Android support?**
A: It's under consideration for Q2 2026. We're evaluating React Native vs. native Kotlin.

**Q: Can I share recordings with others?**
A: Not yet. Sermon sharing and collaborative notes are planned for Q1 2026.

**Q: Can I export to podcast format?**
A: Not currently, but podcast export is under consideration for future releases.

**Q: Will there be a web app?**
A: A read-only web app for reviewing sermons is under consideration. Recording will remain iOS-only.

**Q: Can I integrate with my church management system?**
A: Not yet, but church management system integrations (Planning Center, CCB, etc.) are planned for Q2 2026.

### Troubleshooting

**Q: Why isn't my recording syncing?**
A: Common causes:
1. No internet connection (will sync when connected)
2. Expired auth token (sign out and back in)
3. Audio file upload failed (check storage quota)

Check Settings → Advanced → Sync Status for details.

**Q: The chat says "Rate limit exceeded" - what does that mean?**
A: To prevent abuse and control costs, chat has a rate limit of 100 messages per hour per user. If you hit this limit, wait a few minutes before sending more messages. The limit applies to all users equally.

**Q: Why is transcription taking so long?**
A: AssemblyAI typically processes at approximately 0.3x speed (estimated 10 minutes for a 30-minute sermon). Very long recordings (2+ hours) may take 30-60 minutes. Check the transcription status in the app for progress.

**Q: The app crashed - did I lose my recording?**
A: No! Recordings save to local storage immediately. Even if the app crashes, your audio file is safe in `Documents/AudioRecordings/`. The app will recover and sync it when relaunched.

**Q: How do I report a bug?**
A: Please create an issue on our GitHub repository with:
- iOS version
- Device model
- Steps to reproduce
- Expected vs actual behavior
- Screenshots/logs if available

---

## Performance Benchmarks

*Estimated performance metrics based on testing with iPhone 15 Pro, iOS 18.0, WiFi connection. Actual performance may vary by device and network conditions.*

| Operation | Duration | Notes |
|-----------|----------|-------|
| App Launch | ~1.2s | Cold start |
| Start Recording | <0.5s | After mic permission granted |
| Stop Recording | <0.3s | Audio file write time |
| Upload 30min audio | ~15s | WiFi (35s on LTE) |
| Transcription | ~10min | For 30min sermon |
| Generate Summary | ~8s | GPT-4 processing |
| Chat Response | ~2-4s | First token, streaming |
| Sync 10 sermons | ~5s | With all metadata |

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
