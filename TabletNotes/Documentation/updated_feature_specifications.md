# Updated Feature and Technical Specifications for iOS Speech Framework

## Transcription Feature Specifications

### Real-time Transcription
- **Implementation**: Uses `SFSpeechRecognizer` with audio buffer streaming
- **User Experience**: 
  - Text appears with 1-3 second delay as user speaks
  - Interim results shown with subtle visual indication
  - Final results replace interim results with visual confirmation
- **Technical Requirements**:
  - Audio session configuration: `.playAndRecord` category
  - Audio format: 16kHz sample rate, mono channel
  - Buffer size: 1024 samples for optimal performance
- **UI Components**:
  - Live transcription view with auto-scrolling
  - Visual indicator for active listening
  - Pause/resume transcription button

### Session Management
- **Implementation**: Custom `SpeechSessionManager` to handle iOS limitations
- **Technical Challenge**: iOS limits continuous recognition to ~1 minute
- **Solution**:
  - Automatic session restart before timeout
  - Seamless transition between sessions
  - Text concatenation across session boundaries
- **Error Handling**:
  - Graceful recovery from session timeouts
  - Background noise detection and filtering
  - Signal quality monitoring

### Offline Transcription
- **Implementation**: On-device speech recognition
- **Capabilities**:
  - Full transcription without internet connection
  - Language support limited to downloaded models
  - Reduced accuracy compared to network-enhanced recognition
- **Storage Requirements**:
  - Language models: ~50MB per language
  - Downloaded models stored in app container
- **Battery Considerations**:
  - Higher battery usage during on-device processing
  - Optimization for longer recording sessions

### Custom Summarization
- **Implementation**: Replace AssemblyAI summarization with on-device NLP
- **Technical Approach**:
  - Use `NLTagger` for key phrase extraction
  - Sentence importance ranking algorithm
  - Extractive summarization technique
- **Tiered Implementation**:
  - Free tier: Basic extractive summary (key sentences)
  - Paid tier: Enhanced summary with topic clustering
- **Performance Considerations**:
  - Process in background thread to avoid UI blocking
  - Chunking for longer transcripts
  - Progress indication for user feedback

### Scripture Reference Detection
- **Implementation**: Custom regex pattern matching
- **Technical Approach**:
  - Regular expression library for common Bible reference formats
  - Post-processing of transcription text
  - Integration with Bible API for verification
- **Performance Optimization**:
  - Cached reference patterns
  - Incremental processing during transcription
  - Background processing for longer texts

## Technical Specifications

### Audio Recording Configuration
- **Audio Session Category**: `.playAndRecord`
- **Audio Session Mode**: `.spokenAudio`
- **Sample Rate**: 16kHz (optimal for speech recognition)
- **Bit Depth**: 16-bit
- **Channels**: Mono
- **Format**: Linear PCM
- **Buffer Size**: 1024 samples
- **Background Modes**: Audio recording capability in Info.plist

### Speech Recognition Configuration
- **Authorization**: Request at app first launch
- **Recognition Language**: Based on device locale, with manual override
- **Task Configuration**:
  - `SFSpeechRecognitionTaskHint.confirmation` for better accuracy
  - Enable punctuation with `.enableAutomaticPunctuation`
- **Recognition Constraints**:
  - Optional domain-specific vocabulary (theological terms)
  - On-device recognition when possible
- **Result Handling**:
  - Process both interim and final results
  - Confidence threshold for acceptance

### Performance Specifications
- **CPU Usage**: Peak < 40% during active transcription
- **Memory Usage**: < 250MB during transcription
- **Battery Impact**: < 8% per hour of active transcription
- **Storage Requirements**:
  - Audio: ~0.5MB per minute at 128kbps
  - Transcription text: Negligible
  - Language models: ~50MB per language
- **Minimum Device**: iPhone XS recommended (A12 Bionic or newer)
- **iOS Version**: iOS 15.0 or later for optimal performance

### Error Handling Specifications
- **Authorization Errors**:
  - Clear explanation when permission denied
  - Easy access to settings for permission changes
- **Recognition Errors**:
  - Automatic retry with exponential backoff
  - Fallback to recorded audio when transcription fails
  - User notification for persistent failures
- **Audio Quality Issues**:
  - Real-time audio level monitoring
  - User feedback for poor recording conditions
  - Noise reduction suggestions

### User Interface Specifications
- **Transcription Display**:
  - Auto-scrolling text view
  - Visual distinction between interim and final results
  - Word confidence indication (subtle styling)
- **Status Indicators**:
  - Microphone active indicator
  - Processing status (recording, transcribing, processing)
  - Session transition indicator (subtle)
- **Control Elements**:
  - Pause/resume transcription
  - Manual correction interface
  - Language selection

## Integration Specifications

### SwiftUI Integration
- **ObservableObject Pattern**:
  - `@Published` properties for transcription state
  - Combine publishers for asynchronous updates
- **View Hierarchy**:
  - `RecordingView` as container
  - `LiveTranscriptionView` for real-time display
  - `TranscriptionControlsView` for user controls

### Combine Framework Integration
- **Publishers**:
  - `transcriptionPublisher` for text updates
  - `recognitionStatusPublisher` for status changes
  - `errorPublisher` for error events
- **Operators**:
  - `debounce` for UI updates
  - `receive(on: DispatchQueue.main)` for UI thread safety
  - `retry` for error recovery

### Persistence Integration
- **SwiftData Model**:
  - `TranscriptionEntity` with relationship to `SermonEntity`
  - Incremental saving during transcription
  - Versioning for transcription corrections
- **Backup Strategy**:
  - Local backup of transcription text
  - Cloud backup for paid tier
  - Conflict resolution for offline changes

## Testing Specifications

### Unit Testing
- **Mock SFSpeechRecognizer**:
  - Simulate recognition results
  - Test session management
  - Verify error handling
- **Test Cases**:
  - Authorization flows
  - Session timeout handling
  - Result processing
  - Error recovery

### Integration Testing
- **End-to-end Scenarios**:
  - Recording to transcription flow
  - Offline operation
  - Background processing
- **Performance Testing**:
  - CPU/memory profiling
  - Battery consumption measurement
  - Response time verification

### User Acceptance Testing
- **Test Scenarios**:
  - Various accents and speaking styles
  - Different noise environments
  - Theological terminology accuracy
  - Session transitions during long recordings

## Privacy and Security Specifications

### Data Handling
- **Audio Storage**:
  - Encrypted at rest
  - Automatic deletion based on tier (30 days for free)
- **Transcription Data**:
  - Stored in app container
  - Encrypted database
- **Analytics**:
  - Anonymous usage metrics
  - Opt-out option

### Permission Management
- **Required Entries in Info.plist**:
  - `NSSpeechRecognitionUsageDescription`
  - `NSMicrophoneUsageDescription`
- **Permission Requests**:
  - Clear explanation of usage
  - Graceful degradation if denied
  - Easy access to settings for changes

## Accessibility Specifications

### VoiceOver Support
- **Custom Rotor Actions**:
  - Navigate through transcription by sentence
  - Access correction interface
- **Announcements**:
  - Status changes
  - Completion of processing
  - Error conditions

### Dynamic Type
- **Text Scaling**:
  - Support all accessibility text sizes
  - Maintain layout integrity at large sizes
- **Control Sizing**:
  - Minimum touch target size of 44x44pt
  - Adequate spacing between controls
