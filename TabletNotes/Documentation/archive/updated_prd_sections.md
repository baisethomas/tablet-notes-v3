# Updated PRD Sections for Native iOS Transcription

## Core Features - Updated AI Summarization Section

### 5. Transcription and Summarization
- **Processing**:
  - Transcription via native iOS Speech Recognition framework
  - Custom summarization using on-device NLP algorithms
  - Scripture detection using regex pattern matching
- **Implementation**:
  - Real-time transcription during recording
  - Post-processing for accuracy improvements
  - Session management for longer recordings (>1 minute)
- **Tier Behavior**:
  - Free: Basic transcription with high-level summary (1-2 paragraphs)
  - Paid: Enhanced transcription accuracy with deep summary + theological context (3-5 paragraphs)
- **Processing Status**:
  - Real-time transcription display during recording
  - Progress indicators for post-processing
  - Local notification when complete
- **Error Handling**:
  - Fallback to recorded audio when transcription fails
  - Manual correction options for transcription errors
  - Clear user feedback for recognition limitations

## Tech Stack - Updated Section

### Frontend
- **Framework**: iOS (SwiftUI)
- **State Management**: Combine framework
- **Navigation**: Coordinator pattern
- **Persistence**: SwiftData
- **Networking**: URLSession with Combine
- **Dependency Injection**: Custom DI container
- **Speech Recognition**: Native iOS Speech.framework

### Backend
- **Platform**: Supabase
- **Authentication**: Supabase Auth with JWT
- **Database**: PostgreSQL (via Supabase)
- **Storage**: Supabase Storage for audio files
- **Schema**:
  - User table
  - Sermon table
  - Transcription table
  - Notes table
  - Subscription table

### Third-Party Services
- **Summarization**: On-device NLP with Core ML (replacing AssemblyAI)
- **Scripture Data**: API.Bible or Bible.org API
- **Billing**: Stripe + StoreKit 2
- **Analytics**: Firebase Analytics
- **Crash Reporting**: Firebase Crashlytics
- **Email Service**: Resend or MailerSend
- **Push Notifications**: Firebase Cloud Messaging

## Performance Requirements - Updated Section

- **App Launch Time**: < 2 seconds on iPhone X or newer
- **Recording Initialization**: < 1 second from tap to recording
- **Transcription Response**: < 3 seconds lag for real-time transcription display
- **Transcription Accuracy**: > 85% for general speech, may vary for theological terms
- **Battery Usage**: < 8% battery per hour during recording with active transcription
- **Memory Footprint**: < 250MB memory usage during transcription
- **Offline Performance**: Full recording and transcription functionality without internet
- **Device Compatibility**: iPhone XS or newer recommended for optimal performance

## Privacy and Permissions - New Section

- **Required Permissions**:
  - Microphone access for recording
  - Speech recognition authorization
- **Privacy Considerations**:
  - On-device processing for sensitive content
  - Optional cloud processing for enhanced accuracy (paid tier)
  - Clear user consent for all speech processing
  - Transparency about data retention and usage
- **Info.plist Requirements**:
  - NSMicrophoneUsageDescription
  - NSSpeechRecognitionUsageDescription
- **User Controls**:
  - Option to disable transcription while maintaining recording
  - Clear indicators when speech recognition is active
  - Ability to delete transcription data

## Limitations and Constraints - New Section

- **Recognition Duration**: Native speech recognition sessions limited to ~1 minute
  - Implementation will handle automatic session restart
  - Users informed of potential brief pauses in transcription
- **Language Support**: Primary support for English, with limited support for other languages
  - Language availability dependent on iOS version and device capabilities
  - Clear indication of supported languages in settings
- **Specialized Terminology**: May have reduced accuracy for theological terms
  - Custom post-processing to improve recognition of common theological terms
  - User ability to add custom terms to recognition vocabulary
- **Device Performance**: Transcription quality varies by device model
  - Optimized settings automatically adjusted based on device capability
  - Reduced functionality on older devices (pre-iPhone XS)
