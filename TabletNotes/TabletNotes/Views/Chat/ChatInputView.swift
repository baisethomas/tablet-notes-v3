import SwiftUI

struct ChatInputView: View {
    @Binding var text: String
    let remainingQuestions: Int?
    let isLoading: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            // Remaining questions (free tier)
            if let remaining = remainingQuestions {
                HStack {
                    Text("\(remaining) question\(remaining == 1 ? "" : "s") remaining")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.35))
                    Spacer()
                    if remaining == 0 {
                        Text("Upgrade for unlimited")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.SV.primary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }

            // Input row
            HStack(alignment: .bottom, spacing: 14) {
                // Underline-style text field
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.SV.tertiary.opacity(0.75))
                            .padding(.top, 2)

                        TextField("Ask about this sermon...", text: $text, axis: .vertical)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.SV.onSurface)
                            .textFieldStyle(.plain)
                            .lineLimit(1...4)
                            .focused($isFocused)
                            .disabled(isLoading)
                    }
                    .padding(.bottom, 9)

                    // Underline — transitions to primary on focus
                    Rectangle()
                        .fill(isFocused ? Color.SV.primary : Color.SV.onSurface.opacity(0.15))
                        .frame(height: 1)
                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                }

                // Send button
                Button(action: onSend) {
                    ZStack {
                        Circle()
                            .fill(canSend ? Color.SV.primary : Color.SV.onSurface.opacity(0.07))
                            .frame(width: 36, height: 36)

                        if isLoading {
                            ProgressView()
                                .tint(Color.SV.onSurface.opacity(0.35))
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(canSend ? .white : Color.SV.onSurface.opacity(0.25))
                        }
                    }
                }
                .disabled(!canSend)
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: canSend)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 4)
        }
        .background(Color.SV.surface)
    }
}
