# Tablet Notes App Architecture

## Project Structure

```
TabletNotes/
├── App/
│   └── TabletNotesApp.swift          # Main app entry point with SwiftData setup
│
├── Models/                            # SwiftData @Model classes
│   ├── Sermon.swift                   # Main entity (audio, notes, transcript, summary, chat)
│   ├── Note.swift                     # User-written notes during recording
│   ├── Transcript.swift               # AI-generated transcription with segments
│   ├── Summary.swift                  # AI-generated sermon summary
│   ├── ChatMessage.swift              # AI chat messages for sermon Q&A
│   ├── User.swift                     # User profile and subscription info
│   ├── User+Extensions.swift          # Subscription limit helpers
│   ├── Subscription.swift             # Subscription plan model
│   ├── BibleTranslation.swift         # Bible translation metadata
│   └── SupabaseModels.swift           # DTOs for Supabase API responses
│
├── Services/                          # Service layer (organized by domain)
│   ├── Auth/
│   │   ├── AuthenticationManager.swift    # @Observable — auth state management
│   │   ├── AuthService.swift              # Auth service protocol
│   │   ├── AuthServiceProtocol.swift
│   │   └── SupabaseAuthService.swift      # Supabase auth implementation
│   ├── Recording/
│   │   ├── RecordingService.swift         # @Observable — audio recording + duration limits
│   │   └── RecordingServiceProtocol.swift
│   ├── Chat/
│   │   ├── ChatService.swift              # @Observable — AI sermon Q&A
│   │   └── ChatServiceProtocol.swift
│   ├── Transcription/
│   │   ├── TranscriptionService.swift
│   │   ├── AssemblyAILiveTranscriptionService.swift  # @Observable — WebSocket live transcription
│   │   └── TranscriptionRetryService.swift
│   ├── Summary/
│   │   ├── SummaryService.swift
│   │   └── SummaryRetryService.swift
│   ├── Sync/
│   │   ├── SyncService.swift              # Background sync with Supabase
│   │   └── BackgroundSyncManager.swift
│   ├── Bible/
│   │   ├── BibleAPIService.swift
│   │   ├── DirectBibleAPIService.swift
│   │   └── NetlifyBibleAPIService.swift
│   ├── Subscription/
│   │   ├── SubscriptionService.swift
│   │   └── SubscriptionServiceProtocol.swift
│   ├── Notes/
│   │   ├── NoteService.swift
│   │   └── NoteServiceProtocol.swift
│   ├── Notification/
│   │   ├── NotificationService.swift
│   │   └── NotificationServiceProtocol.swift
│   ├── Analytics/
│   │   ├── AnalyticsService.swift
│   │   └── AnalyticsServiceProtocol.swift
│   ├── NetworkMonitor.swift           # @Observable — NWPathMonitor connectivity tracking
│   ├── NetworkRetry.swift             # Exponential backoff retry logic
│   ├── SermonService.swift            # @Observable — sermon CRUD via SwiftData
│   ├── SettingsService.swift          # User preferences via UserDefaults
│   ├── SupabaseService.swift          # File uploads and Netlify API communication
│   ├── ScriptureAnalysisService.swift # Regex-based scripture reference detection
│   └── DeepLinkHandler.swift          # URL scheme handling
│
├── Views/                             # SwiftUI views
│   ├── MainAppView.swift              # Root view with @ViewBuilder navigation
│   ├── SermonListView.swift           # Sermon list with grouped sections
│   ├── SermonDetailView.swift         # Sermon detail (transcript, notes, summary, audio)
│   ├── RecordingView.swift            # Recording screen with live notes
│   ├── SettingsView.swift             # App settings
│   ├── AccountView.swift              # User account management
│   ├── OnboardingView.swift           # First-launch onboarding
│   ├── SplashView.swift               # Launch screen
│   ├── ContentView.swift              # Legacy content view
│   ├── Authentication/                # Sign in, sign up views
│   ├── Chat/                          # Chat UI (ChatTabView, MessageBubbleView, etc.)
│   ├── Bible/                         # Bible browser
│   ├── Scripture/                     # Scripture text rendering and detail views
│   └── Components/                    # Reusable UI components (BibleFAB, loading states, etc.)
│
├── Utilities/
│   └── MarkdownCleaner.swift          # Pre-compiled regex for markdown processing
│
├── Utils/
│   ├── ColorScheme.swift              # Adaptive color extensions
│   ├── AppVersion.swift               # Version info helpers
│   ├── DataMigration.swift            # SwiftData migration utilities
│   └── MigrationSafety.swift          # Safe migration helpers
│
└── Resources/
    ├── Assets.xcassets/               # Images and color assets
    ├── Config.plist                   # App configuration
    ├── SupabaseConfig.swift           # Supabase project URL and anon key
    ├── AssemblyAIKey.swift            # AssemblyAI API key (not in version control)
    ├── StripeConfig.swift             # Stripe payment configuration
    ├── ApiBibleConfig.swift           # Bible API configuration
    └── TabletNotes.entitlements       # App capabilities
```

