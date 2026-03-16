import Foundation
import SwiftData

enum ProcessingJobKind: String, Codable, CaseIterable {
    case transcription
    case summary
}

enum ProcessingJobStatus: String, Codable, CaseIterable {
    case queued
    case running
    case failed
    case complete
}

@Model
final class ProcessingJob {
    @Attribute(.unique) var id: UUID
    var sermonId: UUID
    var kindRawValue: String
    var statusRawValue: String
    var attemptCount: Int
    var createdAt: Date
    var updatedAt: Date
    var nextAttemptAt: Date?
    var lastAttemptAt: Date?
    var lastError: String?

    init(
        id: UUID = UUID(),
        sermonId: UUID,
        kind: ProcessingJobKind,
        status: ProcessingJobStatus = .queued,
        attemptCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        nextAttemptAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.sermonId = sermonId
        self.kindRawValue = kind.rawValue
        self.statusRawValue = status.rawValue
        self.attemptCount = attemptCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.nextAttemptAt = nextAttemptAt
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
    }

    var kind: ProcessingJobKind {
        get { ProcessingJobKind(rawValue: kindRawValue) ?? .transcription }
        set { kindRawValue = newValue.rawValue }
    }

    var status: ProcessingJobStatus {
        get { ProcessingJobStatus(rawValue: statusRawValue) ?? .queued }
        set { statusRawValue = newValue.rawValue }
    }

    func resetForRetry() {
        status = .queued
        attemptCount = 0
        nextAttemptAt = nil
        lastAttemptAt = nil
        lastError = nil
        updatedAt = Date()
    }

    func markRunning() {
        status = .running
        lastAttemptAt = Date()
        updatedAt = Date()
        nextAttemptAt = nil
        lastError = nil
    }

    func markComplete() {
        status = .complete
        updatedAt = Date()
        nextAttemptAt = nil
        lastError = nil
    }

    func markFailed(error: String, nextAttemptAt: Date?) {
        status = .failed
        attemptCount += 1
        lastAttemptAt = Date()
        updatedAt = Date()
        lastError = error
        self.nextAttemptAt = nextAttemptAt
    }

    func isRunnable(at date: Date = Date()) -> Bool {
        switch status {
        case .queued:
            guard let nextAttemptAt else { return true }
            return nextAttemptAt <= date
        case .failed:
            guard let nextAttemptAt else { return false }
            return nextAttemptAt <= date
        case .running, .complete:
            return false
        }
    }
}
