export interface DataModel {
  name: string;
  code: string;
}

export const dataModels: DataModel[] = [
  {
    name: "Sermon",
    code: `struct Sermon {
    var id: UUID
    var title: String
    var recordingDate: Date
    var serviceType: ServiceType
    var duration: TimeInterval
    var audioFileURL: URL
    var transcriptionStatus: TranscriptionStatus
    var summaryStatus: SummaryStatus
    var syncStatus: SyncStatus
    var isPaid: Bool
}`
  },
  {
    name: "Transcription",
    code: `struct Transcription {
    var id: UUID
    var sermonId: UUID
    var text: String
    var segments: [TranscriptionSegment]
    var lastModified: Date
}`
  },
  {
    name: "TranscriptionSegment",
    code: `struct TranscriptionSegment {
    var id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var confidence: Float
}`
  },
  {
    name: "Note",
    code: `struct Note {
    var id: UUID
    var sermonId: UUID
    var text: String
    var timestamp: TimeInterval
    var lastModified: Date
    var isHighlighted: Bool
    var isBookmarked: Bool
}`
  },
  {
    name: "Summary",
    code: `struct Summary {
    var id: UUID
    var sermonId: UUID
    var text: String
    var format: SummaryFormat
    var createdAt: Date
    var retryCount: Int
}`
  },
  {
    name: "Enums",
    code: `enum ServiceType: String, Codable {
    case sundayService
    case bibleStudy
    case midweek
    case conference
    case guestSpeaker
    case other
}

enum TranscriptionStatus: String, Codable {
    case notStarted
    case inProgress
    case completed
    case failed
}

enum SummaryStatus: String, Codable {
    case notStarted
    case queued
    case inProgress
    case completed
    case failed
}

enum SyncStatus: String, Codable {
    case notSynced
    case syncing
    case synced
    case failed
}

enum SummaryFormat: String, Codable {
    case devotional
    case bulletPoint
    case theological
}`
  }
];
