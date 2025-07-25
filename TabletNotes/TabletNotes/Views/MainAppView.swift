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
    @StateObject private var sermonService: SermonService
    @StateObject private var settingsService = SettingsService.shared
    @StateObject private var recordingService = RecordingService()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        _sermonService = StateObject(wrappedValue: SermonService(modelContext: modelContext))
        
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
                            // Clear the recording session notes after successful save
                            let noteService = NoteService(sessionId: currentRecordingSessionId)
                            noteService.clearSession()
                            // Generate new session ID for next recording
                            currentRecordingSessionId = UUID().uuidString
                            currentScreen = .sermons // Go to the list after recording
                        },
                        sermonService: sermonService,
                        recordingService: recordingService
                    ))
                case .sermonDetail(let sermon):
                    AnyView(SermonDetailView(
                        sermonService: sermonService,
                        sermonID: sermon.id,
                        onBack: { currentScreen = .sermons }
                    ))
                case .sermons:
                    AnyView(SermonListView(
                        sermonService: sermonService,
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
                
                // Only show footer when not in onboarding, settings, or account
                if !isOnboardingScreen(currentScreen) && !isSettingsOrAccountScreen(currentScreen) {
                    FooterView(
                        selectedTab: tabForScreen(currentScreen),
                        onHome: { currentScreen = .home },
                        onRecord: { showServiceTypeModal = true },
                        onAccount: { currentScreen = .account }
                    )
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .background(Color.adaptiveBackground)
            .customColorScheme(settingsService.appTheme.colorScheme)
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
}

#Preview {
    let container = try! ModelContainer(for: Sermon.self, Note.self, Transcript.self, Summary.self, TranscriptSegment.self)
    MainAppView(modelContext: ModelContext(container))
} 
