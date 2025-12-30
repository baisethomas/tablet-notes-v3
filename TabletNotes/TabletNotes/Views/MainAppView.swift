import SwiftUI
import SwiftData
import Foundation
import Combine
// Import models and services from their relative paths

// Add these imports if the models/services are in subfolders
// If not, ensure these files are in the same target
// import TabletNotes.Models
// import TabletNotes.Services

// Centralized navigation enum
enum AppScreen {
    case onboarding
    case home
    case recording(serviceType: String?)
    case sermonDetail(sermon: Sermon)
    case sermons
    case settings
    case account
}

struct MainAppView: View {
    let modelContext: ModelContext
    @State private var currentScreen: AppScreen = .home
    @State private var showServiceTypeModal = false
    @State private var selectedServiceType: String? = nil
    @State private var lastCreatedSermon: Sermon? = nil
    @State private var showSplash = true
    @State private var onboardingReturnScreen: AppScreen = .home // Track where to return after tutorial
    @State private var currentRecordingSessionId = UUID().uuidString // Persistent session ID for recording
    @State private var currentRecordingServiceType: String? = nil // Track what type of service is being recorded
    @State private var cancellables = Set<AnyCancellable>() // Store Combine subscriptions for mini player
    @StateObject private var sermonService: SermonService
    @StateObject private var settingsService = SettingsService.shared
    @StateObject private var recordingService = RecordingService()
    @StateObject private var transcriptionService = TranscriptionService()
    @StateObject private var trialPromptManager = TrialPromptManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var showTrialPrompt = false
    @StateObject private var syncService: SyncService
    @StateObject private var backgroundSyncManager: BackgroundSyncManager

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        _sermonService = StateObject(wrappedValue: SermonService(modelContext: modelContext))
        let syncSvc = SyncService(
            modelContext: modelContext,
            supabaseService: SupabaseService.shared,
            authService: AuthenticationManager.shared
        )
        _syncService = StateObject(wrappedValue: syncSvc)
        _backgroundSyncManager = StateObject(wrappedValue: BackgroundSyncManager(syncService: syncSvc))

        // Initialize TranscriptionRetryService with ModelContext
        TranscriptionRetryService.shared.setModelContext(modelContext)
        
        // Initialize SummaryRetryService with ModelContext
        SummaryRetryService.shared.setModelContext(modelContext)

