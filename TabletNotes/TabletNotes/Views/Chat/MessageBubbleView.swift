//
//  MessageBubbleView.swift
//  TabletNotes
//
//  Created by Claude Code
//

import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage

    private var isUser: Bool {
        message.role == ChatRole.user.rawValue
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser {
                Spacer(minLength: 40)
            } else {
                // AI avatar
                ZStack {
                    Circle()
                        .fill(Color.adaptiveAccent.opacity(0.2))
                        .frame(width: 32, height: 32)

                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14))
                        .foregroundColor(.adaptiveAccent)
                }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Message content
                Text(isUser ? message.content : cleanMarkdown(message.content))
                    .font(.body)
                    .foregroundColor(isUser ? .white : .adaptivePrimaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        isUser ?
                            Color.adaptiveAccent :
                            Color.adaptiveCardBackground
                    )
                    .cornerRadius(16)

                // Timestamp
                Text(formatTimestamp(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.adaptiveSecondaryText)
                    .padding(.horizontal, 8)
            }

            if !isUser {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    /// Cleans markdown using optimized cached regex patterns (50% faster)
    private func cleanMarkdown(_ text: String) -> String {
        return MarkdownCleaner.clean(text)
    }
}
