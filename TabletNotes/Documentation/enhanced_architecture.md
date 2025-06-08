# Enhanced Architecture for TabletNotes App

## Revised Architecture Overview

```
TabletNotes/
├── App/
│   ├── TabletNotesApp.swift           # Main app entry point with DI container setup
│   ├── AppDelegate.swift              # App lifecycle and system integration
│   └── SceneDelegate.swift            # UI lifecycle management
│
├── Features/                          # Feature-based organization
│   ├── Authentication/                # Login/registration screens
│   │   ├── Views/
│   │   │   ├── LoginView.swift
│   │   │   ├── SignupView.swift
│   │   │   ├── PasswordResetView.swift
│   │   │   └── Components/
│   │   ├── ViewModels/
│   │   │   ├── AuthViewModel.swift
│   │   │   └── UserProfileViewModel.swift
│   │   └── Coordinators/
│   │       └── AuthCoordinator.swift
│   │
│   ├── Onboarding/                    # First-time user experience
│   │   ├── Views/
│   │   │   ├── OnboardingView.swift
│   │   │   ├── FeatureHighlightView.swift
│   │   │   └── Components/
│   │   ├── ViewModels/
│   │   │   └── OnboardingViewModel.swift
│   │   └── Models/
│   │       └── OnboardingStep.swift
│   │
│   ├── Dashboard/                     # Home screen with notes list
│   │   ├── Views/
│   │   │   ├── DashboardView.swift
│   │   │   ├── SermonListView.swift
│   │   │   └── Components/
│   │   │       ├── SermonCard.swift
│   │   │       └── FilterBar.swift
│   │   ├── ViewModels/
│   │   │   ├── DashboardViewModel.swift
│   │   │   └── SermonListViewModel.swift
│   │   └── Coordinators/
│   │       └── DashboardCoordinator.swift
│   │
│   ├── Recording/                     # Recording + note-taking feature
│   │   ├── Views/
│   │   │   ├── RecordingView.swift
│   │   │   ├── ServiceTypeSelectionView.swift
│   │   │   ├── NoteEditorView.swift
│   │   │   └── Components/
│   │   │       ├── AudioWaveformView.swift
│   │   │       ├── RecordingControls.swift
│   │   │       └── NoteEditorToolbar.swift
│   │   ├── ViewModels/
│   │   │   ├── RecordingViewModel.swift
│   │   │   └── NoteEditorViewModel.swift
│   │   └── Coordinators/
│   │       └── RecordingCoordinator.swift
│   │
│   ├── Transcription/                 # Viewing transcriptions/summaries
│   │   ├── Views/
│   │   │   ├── TranscriptionView.swift
│   │   │   ├── SummaryView.swift
│   │   │   ├── ScriptureInsightView.swift
│   │   │   └── Components/
│   │   │       ├── TranscriptionPlayer.swift
│   │   │       └── ScriptureCard.swift
│   │   ├── ViewModels/
│   │   │   ├── TranscriptionViewModel.swift
│   │   │   └── ScriptureViewModel.swift
│   │   └── Coordinators/
│   │       └── TranscriptionCoordinator.swift
│   │
│   ├── Search/                        # Search functionality
│   │   ├── Views/
│   │   │   ├── SearchView.swift
│   │   │   ├── SearchResultsView.swift
│   │   │   └── Components/
│   │   │       ├── SearchBar.swift
│   │   │       └── SearchFilterView.swift
│   │   ├── ViewModels/
│   │   │   └── SearchViewModel.swift
│   │   └── Models/
│   │       └── SearchResult.swift
│   │
│   ├── Settings/                      # User settings and account management
│   │   ├── Views/
│   │   │   ├── SettingsView.swift
│   │   │   ├── AccountSettingsView.swift
│   │   │   ├── NotificationSettingsView.swift
│   │   │   └── Components/
│   │   │       └── SettingsCell.swift
│   │   ├── ViewModels/
│   │   │   └── SettingsViewModel.swift
│   │   └── Coordinators/
│   │       └── SettingsCoordinator.swift
│   │
│   └── Subscription/                  # Premium subscription management
│       ├── Views/
│       │   ├── SubscriptionView.swift
│       │   ├── PlanComparisonView.swift
│       │   └── Components/
│       │       ├── PlanCard.swift
│       │       └── FeatureList.swift
│       ├── ViewModels/
│       │   └── SubscriptionViewModel.swift
│       └── Coordinators/
│           └── SubscriptionCoordinator.swift
│
├── Core/                              # Shared core functionality
│   ├── Models/                        # Data models and entities
│   │   ├── User/
│   │   │   ├── UserModel.swift
│   │   │   └── UserPreferences.swift
│   │   ├── Sermon/
│   │   │   ├── SermonModel.swift
│   │   │   ├── ServiceType.swift
│   │   │   └── TranscriptionStatus.swift
│   │   ├── Notes/
│   │   │   ├── NoteModel.swift
│   │   │   └── ScriptureReference.swift
│   │   └── Subscription/
│   │       ├── SubscriptionPlan.swift
│   │       └── SubscriptionStatus.swift
│   │
│   ├── Database/                      # SwiftData configuration
│   │   ├── PersistenceController.swift
│   │   ├── MigrationPlan.swift
│   │   └── Repositories/
│   │       ├── UserRepository.swift
│   │       ├── SermonRepository.swift
│   │       ├── NoteRepository.swift
│   │       └── SubscriptionRepository.swift
│   │
│   ├── Services/                      # Service layer
│   │   ├── Auth/
│   │   │   ├── AuthService.swift
│   │   │   ├── AuthServiceProtocol.swift
│   │   │   └── KeychainService.swift
│   │   ├── API/
│   │   │   ├── NetworkService.swift
│   │   │   ├── APIClient.swift
│   │   │   ├── RequestBuilder.swift
│   │   │   └── Endpoints/
│   │   │       ├── AuthEndpoints.swift
│   │   │       ├── TranscriptionEndpoints.swift
│   │   │       ├── BibleEndpoints.swift
│   │   │       └── SubscriptionEndpoints.swift
│   │   ├── Recording/
│   │   │   ├── RecordingService.swift
│   │   │   ├── RecordingServiceProtocol.swift
│   │   │   └── AudioSessionManager.swift
│   │   ├── Transcription/
│   │   │   ├── TranscriptionService.swift
│   │   │   ├── TranscriptionServiceProtocol.swift
│   │   │   └── AssemblyAIClient.swift
│   │   ├── Scripture/
│   │   │   ├── ScriptureService.swift
│   │   │   ├── ScriptureServiceProtocol.swift
│   │   │   ├── BibleAPIClient.swift
│   │   │   └── ScriptureParser.swift
│   │   ├── Storage/
│   │   │   ├── StorageService.swift
│   │   │   ├── StorageServiceProtocol.swift
│   │   │   └── FileManager+Extensions.swift
│   │   ├── Subscription/
│   │   │   ├── SubscriptionService.swift
│   │   │   ├── SubscriptionServiceProtocol.swift
│   │   │   └── StoreKitManager.swift
│   │   ├── Analytics/
│   │   │   ├── AnalyticsService.swift
│   │   │   ├── AnalyticsServiceProtocol.swift
│   │   │   └── AnalyticsEvent.swift
│   │   └── BackgroundTasks/
│   │       ├── BackgroundTaskService.swift
│   │       └── BackgroundTaskServiceProtocol.swift
│   │
│   ├── Navigation/                    # App navigation system
│   │   ├── AppCoordinator.swift
│   │   ├── Coordinator.swift
│   │   ├── NavigationRouter.swift
│   │   └── DeepLinkHandler.swift
│   │
│   └── DI/                            # Dependency Injection
│       ├── DIContainer.swift
│       ├── ServiceProvider.swift
│       └── Injected.swift
│
├── UI/                                # UI components and styling
│   ├── Components/                    # Reusable UI components
│   │   ├── Buttons/
│   │   │   ├── PrimaryButton.swift
│   │   │   ├── SecondaryButton.swift
│   │   │   └── IconButton.swift
│   │   ├── Cards/
│   │   │   ├── BaseCard.swift
│   │   │   └── ContentCard.swift
│   │   ├── ListItems/
│   │   │   ├── StandardListItem.swift
│   │   │   └── SermonListItem.swift
│   │   ├── Inputs/
│   │   │   ├── StandardTextField.swift
│   │   │   ├── SearchField.swift
│   │   │   └── NoteEditor.swift
│   │   ├── Feedback/
│   │   │   ├── ToastView.swift
│   │   │   ├── LoadingIndicator.swift
│   │   │   └── ErrorView.swift
│   │   └── Media/
│   │       ├── AudioPlayerView.swift
│   │       └── WaveformView.swift
│   │
│   ├── Styles/                        # Styling and theming
│   │   ├── AppTheme.swift
│   │   ├── Colors.swift
│   │   ├── Typography.swift
│   │   ├── Spacing.swift
│   │   └── ViewModifiers/
│   │       ├── CardModifier.swift
│   │       ├── ShadowModifier.swift
│   │       └── AccessibilityModifiers.swift
│   │
│   └── Helpers/                       # UI helper extensions
│       ├── View+Extensions.swift
│       ├── Color+Extensions.swift
│       └── Image+Extensions.swift
│
├── Utils/                             # Utility functions and extensions
│   ├── Extensions/
│   │   ├── Date+Extensions.swift
│   │   ├── String+Extensions.swift
│   │   ├── Array+Extensions.swift
│   │   └── Result+Extensions.swift
│   ├── Formatters/
│   │   ├── DateFormatter+Extensions.swift
│   │   ├── DurationFormatter.swift
│   │   └── TextFormatter.swift
│   ├── Helpers/
│   │   ├── Logger.swift
│   │   ├── ErrorHandler.swift
│   │   └── Debouncer.swift
│   └── Constants/
│       ├── AppConstants.swift
│       ├── APIConstants.swift
│       └── FeatureFlags.swift
│
├── Resources/                         # App resources
│   ├── Assets.xcassets/               # Images and colors
│   ├── Fonts/                         # Custom fonts
│   ├── Localizable.strings            # String localization
│   └── LaunchScreen.storyboard        # Launch screen
│
└── Tests/                             # Test suite
    ├── UnitTests/
    │   ├── ViewModels/
    │   ├── Services/
    │   └── Repositories/
    ├── IntegrationTests/
    │   ├── API/
    │   └── Database/
    └── UITests/
        └── UserFlows/
```

