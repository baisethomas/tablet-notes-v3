import SwiftUI
import SwiftData
import Foundation
// If your project supports module imports, try:
// import TabletNotes.Models
// import TabletNotes.Views

@MainActor
class AppCoordinator: ObservableObject {
    enum Screen {
        case onboarding
        case home
        case recording(serviceType: String)
        case notes
        case summary(serviceType: String, transcript: Transcript?, audioFileURL: URL?)
        case sermonList
        case sermonDetail(sermon: Sermon)
        case settings
    }
    @Published private var screen: Screen = .onboarding
    @Published private var selectedServiceType: String? = nil
    @Published private var lastTranscript: Transcript? = nil
    @Published private var lastAudioFileURL: URL? = nil
    private let noteService = NoteService()
    private let sermonService: SermonService
    private let syncService: SyncService
    private let supabaseService: SupabaseService
    private let authManager: AuthenticationManager
    private let backgroundSyncManager: BackgroundSyncManager
    private let subscriptionService: SubscriptionService
    @Published private var hasSeenOnboarding = false
    private var onboardingReturnScreen: Screen = .home // Track where to return after onboarding

    init(modelContext: ModelContext) {
        // Initialize services
        self.authManager = AuthenticationManager.shared
        self.supabaseService = SupabaseService()
        
        // Create subscription service on main actor
        self.subscriptionService = SubscriptionService(
            authManager: AuthenticationManager.shared,
            supabaseService: supabaseService
        )
        self.syncService = SyncService(
            modelContext: modelContext,
            supabaseService: supabaseService,
            authService: authManager
        )
        self.sermonService = SermonService(
            modelContext: modelContext,
            authManager: authManager,
            syncService: syncService,
            subscriptionService: subscriptionService
        )
        self.backgroundSyncManager = BackgroundSyncManager(syncService: syncService)
        
        // Check if user has seen onboarding before
        if UserDefaults.standard.bool(forKey: "hasSeenOnboarding") {
            self.hasSeenOnboarding = true
            self.screen = .home
        }
    }

    @ViewBuilder
    func start() -> some View {
        switch screen {
        case .onboarding:
            OnboardingView(
                onComplete: {
                    // Only set hasSeenOnboarding to true if this is the first time
                    if !self.hasSeenOnboarding {
                        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                        self.hasSeenOnboarding = true
                    }
                    self.screen = self.onboardingReturnScreen
                },
                onSkip: {
                    // Only set hasSeenOnboarding to true if this is the first time
                    if !self.hasSeenOnboarding {
                        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                        self.hasSeenOnboarding = true
                    }
                    self.screen = self.onboardingReturnScreen
                }
            )
        case .home:
            VStack {
                ContentView(sermonService: sermonService, onStartRecording: { serviceType in
                    self.selectedServiceType = serviceType
                    self.screen = .recording(serviceType: serviceType)
                })
                Button("View Past Sermons") {
                    self.screen = .sermonList
                }
                .padding(.top, 24)
            }
        case .recording(let serviceType):
            RecordingView(serviceType: serviceType, noteService: NoteService(sessionId: UUID().uuidString), onNext: { sermon in
                self.screen = .sermonDetail(sermon: sermon)
            }, sermonService: sermonService)
        case .notes:
            NotesView(noteService: noteService, onNext: {
                let transcript = self.lastTranscript
                let audioFileURL = self.lastAudioFileURL
                self.screen = .summary(serviceType: self.selectedServiceType ?? "", transcript: transcript, audioFileURL: audioFileURL)
            })
        case .summary(let serviceType, let transcript, let audioFileURL):
            SummaryView(serviceType: serviceType, transcript: transcript, audioFileURL: audioFileURL, sermonService: sermonService, noteService: noteService, onNext: { self.screen = .settings })
        case .sermonList:
            SermonListView(sermonService: sermonService, onSermonSelected: { sermon in
                self.screen = .sermonDetail(sermon: sermon)
            })
        case .sermonDetail(let sermon):
            SermonDetailView(sermonService: sermonService, sermonID: sermon.id, onBack: { self.screen = .sermonList })
        case .settings:
            SettingsView(
                onNext: { self.screen = .home },
                onShowOnboarding: { 
                    self.onboardingReturnScreen = .settings
                    self.screen = .onboarding 
                },
                sermonService: sermonService
            )
        }
    }
}
