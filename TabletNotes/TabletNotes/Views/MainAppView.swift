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
    @StateObject private var sermonService: SermonService

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
                        }
                    ))
                case .recording(let serviceType):
                    AnyView(RecordingView(
                        serviceType: serviceType ?? "Sermon",
                        noteService: NoteService(sessionId: UUID().uuidString),
                        onNext: { sermon in
                            sermonService.fetchSermons() // Refresh the list
                            lastCreatedSermon = sermon
                            currentScreen = .sermons // Go to the list after recording
                        },
                        sermonService: sermonService
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
                
                // Only show footer when not in onboarding
                if !isOnboardingScreen(currentScreen) {
                    FooterView(
                        selectedTab: tabForScreen(currentScreen),
                        onHome: { currentScreen = .home },
                        onRecord: { showServiceTypeModal = true },
                        onAccount: { currentScreen = .account }
                    )
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .sheet(isPresented: $showServiceTypeModal) {
                VStack(spacing: 0) {
                    Text("Select Service Type")
                        .font(.headline)
                        .padding()
                    ForEach(["Sermon", "Bible Study", "Youth Group", "Conference"], id: \.self) { type in
                        Button(type) {
                            selectedServiceType = type
                            showServiceTypeModal = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                currentScreen = .recording(serviceType: type)
                            }
                        }
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }
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
}

#Preview {
    let container = try! ModelContainer(for: Sermon.self, Note.self, Transcript.self, Summary.self, TranscriptSegment.self)
    MainAppView(modelContext: ModelContext(container))
} 