## Enhanced Architecture Patterns

### 1. Coordinator Pattern for Navigation
- **Implementation**: Add a coordinator layer to manage navigation flow between features
- **Benefits**: Decouples view controllers from navigation logic, enables deep linking
- **Key Components**:
  - `Coordinator` protocol defining common navigation behavior
  - Feature-specific coordinators managing flows within features
  - `AppCoordinator` as the root coordinator managing the overall app flow
  - `DeepLinkHandler` for processing external links and notifications

### 2. Repository Pattern for Data Access
- **Implementation**: Enhance repository pattern with clear interfaces and error handling
- **Benefits**: Abstracts data sources, enables offline-first approach, simplifies testing
- **Key Components**:
  - Repository protocols defining data access contracts
  - Concrete implementations for SwiftData, network, and cache
  - Transaction support for atomic operations
  - Conflict resolution strategies for offline-online sync

### 3. Dependency Injection
- **Implementation**: Add a proper DI container for service management
- **Benefits**: Improves testability, modularizes code, simplifies dependency management
- **Key Components**:
  - `DIContainer` managing service registration and resolution
  - `@Injected` property wrapper for clean dependency injection
  - Service protocols for all services to enable mocking
  - Factory methods for creating complex object graphs

### 4. Combine for Reactive Programming
- **Implementation**: Use Combine framework for reactive data flow
- **Benefits**: Declarative approach to handling asynchronous events, simplified state management
- **Key Components**:
  - Publishers for data streams (user events, network responses)
  - Subscribers for UI updates
  - Operators for transforming data
  - Error handling with catch and retry operators