## Architecture Patterns

### MVVM with Service Layer

The app uses a **Model-View-Service** architecture built on SwiftUI and the Swift Observation framework:

- **Models**: SwiftData `@Model` classes for persistence (`Sermon`, `Note`, `Transcript`, `Summary`, `ChatMessage`, `User`)
- **Views**: SwiftUI views that observe service state directly
- **Services**: `@Observable` classes that own business logic, data operations, and external API communication

There are no standalone ViewModel classes — services fulfill that role and are injected into views.

### Observation Framework (`@Observable`)

Core services use the iOS 17+ Swift Observation framework instead of the legacy `ObservableObject` pattern:

| Context | Property Wrapper | Example |
|---------|-----------------|---------|
| View owns the instance | `@State` | `@State private var sermonService = SermonService()` |
| View receives instance & needs bindings | `@Bindable` | `@Bindable var sermonService: SermonService` |
| View receives instance, read-only | Plain `var` | `var authManager: AuthenticationManager` |
| Backward Combine compatibility | `@ObservationIgnored @Published` | For services that still need Combine publishers |

**Migrated services**: SermonService, ChatService, AuthenticationManager, RecordingService, AssemblyAILiveTranscriptionService, NetworkMonitor

### Navigation

Navigation uses `AppCoordinator` with a `@ViewBuilder` function for type-safe screen routing:

```swift
@ViewBuilder
private func destinationView(for screen: AppScreen) -> some View {
    switch screen {
    case .home: SermonListView(...)
    case .recording(let serviceType): RecordingView(...)
    case .sermonDetail(let sermon): SermonDetailView(...)
    // ...
    }
}
```

No `AnyView` type erasure is used — all navigation preserves concrete view types.

### Network Resilience

The app handles network transitions (WiFi/cellular switches, phone calls, airplane mode) gracefully:

- **NetworkMonitor** (`Services/NetworkMonitor.swift`): Singleton using `NWPathMonitor` to track real-time connectivity. Access via `NetworkMonitor.shared.isConnected` and `.connectionType`.
- **NetworkRetry** (`Services/NetworkRetry.swift`): `NetworkRetry.withExponentialBackoff()` wraps all network requests with automatic retry, connectivity checks, and error classification.
- **WebSocket reconnection**: `AssemblyAILiveTranscriptionService` observes `NetworkMonitor` and auto-reconnects when network is restored.
- **URLSession**: All sessions configured with `waitsForConnectivity = true`.

### Dependency Injection

- Services are initialized with required dependencies (e.g., `ModelContext` for SwiftData)
- Protocol-based design enables mocking for tests
- Injection happens at the coordinator/root view level
- Singleton services (`NetworkMonitor.shared`, `ChatService.shared`) use `@State` in their owning view

## Data Flow

```
User Action → SwiftUI View → Service → SwiftData / Supabase API
                  ↑                          |
                  └──── @Observable state ────┘
```

1. User interacts with a SwiftUI View
2. View calls methods on its injected Service
3. Service performs business logic and data operations
4. SwiftData manages local persistence; Supabase handles remote sync
5. Netlify Functions process AI transcription and summarization
6. Service properties update automatically via `@Observable`
7. SwiftUI re-renders only the views that read the changed properties

## Performance Patterns

- **No `AnyView`**: Use `@ViewBuilder` for conditional view rendering
- **No inline sorting in ForEach**: Cache sorted arrays as computed properties
- **Pre-compiled regex**: Use `MarkdownCleaner` — never compile `NSRegularExpression` in view bodies
- **File existence caching**: `Sermon.audioFileExists` uses `@Transient` with 5-second cache
- **Stable ForEach identity**: Use model properties (`.id`, `.title`) — never array offsets

## Design Principles

1. **Single Responsibility**: Each service owns one domain (recording, auth, sync, etc.)
2. **Separation of Concerns**: Views, services, and data models are cleanly separated
3. **Composition over Inheritance**: Services are composed, not subclassed
4. **Local-First**: SwiftData provides immediate data access; sync happens in the background
5. **Network Resilience**: All network operations use retry logic and connectivity monitoring
6. **Performance-First**: Cached computations, pre-compiled patterns, fine-grained observation

## External Services

| Service | Purpose | Integration |
|---------|---------|-------------|
| **Supabase** | Auth, database, file storage | Swift SDK via `SupabaseService` |
| **AssemblyAI** | Audio transcription | Via Netlify Functions + WebSocket |
| **Netlify Functions** | Serverless API layer | REST endpoints from `SupabaseService` |
| **Stripe** | Subscription payments | Via `SubscriptionService` |
| **API.Bible** | Bible text content | Via `BibleAPIService` variants |
