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

    func saveSermon(title: String, audioFileURL: URL, date: Date, serviceType: String, transcript: Transcript?, notes: [Note], summary: Summary?, transcriptionStatus: String = "processing", summaryStatus: String = "processing", id: UUID? = nil) {
        print("[SermonService] saveSermon called with title: \(title), date: \(date), serviceType: \(serviceType)")
        let sermonID = id ?? UUID()
        if let existing = sermons.first(where: { $0.id == sermonID }) {
            // Update existing sermon
            existing.title = title
            existing.audioFileURL = audioFileURL
            existing.date = date
            existing.serviceType = serviceType
            existing.transcript = transcript
            existing.notes = notes
            existing.summary = summary
            existing.transcriptionStatus = transcriptionStatus
            existing.summaryStatus = summaryStatus
            print("[DEBUG] saveSermon: updated existing sermon \(existing.id)")
        } else {
            // Insert new sermon
            let sermon = Sermon(
                id: sermonID,
                title: title,
                audioFileURL: audioFileURL,
                date: date,
                serviceType: serviceType,
                transcript: transcript,
                notes: notes,
                summary: summary,
                syncStatus: "localOnly",
                transcriptionStatus: transcriptionStatus,
                summaryStatus: summaryStatus
            )
            modelContext.insert(sermon)
            print("[DEBUG] saveSermon: inserted new sermon \(sermon.id)")
        }
        try? modelContext.save()
        print("[SermonService] Sermon inserted/updated and modelContext saved.")
        fetchSermons()
    }

    func fetchSermons() {
        print("[SermonService] fetchSermons called.")
        let fetchDescriptor = FetchDescriptor<Sermon>()
        if let results = try? modelContext.fetch(fetchDescriptor) {
            sermons = results
            print("[SermonService] sermons fetched: \(sermons.map { $0.title })")
        }
        else {
            print("[SermonService] fetch failed.")
        }
    }

    func deleteSermon(_ sermon: Sermon) {
        if let index = sermons.firstIndex(where: { $0.id == sermon.id }) {
            let sermonToDelete = sermons[index]
            sermons.remove(at: index)
            modelContext.delete(sermonToDelete)
            try? modelContext.save()
        } else {
            modelContext.delete(sermon)
            try? modelContext.save()
            fetchSermons()
        }
    }
} 