### 5. MVVM with Coordinator
- **Implementation**: Enhance MVVM with coordinator pattern for navigation
- **Benefits**: Clear separation of concerns, improved testability
- **Key Components**:
  - ViewModels exposing Combine publishers
  - Views subscribing to ViewModel state
  - Coordinators handling navigation between views
  - Input/Output pattern for ViewModel interfaces

## Technical Implementation Enhancements

### 1. Networking Layer
- **Implementation**: Build a robust networking layer with Combine
- **Key Components**:
  - `APIClient` as the main entry point for network requests
  - `RequestBuilder` for constructing URLRequests
  - Endpoint enums for type-safe API endpoints
  - Response decoders with proper error handling
  - Retry logic with exponential backoff
  - Authentication token management
  - Request/response logging for debugging

### 2. Persistence Layer
- **Implementation**: Enhance SwiftData implementation with migration support
- **Key Components**:
  - `PersistenceController` managing SwiftData stack
  - `MigrationPlan` for schema versioning
  - Repository implementations for CRUD operations
  - Caching strategies for frequently accessed data
  - Background context for heavy operations
  - Error handling and recovery mechanisms

### 3. Audio Recording & Processing
- **Implementation**: Robust audio recording with AVFoundation
- **Key Components**:
  - `AudioSessionManager` for managing audio session configuration
  - `RecordingService` for handling recording operations
  - Background mode support for continuous recording
  - Audio level monitoring for quality feedback
  - Compression and format conversion utilities
  - Error handling for permission and hardware issues

