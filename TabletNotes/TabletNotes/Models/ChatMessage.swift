//
//  ChatMessage.swift
//  TabletNotes
//
//  Created by Claude Code
//

import Foundation
import SwiftData

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var role: String // "user" or "assistant"
    var content: String
    var timestamp: Date
    var sermon: Sermon?

    // Usage tracking for limits - only user questions count toward limit
    var countsTowardLimit: Bool

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        timestamp: Date = Date(),
        countsTowardLimit: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.countsTowardLimit = countsTowardLimit
    }
}

// Helper enum for type safety
enum ChatRole: String {
    case user = "user"
    case assistant = "assistant"

    var displayName: String {
        switch self {
        case .user: return "You"
        case .assistant: return "AI Assistant"
        }
    }
}
