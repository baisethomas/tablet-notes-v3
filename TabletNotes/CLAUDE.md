# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Skills & Best Practices

**Always consult the relevant Swift skill before implementing new features or refactoring existing code.**

- **swiftui-patterns** — Use for any `@Observable`, `@Bindable`, `NavigationStack`, or iOS 17+ pattern work
- **swiftui-expert-skill** — Use for view composition, performance optimization, and state management decisions
- **swift-networking** — Use for any `Network.framework`, `NWConnection`, connectivity handling, or network transition work

These skills are installed globally and available in every session. Reference them when writing new services, migrating patterns, or reviewing code for best practices.

## Project Overview

Tablet Notes is an iOS app built with SwiftUI that allows users to record sermons, take notes during recording, and get AI-powered transcription and summaries. The app uses a Netlify backend for API functions and Supabase for data persistence.

## Development Commands

### Building and Running
- Build and run the app: Use Xcode to build and run the TabletNotes target
- The app targets iOS devices and supports SwiftData for local data management
- No package managers (CocoaPods, SPM CLI) are used — dependencies are managed through Xcode's Swift Package Manager integration

### Testing
- Run unit tests: Use Xcode's Test Navigator or Product > Test menu
- Test targets: `TabletNotesTests` and `TabletNotesUITests`
- Tests can be run individually or as a suite through Xcode

### Dependencies
The project uses Swift Package Manager with the following key dependencies:
- **Supabase Swift SDK** (v2.29.3): Database and authentication
- **Swift Crypto**: Cryptographic operations
- **Swift HTTP Types**: HTTP networking utilities

## Architecture

### Core Architecture Pattern
- **MVVM with Services**: Model-View-ViewModel pattern using SwiftUI and `@Observable` (iOS 17+ Swift Observation framework)
- **Coordinator Pattern**: `AppCoordinator` manages navigation between screens
- **Service Layer**: Protocol-based services for different features (Auth, Recording, Transcription, etc.)
- **Repository Pattern**: Services abstract data access from ViewModels

### Key Components

#### Models (SwiftData)
- `Sermon`: Main entity with audio file, notes, transcript, summary, and chat message relationships. Includes `@Transient` cached file existence checks.
- `Note`: User-written notes during recording
- `Transcript`: AI-generated transcription with segments
- `Summary`: AI-generated summary of the sermon
- All models use `@Model` annotation for SwiftData persistence

#### Services

**Core services using `@Observable`:**
- **SermonService**: CRUD operations for sermons using SwiftData
- **ChatService**: AI chat interactions for sermon Q&A
- **AuthenticationManager**: Auth state management with backward-compatible Combine publisher
- **RecordingService**: Audio recording with duration limits and subscription enforcement

**Network resilience services:**
- **NetworkMonitor**: Real-time connectivity tracking via `NWPathMonitor` (WiFi/cellular/unknown states)
- **NetworkRetry**: Exponential backoff retry logic for all API calls

**Other services (ObservableObject — migration candidates):**
- **SupabaseService**: File uploads and API communication with Netlify backend
- **TranscriptionService**: Manages AssemblyAI integration for transcription
- **AssemblyAILiveTranscriptionService**: WebSocket-based live transcription (`@Observable`, auto-reconnects on network restore)
- **SummaryService**: AI-powered summarization
- **SyncService**: Background sync with Supabase
- **SettingsService**: User preferences via UserDefaults

**Utilities:**
- **MarkdownCleaner**: Pre-compiled regex patterns for efficient markdown-to-plain-text conversion

#### Views and Navigation
- **AppCoordinator**: Central navigation coordinator with screen enumeration
- **Screen-based navigation**: Each major screen uses `@ViewBuilder` for type-safe routing (no `AnyView`)
- **Service injection**: Services are passed down through the view hierarchy

### Observation Patterns (iOS 17+)

The app uses the Swift Observation framework (`@Observable`) for core services. Follow these rules:

| Context | Property Wrapper | Example |
|---------|-----------------|---------|
| View owns the instance | `@State` | `@State private var sermonService = SermonService()` |
| View receives instance & needs bindings | `@Bindable` | `@Bindable var sermonService: SermonService` |
| View receives instance, read-only | Plain `var` | `var authManager: AuthenticationManager` |
| Backward Combine compatibility | `@ObservationIgnored @Published` | `@ObservationIgnored @Published var authStatePublished: AuthState` |