### 4. Background Processing
- **Implementation**: Support for background tasks and uploads
- **Key Components**:
  - `BackgroundTaskService` for managing background tasks
  - Background upload sessions for transcription files
  - Background fetch for updating content
  - Background processing task for offline transcription
  - Battery and network awareness for optimal performance
  - Completion handlers and error recovery

### 5. Security Implementation
- **Implementation**: Comprehensive security measures
- **Key Components**:
  - `KeychainService` for secure credential storage
  - Data encryption for sensitive information
  - Certificate pinning for API communications
  - Secure token management with refresh mechanism
  - Biometric authentication integration
  - App Transport Security configuration

## Testing Architecture

### 1. Unit Testing Framework
- **Implementation**: Comprehensive unit test suite with XCTest
- **Key Components**:
  - Test cases for all ViewModels
  - Test cases for service layer
  - Mock implementations of all service protocols
  - Test helpers for common testing scenarios
  - Code coverage reporting

### 2. UI Testing
- **Implementation**: UI tests for critical user flows
- **Key Components**:
  - Test cases for main user journeys
  - Accessibility testing
  - Performance testing for UI operations
  - Screenshot testing for visual regression

### 3. Integration Testing
- **Implementation**: Tests for service integrations
- **Key Components**:
  - API integration tests
  - Database integration tests
  - Mock server for API testing
  - Test environment configuration

## Deployment & CI/CD

### 1. CI/CD Pipeline
- **Implementation**: GitHub Actions or Bitbucket Pipelines
- **Key Components**:
  - Automated build process
  - Unit and UI test execution
  - Code quality checks (SwiftLint)
  - Automated versioning
  - TestFlight deployment

### 2. Environment Configuration
- **Implementation**: Environment-specific configuration
- **Key Components**:
  - Development, staging, and production environments
  - Configuration files for each environment
  - Feature flags for gradual rollout
  - Debug vs. release build configurations

## Error Handling Strategy

### 1. Comprehensive Error Types
- **Implementation**: Domain-specific error types
- **Key Components**:
  - Network errors (connectivity, server, authentication)
  - Business logic errors
  - Validation errors
  - Resource errors (file not found, permission denied)

### 2. Error Presentation
- **Implementation**: User-friendly error handling
- **Key Components**:
  - Error mapping to user-friendly messages
  - Contextual error presentation
  - Recovery actions where applicable
  - Logging for debugging

## Analytics Implementation

### 1. Event Tracking
- **Implementation**: Comprehensive analytics with Firebase
- **Key Components**:
  - User journey events
  - Feature usage tracking
  - Error and crash reporting
  - Performance monitoring
  - Conversion and retention metrics

### 2. A/B Testing
- **Implementation**: Feature flag management for A/B testing
- **Key Components**:
  - Remote configuration
  - Experiment definition
  - Variant assignment
  - Results tracking and analysis
