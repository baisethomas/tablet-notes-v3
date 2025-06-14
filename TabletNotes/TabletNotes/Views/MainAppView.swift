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
    case home
    case recording(serviceType: String?)
    case sermonDetail(sermon: Sermon)
    case sermons
}

struct MainAppView: View {
    let modelContext: ModelContext
    @State private var currentScreen: AppScreen = .home
    @State private var showServiceTypeModal = false
    @State private var selectedServiceType: String? = nil
    @State private var lastCreatedSermon: Sermon? = nil
    @StateObject private var sermonService: SermonService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        _sermonService = StateObject(wrappedValue: SermonService(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                switch currentScreen {
                case .home:
                    AnyView(SermonListView(
                        sermonService: sermonService,
                        onBack: nil,
                        onSermonTap: { sermon in
                            currentScreen = .sermonDetail(sermon: sermon)
                        }
                    ))
                case .recording(let serviceType):
                    AnyView(RecordingView(
                        serviceType: serviceType ?? "Sermon",
                        noteService: NoteService(),
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
                        onBack: { currentScreen = .home },
                        onSermonTap: { sermon in
                            currentScreen = .sermonDetail(sermon: sermon)
                        }
                    ))
                }
                FooterView(
                    selectedTab: tabForScreen(currentScreen),
                    onHome: { currentScreen = .home },
                    onRecord: { showServiceTypeModal = true },
                    onAccount: { /* handle account */ }
                )
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

    func tabForScreen(_ screen: AppScreen) -> FooterTab {
        switch screen {
        case .home: return .home
        case .recording: return .record
        case .sermonDetail, .sermons: return .home
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Sermon.self, Note.self, Transcript.self, Summary.self, TranscriptSegment.self)
    MainAppView(modelContext: ModelContext(container))
} 
