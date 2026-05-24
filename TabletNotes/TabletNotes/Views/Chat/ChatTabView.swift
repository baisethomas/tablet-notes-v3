import SwiftUI
import Combine

struct ChatTabView: View {
    var chatService: ChatService
    var authManager: AuthenticationManager
    let sermon: Sermon

    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var suggestedQuestions: [String] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                svEmptyState
            } else {
                svMessageList
            }
        }
        .background(Color.SV.surface)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.SV.onSurface.opacity(0.06))
                    .frame(height: 0.5)

                ChatInputView(
                    text: $messageText,
                    remainingQuestions: remainingQuestions,
                    isLoading: isLoading,
                    onSend: sendMessage
                )
                .padding(.top, 12)
            }
            .background(Color.SV.surface)
            .padding(.bottom, 90)
        }
        .onAppear {
            print("[ChatTabView] onAppear — messages: \(messages.count), questions: \(suggestedQuestions.count)")
            setupSubscriptions()
            chatService.loadMessages(for: sermon)
            if suggestedQuestions.isEmpty {
                Task { try? await chatService.generateSuggestedQuestions(for: sermon) }
            }
        }
    }

    // MARK: - Empty State

    private var svEmptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("INQUIRY & REFLECTION")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(Color.SV.onSurface.opacity(0.4))
                    .padding(.horizontal, 24)
                    .padding(.top, 36)
                    .padding(.bottom, 28)

                if suggestedQuestions.isEmpty {
                    // Generating questions
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color.SV.onSurface.opacity(0.3))
                            .scaleEffect(0.8)
                        Text("Preparing questions...")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.SV.onSurface.opacity(0.35))
                    }
                    .padding(.horizontal, 24)
                } else {
                    // Suggested questions as italic serif quotes
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(suggestedQuestions.enumerated()), id: \.element) { _, question in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                messageText = question
                            } label: {
                                Text("\u{201C}\(question)\u{201D}")
                                    .font(.system(size: 17, design: .serif))
                                    .italic()
                                    .foregroundStyle(Color.SV.onSurface.opacity(0.65))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 18)
                            }
                            .buttonStyle(.plain)

                            Rectangle()
                                .fill(Color.SV.onSurface.opacity(0.07))
                                .frame(height: 0.5)
                                .padding(.horizontal, 24)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Message List

    private var svMessageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let isUser = message.role == ChatRole.user.rawValue
                        let topPad: CGFloat = index == 0 ? 24 : (isUser ? 28 : 20)

                        MessageBubbleView(message: message)
                            .padding(.top, topPad)
                            .id(message.id)
                    }

                    // Thinking indicator while loading
                    if isLoading {
                        svThinkingIndicator
                            .padding(.top, 20)
                            .id("thinking")
                    }

                    Color.clear.frame(height: 80).id("bottom")
                }
            }
            .onAppear {
                scrollProxy = proxy
                scrollToBottom()
            }
            .onChange(of: messages.count) { scrollToBottom() }
            .onChange(of: isLoading) { if isLoading { scrollToThinking() } }
        }
    }

    private var svThinkingIndicator: some View {
        HStack(spacing: 6) {
            Text("Scholar is synthesizing deeper connections")
                .font(.system(size: 12))
                .foregroundStyle(Color.SV.onSurface.opacity(0.35))
                .italic()
            ThinkingDotsView()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    private var remainingQuestions: Int? {
        guard let user = authManager.currentUser else { return nil }
        return chatService.remainingQuestions(user: user, sermon: sermon)
    }

    private func setupSubscriptions() {
        chatService.messagesPublisher
            .receive(on: DispatchQueue.main)
            .sink { messages = $0 }
            .store(in: &cancellables)

        chatService.loadingPublisher
            .receive(on: DispatchQueue.main)
            .sink { isLoading = $0 }
            .store(in: &cancellables)

        chatService.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { error = $0 }
            .store(in: &cancellables)

        chatService.suggestedQuestionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { questions in
                print("[ChatTabView] Received \(questions.count) suggested questions")
                suggestedQuestions = questions
            }
            .store(in: &cancellables)
    }

    private func sendMessage() {
        guard let user = authManager.currentUser else { return }
        let message = messageText
        messageText = ""
        Task {
            do {
                try await chatService.sendMessage(message, for: sermon, user: user)
            } catch {
                print("[ChatTabView] Error sending message: \(error)")
            }
        }
    }

    private func scrollToBottom() {
        guard let last = messages.last else { return }
        withAnimation { scrollProxy?.scrollTo(last.id, anchor: .bottom) }
    }

    private func scrollToThinking() {
        withAnimation { scrollProxy?.scrollTo("thinking", anchor: .bottom) }
    }
}

// MARK: - Thinking Dots Animation

private struct ThinkingDotsView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.SV.onSurface.opacity(phase == i ? 0.5 : 0.2))
                    .frame(width: 4, height: 4)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                phase = (phase + 1) % 3
            }
        }
    }
}
