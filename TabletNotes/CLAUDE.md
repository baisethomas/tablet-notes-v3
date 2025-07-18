# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TabletNotes is an iOS app built with SwiftUI that allows users to record sermons, take notes during recording, and get AI-powered transcription and summaries. The app uses a Netlify backend for API functions and Supabase for data persistence.

## Development Commands

### Building and Running
- Build and run the app: Use Xcode to build and run the TabletNotes target
- The app targets iOS devices and supports SwiftData for local data management
- No package managers (CocoaPods, SPM CLI) are used - dependencies are managed through Xcode's Swift Package Manager integration

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
- **MVVM**: Model-View-ViewModel pattern using SwiftUI and ObservableObject
- **Coordinator Pattern**: `AppCoordinator` manages navigation between screens
- **Service Layer**: Protocol-based services for different features (Auth, Recording, Transcription, etc.)
- **Repository Pattern**: Services abstract data access from ViewModels

### Key Components

#### Models (SwiftData)
- `Sermon`: Main entity with audio file, notes, transcript, and summary relationships
- `Note`: User-written notes during recording
- `Transcript`: AI-generated transcription with segments
- `Summary`: AI-generated summary of the sermon
- All models use `@Model` annotation for SwiftData persistence

#### Services
- **Protocol-based design**: Each service has a corresponding protocol for testability
- **SupabaseService**: Handles file uploads and API communication with Netlify backend
- **TranscriptionService**: Manages AssemblyAI integration for transcription
- **SummaryService**: Handles AI-powered summarization
- **RecordingService**: Manages audio recording functionality
- **SermonService**: CRUD operations for sermons using SwiftData

#### Views and Navigation
- **AppCoordinator**: Central navigation coordinator with screen enumeration
- **Screen-based navigation**: Each major screen is represented as a case in the coordinator
- **Service injection**: Services are passed down through the view hierarchy

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

### AI Processing
- **Transcription**: AssemblyAI integration via Netlify Functions
- **Summarization**: AI-powered sermon summaries
- **Asynchronous processing**: Status tracking for long-running operations

### Data Management
- **Local-first**: SwiftData for immediate data access
- **Sync capabilities**: Background sync with Supabase
- **Status tracking**: Each sermon tracks sync, transcription, and summary status

## Configuration

### API Keys and Configuration
- AssemblyAI API key: Stored in `AssemblyAIKey.swift` (not committed to version control)
- Supabase credentials: Currently hardcoded in `SupabaseService.swift` (should be moved to Config.plist)
- Netlify API base URL: `https://comfy-daffodil-7ecc55.netlify.app`

### Environment Setup
- Xcode 15+ required
- iOS 17+ target deployment
- Swift 5.9+ language features

## Development Notes

### Service Dependencies
- Services are initialized with their required dependencies (e.g., ModelContext for SwiftData operations)
- Protocol-based design allows for easy mocking and testing
- Dependency injection happens at the coordinator level

### Data Persistence
- SwiftData is used for local data persistence
- Models use relationships with cascade delete rules
- Sync status tracking enables offline-first functionality

### Error Handling
- Services should handle errors gracefully and update status fields
- UI should reflect processing states (loading, error, success)
- Network errors should be handled with retry mechanisms where appropriate

### Testing Strategy
- Unit tests for service layer business logic
- UI tests for critical user flows
- Mock services for testing without network dependencies