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
    
    private func cleanMarkdown(_ text: String) -> String {
        var cleaned = text
        
        // Remove markdown headers (# ## ###) - process line by line
        let lines = cleaned.components(separatedBy: .newlines)
        cleaned = lines.map { line in
            line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
        }.joined(separator: "\n")
        
        // Remove bold (**text** or __text__) - handle multiline
        cleaned = cleaned.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"__([^_]+)__"#, with: "$1", options: .regularExpression)
        
        // Remove italic (*text* or _text_) - be careful not to match bold
        cleaned = cleaned.replacingOccurrences(of: #"(?<!\*)\*([^*]+)\*(?!\*)"#, with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?<!_)_([^_]+)_(?!_)"#, with: "$1", options: .regularExpression)
        
        // Process numbered lists and bullet points line by line
        let processedLines = cleaned.components(separatedBy: .newlines).map { line in
            var processed = line
            // Convert numbered lists (1. 2. 3.) - keep the number and period
            processed = processed.replacingOccurrences(of: #"^(\d+)\.\s+"#, with: "$1. ", options: .regularExpression)
            // Remove bullet points (* - +) but keep the content
            processed = processed.replacingOccurrences(of: #"^[\*\-\+]\s+"#, with: "", options: .regularExpression)
            return processed
        }
        cleaned = processedLines.joined(separator: "\n")
        
        // Remove code blocks (```code```)
        cleaned = cleaned.replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)
        
        // Remove inline code (`code`)
        cleaned = cleaned.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        
        // Remove links [text](url) - keep just the text
        cleaned = cleaned.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        
        // Remove strikethrough (~~text~~)
        cleaned = cleaned.replacingOccurrences(of: #"~~([^~]+)~~"#, with: "$1", options: .regularExpression)
        
        // Clean up extra whitespace (multiple newlines to double newline, multiple spaces to single space)
        cleaned = cleaned.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        
        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
}
