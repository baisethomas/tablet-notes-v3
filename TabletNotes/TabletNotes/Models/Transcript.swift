import Foundation
import SwiftData

@Model
final class Transcript {
    @Attribute(.unique) var id: UUID
    var text: String
    @Relationship(deleteRule: .cascade) var segments: [TranscriptSegment]

    // Sync metadata
    var remoteId: String?
    var updatedAt: Date?
    var needsSync: Bool = false

    init(id: UUID = UUID(), text: String, segments: [TranscriptSegment] = [], remoteId: String? = nil, updatedAt: Date? = Date(), needsSync: Bool = false) {
        self.id = id
        self.text = text
        self.segments = segments
        self.remoteId = remoteId
        self.updatedAt = updatedAt
        self.needsSync = needsSync
    }
}

@Model
final class TranscriptSegment: Identifiable {
    @Attribute(.unique) var id: UUID
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval

    init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
} 