        // Check if user has seen onboarding before
        if !UserDefaults.standard.bool(forKey: "hasSeenOnboarding") {
            _currentScreen = State(initialValue: .onboarding)
        }
    }

    var body: some View {
        if showSplash {
            BrandSplashView {
                withAnimation(.easeInOut(duration: 0.5)) {
                    showSplash = false
                }
            }
        } else {
            NavigationStack {
                ZStack(alignment: .bottom) {
                switch currentScreen {
                case .onboarding:
                    OnboardingView(
                        onComplete: {
                            // Only set hasSeenOnboarding to true if this is the first time
                            if case .home = onboardingReturnScreen {
                                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                            }
                            currentScreen = onboardingReturnScreen
                        },
                        onSkip: {
                            // Only set hasSeenOnboarding to true if this is the first time
                            if case .home = onboardingReturnScreen {
                                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                            }
                            currentScreen = onboardingReturnScreen
                        }
                    )
                case .home:
                    AnyView(SermonListView(
                        sermonService: sermonService,
                        syncService: syncService,
                        onSermonSelected: { sermon in
                            currentScreen = .sermonDetail(sermon: sermon)
                        },
                        onSettings: {
                            currentScreen = .settings
                        },
                        onStartRecording: {
                            showServiceTypeModal = true
                        }
                    ))
                case .recording(let serviceType):
                    AnyView(RecordingView(
                        serviceType: serviceType ?? "Sermon",
                        noteService: NoteService(sessionId: currentRecordingSessionId),
                        onNext: { sermon in
                            sermonService.fetchSermons() // Refresh the list
                            lastCreatedSermon = sermon
                            // Delay clearing session to ensure notes are fully saved to sermon
                            // This prevents race condition where session clears before async sermon save completes
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                let noteService = NoteService(sessionId: currentRecordingSessionId)
                                noteService.clearSession()
                                // Generate new session ID for next recording
                                currentRecordingSessionId = UUID().uuidString
                            }
                            currentScreen = .sermons // Go to the list after recording
                        },
                        sermonService: sermonService,
                        recordingService: recordingService,
                        transcriptionService: transcriptionService
                    ))
                case .sermonDetail(let sermon):
                    AnyView(SermonDetailView(
                        sermonService: sermonService,
                        authManager: authManager,
                        sermonID: sermon.id,
                        onBack: { currentScreen = .sermons }
                    ))
                case .sermons:
                    AnyView(SermonListView(
                        sermonService: sermonService,
                        syncService: syncService,
                        onSermonSelected: { sermon in
                            currentScreen = .sermonDetail(sermon: sermon)
                        },
                        onSettings: {
                            currentScreen = .settings
                        },
                        onStartRecording: {
                            showServiceTypeModal = true
                        }
                    ))
                case .settings:
                    AnyView(SettingsView(
                        onNext: { 
                            currentScreen = .home 
                        },
                        onShowOnboarding: {
                            onboardingReturnScreen = .settings
                            currentScreen = .onboarding
                        },
                        onNavigateToAccount: {
                            currentScreen = .account
                        }
                    ))
                case .account:
                    AnyView(AccountView(
                        onBack: { 
                            currentScreen = .home 
                        },
                        onNavigateToSettings: {
                            currentScreen = .settings
                        }
                    ))
                }

                // Show footer and mini-player together when not in onboarding, settings, or account
                if !isOnboardingScreen(currentScreen) && !isSettingsOrAccountScreen(currentScreen) {
                    VStack(spacing: 0) {
                        Spacer()

                        // Show mini-player above footer when recording
                        if recordingService.isRecording,
                           let serviceType = currentRecordingServiceType,
                           !isRecordingScreen(currentScreen) {
                            MiniPlayer(
                                serviceType: serviceType,
                                duration: recordingService.recordingDuration,
                                isRecording: recordingService.isRecording,
                                isPaused: recordingService.isPaused,
                                onTap: {
                                    // Navigate back to recording screen
                                    currentScreen = .recording(serviceType: serviceType)
                                },
                                onPlayPause: {
                                    // Handle pause/resume
                                    do {
                                        if recordingService.isPaused {
                                            try recordingService.resumeRecording()
                                            print("[MiniPlayer] Recording resumed")
                                        } else {
                                            try recordingService.pauseRecording()
                                            print("[MiniPlayer] Recording paused")
                                        }
                                    } catch {
                                        print("[MiniPlayer] Failed to pause/resume recording: \(error)")
                                    }
                                },
                                onStop: {
                                    // Stop recording and process
                                    Task {
                                        // Stop the recording and get the audio URL
                                        let audioURL = recordingService.stopRecording()
                                        print("[MiniPlayer] Recording stopped")

                                        // Stop transcription service
                                        transcriptionService.stopTranscription()
                                        print("[MiniPlayer] Transcription stopped")

                                        await MainActor.run {
                                            if let audioURL = audioURL, let serviceType = currentRecordingServiceType {
                                                // Create title and date for processing
                                                let title = "Sermon on " + DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
                                                let date = Date()

                                                // Process the recording just like in RecordingView
                                                transcriptionService.transcribeAudioFileWithResult(url: audioURL) { result in
                                                    DispatchQueue.main.async {
                                                        switch result {
                                                        case .success(let (text, segments)):
                                                            guard !text.isEmpty else { return }

                                                            let transcriptModel = Transcript(text: text, segments: segments)
                                                            let summaryModel = Summary(text: "", type: serviceType, status: "processing")
                                                            let sermonId = UUID()

                                                            // Get notes from the current session
                                                            let noteService = NoteService(sessionId: currentRecordingSessionId)
                                                            let notes = noteService.currentNotes

                                                            // Save sermon with transcript
                                                            sermonService.saveSermon(
                                                                title: title,
                                                                audioFileURL: audioURL,
                                                                date: date,
                                                                serviceType: serviceType,
                                                                speaker: nil,
                                                                transcript: transcriptModel,
                                                                notes: notes,
                                                                summary: summaryModel,
                                                                transcriptionStatus: "complete",
                                                                summaryStatus: "processing",
                                                                id: sermonId
                                                            )

                                                            // Generate summary via service layer
                                                            // Create a temporary sermon object to avoid race condition
                                                            if let currentUser = AuthenticationManager.shared.currentUser {
                                                                let tempSermon = Sermon(
                                                                    id: sermonId,
                                                                    title: title,
                                                                    audioFileURL: audioURL,
                                                                    date: date,
                                                                    serviceType: serviceType,
                                                                    speaker: nil,
                                                                    transcript: transcriptModel,
                                                                    notes: notes,
                                                                    summary: summaryModel,
                                                                    transcriptionStatus: "complete",
                                                                    summaryStatus: "processing",
                                                                    userId: currentUser.id
                                                                )
                                                                sermonService.generateSummaryForSermon(tempSermon, transcript: text, serviceType: serviceType)
                                                            }

                                                            print("[MiniPlayer] Processing complete, refreshing sermon list")
                                                            sermonService.fetchSermons()

                                                        case .failure(let error):
                                                            print("[MiniPlayer] Transcription failed: \(error)")
                                                            // Save recording for later processing
                                                            let noteService = NoteService(sessionId: currentRecordingSessionId)
                                                            let notes = noteService.currentNotes

                                                            sermonService.saveSermon(
                                                                title: title,
                                                                audioFileURL: audioURL,
                                                                date: date,
                                                                serviceType: serviceType,
                                                                transcript: nil,
                                                                notes: notes,
                                                                summary: nil,
                                                                transcriptionStatus: "pending",
                                                                summaryStatus: "pending",
                                                                id: UUID()
                                                            )
                                                        }
                                                    }
                                                }
                                            }

                                            // Clear recording state
                                            currentRecordingServiceType = nil
                                            // Delay clearing session to ensure notes are fully saved
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                let noteService = NoteService(sessionId: currentRecordingSessionId)
                                                noteService.clearSession()
                                                // Generate new session ID for next recording
                                                currentRecordingSessionId = UUID().uuidString
                                            }
                                        }
                                    }
                                }
                            )
                        }

                        FooterView(
                        selectedTab: tabForScreen(currentScreen),
                        isRecording: recordingService.isRecording,
                        isPaused: recordingService.isPaused,
                        onHome: { currentScreen = .home },
                        onRecord: { 
                            // Check if recording is in progress
                            if recordingService.isRecording {
                                // Handle pause/resume for active recording
                                do {
                                    if recordingService.isPaused {
                                        try recordingService.resumeRecording()
                                        print("[MainAppView] Recording resumed")
                                    } else {
                                        try recordingService.pauseRecording()
                                        print("[MainAppView] Recording paused")
                                    }
                                } catch {
                                    print("[MainAppView] Failed to pause/resume recording: \(error)")
                                }
                            } else {
                                // No recording in progress, show service type modal to start new recording
                                showServiceTypeModal = true 
                            }
                        },
                        onAccount: { currentScreen = .account }
                    )
                    }
                }

                // Show mini-player on settings/account screens when recording (no footer)
                if isSettingsOrAccountScreen(currentScreen),
                   recordingService.isRecording,
                   let serviceType = currentRecordingServiceType,
                   !isRecordingScreen(currentScreen) {
                    MiniPlayer(
                        serviceType: serviceType,
                        duration: recordingService.recordingDuration,
                        isRecording: recordingService.isRecording,
                        isPaused: recordingService.isPaused,
                        onTap: {
                            // Navigate back to recording screen
                            currentScreen = .recording(serviceType: serviceType)
                        },
                        onPlayPause: {
                            // Handle pause/resume
                            do {
                                if recordingService.isPaused {
                                    try recordingService.resumeRecording()
                                    print("[MiniPlayer] Recording resumed")
                                } else {
                                    try recordingService.pauseRecording()
                                    print("[MiniPlayer] Recording paused")
                                }
                            } catch {
                                print("[MiniPlayer] Failed to pause/resume recording: \(error)")
                            }
                        },
                        onStop: {
                            // Stop recording and process
                            Task {
                                // Stop the recording and get the audio URL
                                let audioURL = recordingService.stopRecording()
                                print("[MiniPlayer] Recording stopped")

                                // Stop transcription service
                                transcriptionService.stopTranscription()
                                print("[MiniPlayer] Transcription stopped")

                                await MainActor.run {
                                    if let audioURL = audioURL, let serviceType = currentRecordingServiceType {
                                        // Create title and date for processing
                                        let title = "Sermon on " + DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
                                        let date = Date()

                                        // Process the recording just like in RecordingView
                                        transcriptionService.transcribeAudioFileWithResult(url: audioURL) { result in
                                            DispatchQueue.main.async {
                                                switch result {
                                                case .success(let (text, segments)):
                                                    guard !text.isEmpty else { return }

                                                    let transcriptModel = Transcript(text: text, segments: segments)
                                                    let summaryModel = Summary(text: "", type: serviceType, status: "processing")
                                                    let sermonId = UUID()

                                                    // Get notes from the current session
                                                    let noteService = NoteService(sessionId: currentRecordingSessionId)
                                                    let notes = noteService.currentNotes

                                                    // Save sermon with transcript
                                                    sermonService.saveSermon(
                                                        title: title,
                                                        audioFileURL: audioURL,
                                                        date: date,
                                                        serviceType: serviceType,
                                                        speaker: nil,
                                                        transcript: transcriptModel,
                                                        notes: notes,
                                                        summary: summaryModel,
                                                        transcriptionStatus: "complete",
                                                        summaryStatus: "processing",
                                                        id: sermonId
                                                    )

                                                    // Generate summary via service layer
                                                    // Create a temporary sermon object to avoid race condition
                                                    if let currentUser = AuthenticationManager.shared.currentUser {
                                                        let tempSermon = Sermon(
                                                            id: sermonId,
                                                            title: title,
                                                            audioFileURL: audioURL,
                                                            date: date,
                                                            serviceType: serviceType,
                                                            speaker: nil,
                                                            transcript: transcriptModel,
                                                            notes: notes,
                                                            summary: summaryModel,
                                                            transcriptionStatus: "complete",
                                                            summaryStatus: "processing",
                                                            userId: currentUser.id
                                                        )
                                                        sermonService.generateSummaryForSermon(tempSermon, transcript: text, serviceType: serviceType)
                                                    }

                                                    print("[MiniPlayer] Processing complete, refreshing sermon list")
                                                    sermonService.fetchSermons()

                                                case .failure(let error):
                                                    print("[MiniPlayer] Transcription failed: \(error)")
                                                    // Save recording for later processing
                                                    let noteService = NoteService(sessionId: currentRecordingSessionId)
                                                    let notes = noteService.currentNotes

                                                    sermonService.saveSermon(
                                                        title: title,
                                                        audioFileURL: audioURL,
                                                        date: date,
                                                        serviceType: serviceType,
                                                        transcript: nil,
                                                        notes: notes,
                                                        summary: nil,
                                                        transcriptionStatus: "pending",
                                                        summaryStatus: "pending",
                                                        id: UUID()
                                                    )
                                                }
                                            }
                                        }
                                    }

                                    // Clear recording state
                                    currentRecordingServiceType = nil
                                    // Delay clearing session to ensure notes are fully saved
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        let noteService = NoteService(sessionId: currentRecordingSessionId)
                                        noteService.clearSession()
                                        // Generate new session ID for next recording
                                        currentRecordingSessionId = UUID().uuidString
                                    }
                                }
                            }
                        }
                    )
                    .padding(.bottom, 20) // Bottom padding for no-footer screens
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .background(Color.adaptiveBackground)
            .customColorScheme(settingsService.appTheme.colorScheme)
            .overlay(alignment: .top) {
                // Trial expiring soon banner
                if let user = authManager.currentUser,
                   case .trialExpiringSoon(let daysLeft) = user.trialState {
                    TrialExpiringBanner(daysLeft: daysLeft) {
                        currentScreen = .settings
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay {
                // Trial expired modal
                if showTrialPrompt, let user = authManager.currentUser {
                    SubscriptionPromptModal(
                        trialState: user.trialState,
                        onDismiss: {
                            withAnimation {
                                showTrialPrompt = false
                                trialPromptManager.recordDismissal()
                            }
                        },
                        onSubscribe: {
                            withAnimation {
                                showTrialPrompt = false
                            }
                            currentScreen = .settings
                        }
                    )
                    .transition(.opacity)
                }

            }
            .onAppear {
                // Inject syncService into sermonService
                sermonService.setSyncService(syncService)

                // Initialize SummaryRetryService with model context
                SummaryRetryService.shared.setModelContext(modelContext)
                
                // Check for stuck processing summaries and recover them
                sermonService.recoverStuckSummaries()
                
                // Process any pending summaries in the queue
                SummaryRetryService.shared.processQueue()

                checkTrialStatus()

                // Trigger sync when app launches
                Task {
                    // Small delay to ensure UI is ready
                    try? await Task.sleep(nanoseconds: 500_000_000)

                    await syncService.syncAllData()
                }
            }
            .onChange(of: authManager.currentUser?.id) { _, newUserId in
                if newUserId != nil {
                    checkTrialStatus()

                    // Trigger sync when user changes (login/logout)
                    Task {
                        await syncService.syncAllData()
                    }
                }
            }
            .sheet(isPresented: $showServiceTypeModal) {
                VStack(spacing: 0) {
                    Text("Select Service Type")
                        .font(.headline)
                        .foregroundColor(.adaptivePrimaryText)
                        .padding()
                    
                    ForEach(["Sermon", "Bible Study", "Youth Group", "Conference"], id: \.self) { type in
                        Button(type) {
                            selectedServiceType = type
                            showServiceTypeModal = false
                            
                            Task {
                                // Check if user can start recording before navigating
                                let (canStart, reason) = await recordingService.canStartRecording()
                                if !canStart {
                                    print("[MainAppView] Cannot start recording: \(reason ?? "Unknown limit")")
                                    // TODO: Show alert with reason
                                    return
                                }
                                
                                // Start recording immediately
                                do {
                                    try await recordingService.startRecording(serviceType: type)
                                    print("[MainAppView] Recording started immediately for \(type)")

                                    // Log duration limit
                                    let maxDuration = await recordingService.getMaxRecordingDuration()
                                    if let maxDuration = maxDuration {
                                        let maxMinutes = Int(maxDuration / 60)
                                        print("[MainAppView] Recording limit: \(maxMinutes) minutes")
                                    }

                                    await MainActor.run {
                                        // Track the current recording service type for mini-player
                                        currentRecordingServiceType = type
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            currentScreen = .recording(serviceType: type)
                                        }
                                    }
                                } catch {
                                    print("[MainAppView] Failed to start recording: \(error)")
                                    // TODO: Show alert with error
                                    return
                                }
                            }
                        }
                        .font(.title3)
                        .foregroundColor(.adaptivePrimaryText)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.adaptiveSecondaryBackground)
                        .cornerRadius(8)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }
                .background(Color.adaptiveBackground)
                .presentationDetents([.medium])
            }
        }
    }
    }

    func tabForScreen(_ screen: AppScreen) -> FooterTab {
        switch screen {
        case .onboarding: return .home // Default, though footer won't show
        case .home: return .home
        case .recording: return .record
        case .sermonDetail, .sermons: return .home
        case .settings: return .home
        case .account: return .account
        }
    }

    func isRecordingScreen(_ screen: AppScreen) -> Bool {
        if case .recording = screen {
            return true
        }
        return false
    }
    
    private func isOnboardingScreen(_ screen: AppScreen) -> Bool {
        if case .onboarding = screen {
            return true
        }
        return false
    }
    
    private func isSettingsOrAccountScreen(_ screen: AppScreen) -> Bool {
        switch screen {
        case .settings, .account:
            return true
        default:
            return false
        }
    }

    private func checkTrialStatus() {
        guard let user = authManager.currentUser else { return }

        let trialState = user.trialState

        // Check if we should show the trial prompt
        if trialPromptManager.shouldShowPrompt(for: trialState) {
            withAnimation {
                showTrialPrompt = true
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Sermon.self, Note.self, Transcript.self, Summary.self, TranscriptSegment.self)
    MainAppView(modelContext: ModelContext(container))
} 
