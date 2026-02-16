# Updated Architecture Sections for Native iOS Transcription

## Core/Services/Transcription - Updated Section

```
Core/
├── Services/
│   ├── Transcription/
│   │   ├── SpeechRecognitionService.swift       # Replaces TranscriptionService
│   │   ├── SpeechRecognitionServiceProtocol.swift
│   │   ├── SpeechSessionManager.swift           # Manages recognition sessions
│   │   ├── TranscriptionProcessor.swift         # Post-processing for accuracy
│   │   └── SummarizationService.swift           # Custom summarization logic
```

### SpeechRecognitionService Implementation

The `SpeechRecognitionService` will replace the previously planned `AssemblyAIClient` and handle all speech-to-text functionality using the native iOS Speech Recognition framework:

```swift
protocol SpeechRecognitionServiceProtocol {
    func startLiveTranscription() -> AnyPublisher<TranscriptionUpdate, Error>
    func processRecordedAudio(url: URL) -> AnyPublisher<TranscriptionResult, Error>
    func cancelTranscription()
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus { get }
    func requestAuthorization() -> AnyPublisher<SFSpeechRecognizerAuthorizationStatus, Never>
}

class SpeechRecognitionService: SpeechRecognitionServiceProtocol {
    private let speechRecognizer: SFSpeechRecognizer
    private let sessionManager: SpeechSessionManager
    private let audioEngine: AVAudioEngine
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognitionSubject = PassthroughSubject<TranscriptionUpdate, Error>()
    
    // Implementation details for handling speech recognition
    // Including session management for recordings > 1 minute
}
```

### SpeechSessionManager Implementation

The `SpeechSessionManager` will handle the limitation of ~1 minute per recognition session by automatically creating new sessions:

```swift
class SpeechSessionManager {
    private let maxSessionDuration: TimeInterval = 50 // Slightly less than 1 minute
    private var currentSessionStartTime: Date?
    private var sessionRestartHandler: (() -> Void)?
    
    // Implementation for managing session timeouts and restarts
}
```

### TranscriptionProcessor Implementation

The `TranscriptionProcessor` will handle post-processing to improve accuracy, especially for theological terms:

```swift
class TranscriptionProcessor {
    private let theologicalTerms: [String: String] // Dictionary of common terms and corrections
    
    func processTranscription(_ text: String) -> String {
        // Implementation for improving transcription accuracy
        // Including theological term correction and formatting
    }
}
```

### SummarizationService Implementation

The `SummarizationService` will replace the AI summarization previously handled by AssemblyAI:

```swift
protocol SummarizationServiceProtocol {
    func generateSummary(from text: String, detailed: Bool) -> AnyPublisher<String, Error>
}

class SummarizationService: SummarizationServiceProtocol {
    private let nlProcessor: NLProcessor
    
    func generateSummary(from text: String, detailed: Bool) -> AnyPublisher<String, Error> {
        // Implementation using Natural Language framework
        // Different approaches based on user tier (basic vs. detailed)
    }
}
```

## Core/Services/Scripture - Updated Section

The Scripture service remains largely unchanged but will need to integrate with the new transcription service:

```swift
class ScriptureService: ScriptureServiceProtocol {
    private let bibleAPIClient: BibleAPIClient
    private let scriptureParser: ScriptureParser
    
    func detectReferences(in text: String) -> [ScriptureReference] {
        // Implementation for detecting scripture references in transcribed text
    }
    
    func fetchVerseContent(for reference: ScriptureReference) -> AnyPublisher<Scripture, Error> {
        // Implementation for fetching verse content from Bible API
    }
}
```

## Feature/Recording - Updated Section

The Recording feature will need updates to integrate with the native speech recognition:

```
Features/
├── Recording/
│   ├── Views/
│   │   ├── RecordingView.swift
│   │   ├── LiveTranscriptionView.swift        # New component for real-time display
│   │   ├── ServiceTypeSelectionView.swift
│   │   ├── NoteEditorView.swift
│   │   └── Components/
│   │       ├── AudioWaveformView.swift
│   │       ├── RecordingControls.swift
│   │       ├── TranscriptionStatusView.swift  # New component for status display
│   │       └── NoteEditorToolbar.swift
│   ├── ViewModels/
│   │   ├── RecordingViewModel.swift
│   │   ├── TranscriptionViewModel.swift       # New ViewModel for transcription
│   │   └── NoteEditorViewModel.swift
│   └── Coordinators/
│       └── RecordingCoordinator.swift
```

### RecordingViewModel Implementation

The `RecordingViewModel` will need to coordinate with the speech recognition service:

```swift
class RecordingViewModel: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var liveTranscription: String = ""
    @Published var recognitionStatus: RecognitionStatus = .inactive
    
    private let recordingService: RecordingServiceProtocol
    private let speechRecognitionService: SpeechRecognitionServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // Implementation for managing recording and live transcription
}
```

### TranscriptionViewModel Implementation

A new `TranscriptionViewModel` will handle the transcription-specific logic:

```swift
class TranscriptionViewModel: ObservableObject {
    @Published var transcriptionText: String = ""
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    
    private let speechRecognitionService: SpeechRecognitionServiceProtocol
    private let transcriptionProcessor: TranscriptionProcessor
    private var cancellables = Set<AnyCancellable>()
    
    // Implementation for managing transcription processing
}
```

## App/AppDelegate - Updated Section

The `AppDelegate` will need to handle speech recognition authorization:

```swift
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Request speech recognition authorization at app launch
        SFSpeechRecognizer.requestAuthorization { status in
            // Handle authorization status
        }
        
        return true
    }
}
```

## Utils/Permissions - New Section

A new permissions helper will manage speech recognition authorization:

```swift
class PermissionsManager {
    static let shared = PermissionsManager()
    
    func requestMicrophonePermission() -> AnyPublisher<Bool, Never> {
        // Implementation for requesting microphone permission
    }
    
    func requestSpeechRecognitionPermission() -> AnyPublisher<SFSpeechRecognizerAuthorizationStatus, Never> {
        // Implementation for requesting speech recognition permission
    }
}
```

## Testing/SpeechRecognition - New Section

New test cases will be needed for the speech recognition functionality:

```
Tests/
├── UnitTests/
│   ├── Services/
│   │   ├── SpeechRecognitionServiceTests.swift
│   │   ├── SpeechSessionManagerTests.swift
│   │   ├── TranscriptionProcessorTests.swift
│   │   └── SummarizationServiceTests.swift
```

## Error Handling - Updated Section

Error handling will need to be expanded to cover speech recognition specific errors:

```swift
enum SpeechRecognitionError: Error {
    case authorizationDenied
    case recognitionFailed(String)
    case sessionTimeout
    case audioFormatError
    case deviceNotSupported
}

class ErrorHandler {
    func handleSpeechRecognitionError(_ error: SpeechRecognitionError) -> String {
        // Implementation for user-friendly error messages
    }
}
```