**Rules:**
- Never call `objectWillChange.send()` — `@Observable` handles UI updates automatically
- Never use `@StateObject` or `@ObservedObject` with `@Observable` classes — use `@State` or `@Bindable`
- Use `@MainActor` on services that update UI state; omit it for services with synchronous callbacks (e.g., AVFoundation delegates)
- When a service needs both `@Observable` and Combine publishers, use `@ObservationIgnored @Published` for the published property

### Network Resilience

The app handles network transitions (WiFi/cellular switches, phone calls, airplane mode) without crashing:

- **NetworkMonitor** (`Services/NetworkMonitor.swift`): Singleton using `NWPathMonitor` to track connectivity state. Access via `NetworkMonitor.shared.isConnected`.
- **NetworkRetry** (`Services/NetworkRetry.swift`): Use `NetworkRetry.withExponentialBackoff()` for all network requests. Automatically checks connectivity before retrying and classifies retryable vs. non-retryable errors.
- **WebSocket reconnection**: `AssemblyAILiveTranscriptionService` observes `NetworkMonitor` and auto-reconnects when connectivity is restored.
- **URLSession configuration**: All sessions use `waitsForConnectivity = true` with appropriate timeouts.

### Data Flow
1. User interacts with SwiftUI View
2. View calls methods on injected Services
3. Services handle business logic and data operations
4. SwiftData manages local persistence
5. Supabase handles remote sync and file storage
6. Netlify Functions process AI transcription/summarization

## Key Features

### Audio Recording and Notes
- Real-time note-taking during audio recording
- Service type selection (Sunday Service, Bible Study, etc.)
- Audio files stored locally and uploaded to Supabase storage
- Subscription-based recording duration limits with cached enforcement

### AI Processing
- **Transcription**: AssemblyAI integration via Netlify Functions
- **Live Transcription**: WebSocket-based real-time transcription with auto-reconnect
- **Summarization**: AI-powered sermon summaries
- **Chat**: AI Q&A about sermon content
- **Asynchronous processing**: Status tracking for long-running operations

### Data Management
- **Local-first**: SwiftData for immediate data access
- **Sync capabilities**: Background sync with Supabase
- **Status tracking**: Each sermon tracks sync, transcription, and summary status

## Configuration

### API Keys and Configuration
- **AssemblyAI API key**: Stored in `AssemblyAIKey.swift` (not committed to version control)
- **Supabase credentials**: Stored in `Resources/SupabaseConfig.swift`
- **Netlify API base URL**: `https://comfy-daffodil-7ecc55.netlify.app`

### Environment Setup
- Xcode 16+ required
- iOS 17+ target deployment
- Swift 5.9+ with Observation framework
- Swift Concurrency (async/await, @MainActor)

## Development Notes

### Performance Patterns

Follow these established patterns to maintain app performance:

- **No `AnyView`**: Use `@ViewBuilder` functions for type-safe conditional views instead of `AnyView` type erasure
- **No inline sorting in ForEach**: Cache sorted arrays as computed properties on the view, not inside `ForEach` closures
- **Pre-compiled regex**: Use `MarkdownCleaner` for markdown processing. Add new patterns there — never compile `NSRegularExpression` inside view bodies
- **File existence caching**: `Sermon.audioFileExists` uses `@Transient` 5-second cache to reduce disk I/O. Call `invalidateFileExistenceCache()` after creating/deleting audio files
- **Stable ForEach identity**: Use model properties (`.id`, `.title`) as ForEach identifiers — never use array offsets (`\.offset`)
- **`@Observable` over `ObservableObject`**: All new services must use `@Observable`. Only use `ObservableObject` when Combine publisher integration is required

### Service Dependencies
- Services are initialized with their required dependencies (e.g., ModelContext for SwiftData operations)
- Protocol-based design allows for easy mocking and testing
- Dependency injection happens at the coordinator level
- Singleton services (e.g., `NetworkMonitor.shared`, `ChatService.shared`) use `@State` in their owning view

### Data Persistence
- SwiftData is used for local data persistence
- Models use relationships with cascade delete rules
- Sync status tracking enables offline-first functionality

### Error Handling
- Services should handle errors gracefully and update status fields
- UI should reflect processing states (loading, error, success)
- Network errors must use `NetworkRetry.withExponentialBackoff()` for automatic retry
- Check `NetworkMonitor.shared.isConnected` before initiating network-dependent operations

### Testing Strategy
- Unit tests for service layer business logic
- UI tests for critical user flows
- Mock services for testing without network dependencies
