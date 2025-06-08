import Foundation
import SwiftData

extension Sermon: Identifiable {}
extension Transcript: Identifiable {}
extension Note: Identifiable {}
extension Summary: Identifiable {}

class SermonService: ObservableObject {
    private let modelContext: ModelContext
    @Published private(set) var sermons: [Sermon] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchSermons()
    }

    func saveSermon(title: String, audioFileURL: URL, date: Date, serviceType: String, transcript: Transcript?, notes: [Note], summary: Summary?) {
        let sermon = Sermon(title: title, audioFileURL: audioFileURL, date: date, serviceType: serviceType, transcript: transcript, notes: notes, summary: summary)
        modelContext.insert(sermon)
        try? modelContext.save()
        fetchSermons()
    }

    func fetchSermons() {
        let fetchDescriptor = FetchDescriptor<Sermon>()
        if let results = try? modelContext.fetch(fetchDescriptor) {
            sermons = results
        }
    }
} 