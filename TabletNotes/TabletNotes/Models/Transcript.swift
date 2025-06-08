import Foundation
import SwiftData

@Model
final class Transcript {
    var text: String
    @Relationship(deleteRule: .cascade) var segments: [TranscriptSegment]

    init(text: String, segments: [TranscriptSegment] = []) {
        self.text = text
        self.segments = segments
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