import Foundation
import SwiftData

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var text: String
    var timestamp: TimeInterval // seconds into audio
    // Relationship to Sermon omitted for now due to cross-file reference issues

    init(id: UUID = UUID(), text: String, timestamp: TimeInterval) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }
} 