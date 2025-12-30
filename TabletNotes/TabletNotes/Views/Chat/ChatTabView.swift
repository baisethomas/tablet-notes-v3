//
//  ChatTabView.swift
//  TabletNotes
//
//  Created by Claude Code
//

import SwiftUI
import Combine

struct ChatTabView: View {
    @ObservedObject var chatService: ChatService
    @ObservedObject var authManager: AuthenticationManager
    let sermon: Sermon

    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var suggestedQuestions: [String] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Main content area
                VStack(spacing: 0) {
                    if messages.isEmpty {
                        emptyStateView
                    } else {
                        messageListView
                    }
                }
                .padding(.bottom, 145) // Space for input area + tab bar

                // Input area fixed at bottom
                VStack(spacing: 0) {
                    Divider()

                    ChatInputView(
                        text: $messageText,
                        remainingQuestions: remainingQuestions,
                        isLoading: isLoading,
                        onSend: sendMessage
                    )
                }
                .background(Color.adaptiveBackground)
                .padding(.bottom, geometry.safeAreaInsets.bottom + 45) // Tab bar height
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            setupSubscriptions()
            chatService.loadMessages(for: sermon)

            // Generate suggestions if first time
            if messages.isEmpty {
                Task {
                    try? await chatService.generateSuggestedQuestions(for: sermon)
                }
            }
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 60)

                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.adaptiveAccent)

                    VStack(spacing: 8) {
                        Text("Ask Questions About This Sermon")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.adaptivePrimaryText)

                        Text("Get insights from AI powered by the sermon's transcript and summary")
                            .font(.subheadline)
                            .foregroundColor(.adaptiveSecondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }

                if !suggestedQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Suggested Questions")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.adaptiveSecondaryText)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        VStack(spacing: 12) {
                            ForEach(suggestedQuestions, id: \.self) { question in
                                Button(action: {
                                    messageText = question
                                }) {
                                    HStack {
                                        Text(question)
                                            .font(.subheadline)
                                            .foregroundColor(.adaptivePrimaryText)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: "arrow.up.circle.fill")
                                            .foregroundColor(.adaptiveAccent)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color.adaptiveCardBackground)
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                Spacer()
                    .frame(height: 20)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Message List
    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 16)
            }
            .onAppear {
                scrollProxy = proxy
                scrollToBottom()
            }
            .onChange(of: messages.count) {
                scrollToBottom()
            }
        }
    }

    // MARK: - Helpers
    private var remainingQuestions: Int? {
        guard let user = authManager.currentUser else { return nil }
        return chatService.remainingQuestions(user: user, sermon: sermon)
    }

    private func setupSubscriptions() {
        chatService.messagesPublisher
            .receive(on: DispatchQueue.main)
            .sink { newMessages in
                messages = newMessages
            }
            .store(in: &cancellables)

        chatService.loadingPublisher
            .receive(on: DispatchQueue.main)
            .sink { loading in
                isLoading = loading
            }
            .store(in: &cancellables)

        chatService.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { newError in
                error = newError
            }
            .store(in: &cancellables)

        chatService.suggestedQuestionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { questions in
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
                // Show error to user
            }
        }
    }

    private func scrollToBottom() {
        guard let lastMessage = messages.last else { return }
        withAnimation {
            scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}
