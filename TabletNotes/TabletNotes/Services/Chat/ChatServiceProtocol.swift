//
//  ChatServiceProtocol.swift
//  TabletNotes
//
//  Created by Claude Code
//

import Foundation
import Combine

protocol ChatServiceProtocol: ObservableObject {
    var messagesPublisher: AnyPublisher<[ChatMessage], Never> { get }
    var loadingPublisher: AnyPublisher<Bool, Never> { get }
    var errorPublisher: AnyPublisher<Error?, Never> { get }
    var suggestedQuestionsPublisher: AnyPublisher<[String], Never> { get }

    func sendMessage(_ message: String, for sermon: Sermon, user: User) async throws
    func generateSuggestedQuestions(for sermon: Sermon) async throws
    func loadMessages(for sermon: Sermon)
    func canSendMessage(user: User, sermon: Sermon) -> Bool
    func remainingQuestions(user: User, sermon: Sermon) -> Int?
}
