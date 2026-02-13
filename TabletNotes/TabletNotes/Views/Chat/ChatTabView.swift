//
//  ChatTabView.swift
//  TabletNotes
//
//  Created by Claude Code
//

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
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Main content area
                if messages.isEmpty {
                    emptyStateView
                } else {
                    messageListView
                }
            }
            .background(Color.adaptiveBackground)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    
                    ChatInputView(
                        text: $messageText,
                        remainingQuestions: remainingQuestions,
                        isLoading: isLoading,
                        onSend: sendMessage
                    )
                    .padding(.top, 12)
                }
                .background(Color.adaptiveBackground)
                .padding(.bottom, 45) // Tab bar height
            }
        }
        .background(Color.adaptiveBackground)
        .onAppear {
            print("[ChatTabView] onAppear - messages.count: \(messages.count), suggestedQuestions.count: \(suggestedQuestions.count)")
            setupSubscriptions()
            chatService.loadMessages(for: sermon)

            // Generate suggestions if we don't have any yet
            if suggestedQuestions.isEmpty {
                print("[ChatTabView] Triggering question generation")
                Task {
                    try? await chatService.generateSuggestedQuestions(for: sermon)
                }
            } else {
                print("[ChatTabView] Already have \(suggestedQuestions.count) questions, skipping generation")
            }
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                VStack(spacing: 8) {
                    Text("Ask Questions About This Sermon")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.adaptivePrimaryText)
                        .multilineTextAlignment(.center)

                    Text("Get answers from AI Chat")
                        .font(.subheadline)
                        .foregroundColor(.adaptiveSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 24)
                .padding(.bottom, 32)

                if !suggestedQuestions.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(suggestedQuestions, id: \.self) { question in
                            Button(action: {
                                messageText = question
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 14))
                                        .foregroundColor(.adaptiveAccent)
                                    
                                    Text(question)
                                        .font(.subheadline)
                                        .foregroundColor(.adaptivePrimaryText)
                                        .multilineTextAlignment(.leading)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.adaptiveInputBackground)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.adaptiveBorder.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .onAppear {
                        print("[ChatTabView] Suggested questions section appearing with \(suggestedQuestions.count) questions")
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
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.bottom, 80) // Padding to prevent content behind input
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom()
                }
                .onChange(of: messages.count) {
                    scrollToBottom()
                }
                
                // Fully opaque gradient fade effect at bottom
                VStack {
                    Spacer()
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.adaptiveBackground.opacity(0), location: 0.0),
                            .init(color: Color.adaptiveBackground.opacity(0.4), location: 0.4),
                            .init(color: Color.adaptiveBackground.opacity(0.8), location: 0.7),
                            .init(color: Color.adaptiveBackground, location: 0.85),
                            .init(color: Color.adaptiveBackground, location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                    .allowsHitTesting(false)
                }
            }
            .background(Color.adaptiveBackground)
            .clipped()
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
                print("[ChatTabView] Received \(questions.count) suggested questions from publisher")
                suggestedQuestions = questions
                print("[ChatTabView] suggestedQuestions state updated, isEmpty: \(suggestedQuestions.isEmpty)")
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
