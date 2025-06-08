import Foundation
import SwiftData

@Model
final class Summary {
    @Attribute(.unique) var id: UUID
    var text: String
    var type: String // e.g., devotional, bullet, theological
    var status: String // e.g., pending, complete, failed

    init(id: UUID = UUID(), text: String, type: String, status: String) {
        self.id = id
        self.text = text
        self.type = type
        self.status = status
    }
} 