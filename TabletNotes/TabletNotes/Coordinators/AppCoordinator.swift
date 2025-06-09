import SwiftUI
import SwiftData
import Foundation
// If your project supports module imports, try:
// import TabletNotes.Models
// import TabletNotes.Views

class AppCoordinator: ObservableObject {
    enum Screen {
        case home
        case recording(serviceType: String)
        case notes
        case summary(serviceType: String, transcript: Transcript?, audioFileURL: URL?)
        case sermonList
        case sermonDetail(sermon: Sermon)
        case settings
    }
    @Published private var screen: Screen = .home
    @Published private var selectedServiceType: String? = nil
    @Published private var lastTranscript: Transcript? = nil
    @Published private var lastAudioFileURL: URL? = nil
    private let noteService = NoteService()
    private let sermonService: SermonService

    init(modelContext: ModelContext) {
        self.sermonService = SermonService(modelContext: modelContext)
    }

    @ViewBuilder
    func start() -> some View {
        switch screen {
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
            RecordingView(serviceType: serviceType, noteService: noteService, onNext: { sermon in
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
            SermonListView(sermonService: sermonService, onBack: { self.screen = .home }) { sermon in
                self.screen = .sermonDetail(sermon: sermon)
            }
        case .sermonDetail(let sermon):
            SermonDetailView(sermonService: sermonService, sermonID: sermon.id, onBack: { self.screen = .sermonList })
        case .settings:
            SettingsView(onNext: { self.screen = .home })
        }
    }
}
