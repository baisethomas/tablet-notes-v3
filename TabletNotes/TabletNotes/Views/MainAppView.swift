import SwiftUI
import SwiftData
import Foundation
import Combine

// Centralized navigation enum
enum AppScreen {
    case home
    case recording(serviceType: String?)
    case sermonDetail(sermon: Sermon)
    case sermons
}

struct MainAppView: View {
    @State private var currentScreen: AppScreen = .home
    @State private var showServiceTypeModal = false
    @State private var selectedServiceType: String? = nil
    @State private var lastCreatedSermon: Sermon? = nil
    @State private var modelContext: ModelContext = {
        do {
            let container = try ModelContainer(for: Sermon.self, Note.self, Transcript.self, Summary.self, TranscriptSegment.self)
            return ModelContext(container)
        } catch {
            print("Failed to load model container: \(error)")
            fatalError("Failed to load model container: \(error)")
        }
    }()

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch currentScreen {
                case .home:
                    AnyView(ContentView(
                        onStartRecording: { _ in showServiceTypeModal = true },
                        onViewPastSermons: { currentScreen = .sermons }
                    ))
                case .recording(let serviceType):
                    AnyView(RecordingView(
                        serviceType: serviceType ?? "Sermon",
                        noteService: NoteService(),
                        onNext: { sermon in
                            modelContext.insert(sermon)
                            lastCreatedSermon = sermon
                            currentScreen = .home
                        }
                    ))
                case .sermonDetail(let sermon):
                    AnyView(SermonDetailView(
                        sermon: sermon,
                        onBack: { currentScreen = .home }
                    ))
                case .sermons:
                    AnyView(SermonListView(
                        sermonService: SermonService(modelContext: modelContext),
                        onBack: { currentScreen = .home },
                        onSermonTap: { sermon in
                            currentScreen = .sermonDetail(sermon: sermon)
                        }
                    ))
                }
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

    func tabForScreen(_ screen: AppScreen) -> FooterTab {
        switch screen {
        case .home: return .home
        case .recording: return .record
        case .sermonDetail, .sermons: return .home
        }
    }
}

#Preview {
    MainAppView()
} 