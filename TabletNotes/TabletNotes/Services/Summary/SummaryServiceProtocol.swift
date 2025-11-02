import Foundation
import Combine

protocol SummaryServiceProtocol {
    var titlePublisher: AnyPublisher<String?, Never> { get }
    var summaryPublisher: AnyPublisher<String?, Never> { get }
    var statusPublisher: AnyPublisher<String, Never> { get } // e.g., pending, complete, failed
    var errorPublisher: AnyPublisher<Error?, Never> { get }
    func generateSummary(for transcript: String, type: String)
    func retrySummary()
} 