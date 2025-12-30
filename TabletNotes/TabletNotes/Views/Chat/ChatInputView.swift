//
//  ChatInputView.swift
//  TabletNotes
//
//  Created by Claude Code
//

import SwiftUI

struct ChatInputView: View {
    @Binding var text: String
    let remainingQuestions: Int?
    let isLoading: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Remaining questions indicator (for free users)
            if let remaining = remainingQuestions {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundColor(.adaptiveSecondaryText)

                    Text("\(remaining) question\(remaining == 1 ? "" : "s") remaining")
                        .font(.caption)
                        .foregroundColor(.adaptiveSecondaryText)

                    Spacer()

                    if remaining == 0 {
                        Text("Upgrade for unlimited")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.adaptiveAccent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Input field
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.adaptiveAccent)
                    
                    TextField("Ask a question", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .focused($isFocused)
                        .disabled(isLoading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.adaptiveInputBackground)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.adaptiveBorder.opacity(0.3), lineWidth: 1)
                )

                Button(action: onSend) {
                    ZStack {
                        Circle()
                            .fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading ?
                                  Color.adaptiveInputBackground :
                                  Color.adaptiveInputBackground)
                            .frame(width: 44, height: 44)

                        if isLoading {
                            ProgressView()
                                .tint(.adaptiveSecondaryText)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.adaptiveSecondaryText)
                        }
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color.adaptiveBackground)
    }
}
