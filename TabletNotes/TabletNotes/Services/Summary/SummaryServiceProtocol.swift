import Foundation

struct SummaryGenerationResult: Sendable {
    let title: String?
    let summary: String
}

protocol SummaryServiceProtocol: Sendable {
    func generateSummaryResult(for transcript: String, type: String) async throws -> SummaryGenerationResult
    func generateBasicSummaryResult(for transcript: String, type: String) -> SummaryGenerationResult
    func userFacingMessage(for error: Error) -> String
}
