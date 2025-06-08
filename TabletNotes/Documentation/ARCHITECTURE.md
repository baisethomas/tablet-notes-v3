# TabletNotes App Architecture

## File Structure

```
TabletNotes/
├── App/
│   └── TabletNotesApp.swift      # Main app entry point with SwiftData setup
│
├── Features/                     # Feature-based organization
│   ├── Authentication/           # Login/registration screens
│   ├── Dashboard/                # Home screen with notes list
│   ├── Recording/                # Recording + note-taking feature
│   ├── Transcription/            # Viewing transcriptions/summaries 
│   ├── Settings/                 # User settings and account management
│   └── Subscription/             # Premium subscription management
│
├── Core/                         # Shared core functionality
│   ├── Models/                   # Data models and entities
│   │   ├── NoteModel.swift
│   │   ├── UserModel.swift
│   │   └── ... 
│   ├── Services/                 # Service layer
│   │   ├── AuthService.swift
│   │   ├── TranscriptionService.swift
│   │   ├── RecordingService.swift
│   │   ├── StorageService.swift
│   │   └── ...
│   └── Navigation/               # App navigation system
│
├── UI/                           # UI components and styling
│   ├── Components/               # Reusable UI components
│   │   ├── Buttons/
│   │   ├── Cards/
│   │   ├── ListItems/
│   │   └── ...
│   ├── Styles/                   # Styling and theming
│   │   ├── Colors.swift
│   │   ├── Typography.swift
│   │   └── ViewModifiers/
│   └── Helpers/                  # UI helper extensions
│
├── Utils/                        # Utility functions and extensions
│   ├── Extensions/
│   ├── Formatters/
│   └── Helpers/
│
└── Resources/                    # App resources
    ├── Assets.xcassets/          # Images and colors
    ├── Fonts/                    # Custom fonts
    └── Localizable.strings       # String localization
```

## Architecture Patterns

### MVVM (Model-View-ViewModel)
- **Models**: Core data structures using SwiftData
- **Views**: SwiftUI views for UI representation
- **ViewModels**: Business logic and state management using ObservableObject

### Repository Pattern
- Abstract data access layer between services and SwiftData
- Provides clean API for data operations

### Dependency Injection
- Services injected into ViewModels
- Environment Objects for widely used services
- ModelContext for SwiftData operations

## Data Flow

1. **User interacts with View**
2. **View calls methods on ViewModel**
3. **ViewModel coordinates with Services**
4. **Services interact with SwiftData or external APIs**
5. **Data flows back through the same path**
6. **ViewModel updates its state**
7. **View reacts to state changes**

## Design Principles

1. **Single Responsibility**: Each class has one primary responsibility
2. **Separation of Concerns**: UI, business logic, and data access are separated
3. **Composition over Inheritance**: Prefer composing objects over class hierarchies
4. **Immutability**: Use immutable data when possible
5. **Unidirectional Data Flow**: Data flows in one direction for predictability

## Feature Module Structure

Each feature module (e.g., Recording, Dashboard) follows this structure:

```
FeatureName/
├── Views/                    # SwiftUI Views
│   ├── FeatureNameView.swift # Main view
│   └── Components/           # Feature-specific components
│       └── ...
├── ViewModels/               # View Models
│   └── FeatureNameViewModel.swift
└── Models/                   # Feature-specific models (if needed beyond Core models)
    └── ... 
``` 