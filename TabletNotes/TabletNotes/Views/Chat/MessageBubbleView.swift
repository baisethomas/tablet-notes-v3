import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == ChatRole.user.rawValue }

    var body: some View {
        if isUser {
            svUserMessage
        } else {
            svAIResponse
        }
    }

    // MARK: - User Message

    private var svUserMessage: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 5) {
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.SV.primary)
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))

                Text(formatTimestamp(message.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.3))
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - AI Response

    private var svAIResponse: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCHOLAR ANALYSIS")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Color.SV.onSurface.opacity(0.35))

            Text(cleanMarkdown(message.content))
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(Color.SV.onSurface)
                .lineSpacing(7)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(formatTimestamp(message.timestamp))
                .font(.system(size: 10))
                .foregroundStyle(Color.SV.onSurface.opacity(0.3))
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func cleanMarkdown(_ text: String) -> String {
        MarkdownCleaner.clean(text)
    }
}
