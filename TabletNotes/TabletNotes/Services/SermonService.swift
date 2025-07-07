import Foundation
import SwiftData

extension Sermon: Identifiable {}
extension Transcript: Identifiable {}
extension Note: Identifiable {}
extension Summary: Identifiable {}

enum SortOption: String, CaseIterable {
    case newest = "Newest First"
    case oldest = "Oldest First"
}

class SermonService: ObservableObject {
    private let modelContext: ModelContext
    @Published private(set) var sermons: [Sermon] = []
    @Published private(set) var filteredSermons: [Sermon] = []
    @Published var searchText: String = "" {
        didSet {
            applyFilters()
        }
    }
    @Published var sortOption: SortOption = .newest {
        didSet {
            applyFilters()
        }
    }
    @Published var showArchivedSermons: Bool = false {
        didSet {
            applyFilters()
        }
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchSermons()
    }

    func saveSermon(title: String, audioFileURL: URL, date: Date, serviceType: String, speaker: String? = nil, transcript: Transcript?, notes: [Note], summary: Summary?, transcriptionStatus: String = "processing", summaryStatus: String = "processing", isArchived: Bool = false, id: UUID? = nil) {
        print("[SermonService] saveSermon called with title: \(title), date: \(date), serviceType: \(serviceType)")
        let sermonID = id ?? UUID()
        if let existing = sermons.first(where: { $0.id == sermonID }) {
            // Update existing sermon
            existing.title = title
            existing.audioFileURL = audioFileURL
            existing.date = date
            existing.serviceType = serviceType
            existing.speaker = speaker
            existing.transcript = transcript
            existing.notes = notes
            existing.summary = summary
            existing.transcriptionStatus = transcriptionStatus
            existing.summaryStatus = summaryStatus
            existing.isArchived = isArchived
            print("[DEBUG] saveSermon: updated existing sermon \(existing.id)")
        } else {
            // Insert new sermon
            let sermon = Sermon(
                id: sermonID,
                title: title,
                audioFileURL: audioFileURL,
                date: date,
                serviceType: serviceType,
                speaker: speaker,
                transcript: transcript,
                notes: notes,
                summary: summary,
                syncStatus: "localOnly",
                transcriptionStatus: transcriptionStatus,
                summaryStatus: summaryStatus,
                isArchived: isArchived
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
            applyFilters()
        }
        else {
            print("[SermonService] fetch failed.")
        }
    }
    
    private func applyFilters() {
        var filtered = sermons
        
        // Apply archive filter
        if !showArchivedSermons {
            filtered = filtered.filter { !$0.isArchived }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { sermon in
                sermon.title.localizedCaseInsensitiveContains(searchText) ||
                sermon.serviceType.localizedCaseInsensitiveContains(searchText) ||
                (sermon.speaker?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (sermon.transcript?.text.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (sermon.summary?.text.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Apply sort order
        switch sortOption {
        case .newest:
            filtered = filtered.sorted { $0.date > $1.date }
        case .oldest:
            filtered = filtered.sorted { $0.date < $1.date }
        }
        
        filteredSermons = filtered
    }
    
    func clearSearch() {
        searchText = ""
    }
    
    func archiveSermon(_ sermon: Sermon) {
        sermon.isArchived = true
        try? modelContext.save()
        applyFilters()
    }
    
    func unarchiveSermon(_ sermon: Sermon) {
        sermon.isArchived = false
        try? modelContext.save()
        applyFilters()
    }
    
    func toggleSermonArchiveStatus(_ sermon: Sermon) {
        sermon.isArchived.toggle()
        try? modelContext.save()
        applyFilters()
    }

    func deleteSermon(_ sermon: Sermon) {
        if let index = sermons.firstIndex(where: { $0.id == sermon.id }) {
            let sermonToDelete = sermons[index]
            sermons.remove(at: index)
            modelContext.delete(sermonToDelete)
            try? modelContext.save()
            applyFilters()
        } else {
            modelContext.delete(sermon)
            try? modelContext.save()
            fetchSermons()
        }
    }
} 