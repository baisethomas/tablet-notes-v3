import Foundation
import SwiftData

private struct LegacyPendingSummary: Codable, Identifiable {
    let id: UUID
    let sermonId: UUID
    let transcript: String
    let serviceType: String
    let createdAt: Date
    let retryCount: Int
    let lastAttemptAt: Date?
}

@MainActor
class SummaryRetryService: ObservableObject {
    static let shared = SummaryRetryService()

    @Published var isProcessingQueue = false

    static let summaryCompletedNotification = Notification.Name("SummaryCompleted")

    private var isNetworkAvailable = false

    private let userDefaults = UserDefaults.standard
    private let pendingSummariesKey = "PendingSummaries"
    private var modelContext: ModelContext?
    private let maxRetries = 3
    private let processingTimeoutMinutes: TimeInterval = 10
    private let summaryService: any SummaryServiceProtocol
    var summaryRunner: ((String, String) async throws -> SummaryGenerationResult)?
    var basicSummaryGenerator: ((String, String) -> SummaryGenerationResult)?

    init(summaryService: any SummaryServiceProtocol = SummaryService()) {
        self.summaryService = summaryService
    }

    private func upsertSummary(
        on sermon: Sermon,
        in context: ModelContext,
        title: String,
        text: String,
        type: String,
        status: String
    ) {
        if let existingSummary = sermon.summary {
            existingSummary.title = title
            existingSummary.text = text
            existingSummary.type = type
            existingSummary.status = status
            existingSummary.updatedAt = Date()
            existingSummary.needsSync = true
            sermon.summaryPreviewText = Sermon.makeSummaryPreview(from: text)
            return
        }

        let summary = Summary(
            title: title,
            text: text,
            type: type,
            status: status,
            updatedAt: Date(),
            needsSync: true
        )
        context.insert(summary)
        sermon.summary = summary
        sermon.summaryPreviewText = Sermon.makeSummaryPreview(from: text)
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func overrideNetworkAvailability(_ isAvailable: Bool) {
        let wasAvailable = isNetworkAvailable
        isNetworkAvailable = isAvailable
        if !wasAvailable && isAvailable {
            processQueue()
        }
    }

    func migrateLegacyPendingSummariesIfNeeded() {
        guard let context = modelContext,
              let data = userDefaults.data(forKey: pendingSummariesKey) else {
            return
        }

        do {
            let legacyItems = try JSONDecoder().decode([LegacyPendingSummary].self, from: data)
            for item in legacyItems where fetchSermon(withId: item.sermonId, in: context) != nil {
                upsertJob(for: item.sermonId, resetAttempts: false)
            }
            try? context.save()
            userDefaults.removeObject(forKey: pendingSummariesKey)
            print("[SummaryRetryService] Migrated legacy pending summary queue to ProcessingJob records")
        } catch {
            print("[SummaryRetryService] Failed to migrate legacy pending summaries: \(error)")
        }
    }

    func enqueueSummary(for sermonId: UUID) {
        guard let context = modelContext,
              let sermon = fetchSermon(withId: sermonId, in: context),
              let transcript = sermon.transcript,
              !transcript.text.isEmpty else {
            print("[SummaryRetryService] Cannot enqueue summary; transcript unavailable")
            return
        }

        upsertJob(for: sermonId, resetAttempts: true)
        sermon.summaryStatus = "processing"
        sermon.updatedAt = Date()
        sermon.needsSync = true
        sermon.syncStatus = "pending"
        try? context.save()

        if isNetworkAvailable {
            processQueue()
        }
    }

    func retrySummaryIfNeeded(for sermon: Sermon) {
        guard sermon.summaryStatus == "failed" || sermon.summaryStatus == "processing" else {
            return
        }
        guard job(for: sermon.id) == nil else { return }
        enqueueSummary(for: sermon.id)
    }

    func recoverIncompleteSummaries() {
        guard let context = modelContext else { return }

        do {
            let sermons = try context.fetch(FetchDescriptor<Sermon>())
            for sermon in sermons where sermon.transcriptionStatus == "complete" {
                guard let transcript = sermon.transcript, !transcript.text.isEmpty else { continue }
                guard sermon.summaryStatus == "failed" || sermon.summaryStatus == "processing" else { continue }
                if job(for: sermon.id) == nil {
                    upsertJob(for: sermon.id, resetAttempts: false)
                }
            }
            try? context.save()
        } catch {
            print("[SummaryRetryService] Failed to recover incomplete summaries: \(error)")
        }
    }

    func checkForStuckProcessingSummaries() {
        guard let context = modelContext else { return }

        let timeoutThreshold = Date().addingTimeInterval(-processingTimeoutMinutes * 60)

        do {
            let sermons = try context.fetch(FetchDescriptor<Sermon>())
            for sermon in sermons where sermon.summaryStatus == "processing" {
                guard let updatedAt = sermon.updatedAt, updatedAt < timeoutThreshold else { continue }
                if job(for: sermon.id) == nil {
                    upsertJob(for: sermon.id, resetAttempts: false)
                }
            }
            try? context.save()
        } catch {
            print("[SummaryRetryService] Failed to recover stuck summaries: \(error)")
        }
    }

    func processQueue() {
        guard !isProcessingQueue,
              isNetworkAvailable,
              let context = modelContext,
              let nextJob = nextRunnableJob(in: context),
              let sermon = fetchSermon(withId: nextJob.sermonId, in: context),
              let transcript = sermon.transcript,
              !transcript.text.isEmpty else {
            return
        }

        isProcessingQueue = true
        nextJob.markRunning()
        sermon.summaryStatus = "processing"
        sermon.updatedAt = Date()
        sermon.needsSync = true
        sermon.syncStatus = "pending"
        try? context.save()

        let sermonId = sermon.id
        let jobId = nextJob.id
        let transcriptText = transcript.text
        let serviceType = sermon.serviceType
        let summaryService = self.summaryService
        let runner = summaryRunner ?? { transcript, type in
            try await summaryService.generateSummaryResult(for: transcript, type: type)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                self.isProcessingQueue = false
                self.processQueue()
            }

            do {
                let result = try await runner(transcriptText, serviceType)

                guard let context = self.modelContext,
                      let refreshedJob = self.fetchJob(withId: jobId, in: context),
                      let refreshedSermon = self.fetchSermon(withId: sermonId, in: context) else {
                    return
                }

                let summaryTitle = result.title ?? "Sermon Summary"
                self.upsertSummary(
                    on: refreshedSermon,
                    in: context,
                    title: summaryTitle,
                    text: result.summary,
                    type: refreshedSermon.serviceType,
                    status: "complete"
                )

                if let title = result.title, !title.isEmpty {
                    refreshedSermon.title = title
                }

                refreshedSermon.summaryStatus = "complete"
                refreshedSermon.needsSync = true
                refreshedSermon.updatedAt = Date()
                refreshedSermon.syncStatus = "pending"
                refreshedJob.markComplete()
                try? context.save()

                NotificationCenter.default.post(
                    name: SummaryRetryService.summaryCompletedNotification,
                    object: refreshedSermon.id
                )
            } catch {
                guard let context = self.modelContext,
                      let refreshedJob = self.fetchJob(withId: jobId, in: context),
                      let refreshedSermon = self.fetchSermon(withId: sermonId, in: context) else {
                    return
                }

                self.handleSummaryFailure(
                    job: refreshedJob,
                    sermon: refreshedSermon,
                    transcript: transcriptText,
                    errorDescription: error.localizedDescription,
                    in: context
                )
            }
        }
    }

    private func handleSummaryFailure(
        job: ProcessingJob,
        sermon: Sermon,
        transcript: String,
        errorDescription: String,
        in context: ModelContext
    ) {
        let sermonSyncDate = Date()

        let nextAttemptAt: Date?
        if job.attemptCount + 1 >= maxRetries {
            nextAttemptAt = nil
            if attemptBasicSummaryFallback(for: sermon, job: job, transcript: transcript, in: context) {
                return
            }
            sermon.summaryStatus = "failed"
        } else {
            let retryDelayMinutes = pow(2.0, Double(job.attemptCount + 1))
            nextAttemptAt = Date().addingTimeInterval(retryDelayMinutes * 60)
            sermon.summaryStatus = "processing"
            scheduleQueueProcessing(after: retryDelayMinutes * 60)
        }

        sermon.needsSync = true
        sermon.updatedAt = sermonSyncDate
        sermon.syncStatus = "pending"
        job.markFailed(error: errorDescription, nextAttemptAt: nextAttemptAt)
        try? context.save()
    }

    private func attemptBasicSummaryFallback(
        for sermon: Sermon,
        job: ProcessingJob,
        transcript: String,
        in context: ModelContext
    ) -> Bool {
        let summaryService = self.summaryService
        let generator = basicSummaryGenerator ?? { transcript, type in
            summaryService.generateBasicSummaryResult(for: transcript, type: type)
        }

        let fallbackResult = generator(transcript, sermon.serviceType)
        guard !fallbackResult.summary.isEmpty else {
            return false
        }

        let summaryTitle = fallbackResult.title ?? "Sermon Summary"
        upsertSummary(
            on: sermon,
            in: context,
            title: summaryTitle,
            text: fallbackResult.summary,
            type: sermon.serviceType,
            status: "complete"
        )

        if let title = fallbackResult.title, !title.isEmpty {
            sermon.title = title
        }

        sermon.summaryStatus = "complete"
        sermon.needsSync = true
        sermon.updatedAt = Date()
        sermon.syncStatus = "pending"
        job.markComplete()
        try? context.save()

        NotificationCenter.default.post(
            name: SummaryRetryService.summaryCompletedNotification,
            object: sermon.id
        )

        return true
    }

    private func scheduleQueueProcessing(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor in
                self?.processQueue()
            }
        }
    }

    private func upsertJob(for sermonId: UUID, resetAttempts: Bool) {
        guard let context = modelContext else { return }

        if let existingJob = job(for: sermonId) {
            if resetAttempts {
                existingJob.resetForRetry()
            } else {
                existingJob.status = .queued
                existingJob.nextAttemptAt = nil
                existingJob.updatedAt = Date()
            }
            return
        }

        let job = ProcessingJob(sermonId: sermonId, kind: .summary)
        context.insert(job)
    }

    private func job(for sermonId: UUID) -> ProcessingJob? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<ProcessingJob>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor))?.first(where: {
            $0.sermonId == sermonId &&
            $0.kind == .summary &&
            $0.status != .complete
        })
    }

    private func nextRunnableJob(in context: ModelContext) -> ProcessingJob? {
        let descriptor = FetchDescriptor<ProcessingJob>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor))?.first(where: {
            $0.kind == .summary && $0.isRunnable()
        })
    }

    private func fetchSermon(withId id: UUID, in context: ModelContext) -> Sermon? {
        let descriptor = FetchDescriptor<Sermon>(predicate: #Predicate { sermon in
            sermon.id == id
        })
        return try? context.fetch(descriptor).first
    }

    private func fetchJob(withId id: UUID, in context: ModelContext) -> ProcessingJob? {
        let descriptor = FetchDescriptor<ProcessingJob>(predicate: #Predicate { job in
            job.id == id
        })
        return try? context.fetch(descriptor).first
    }
}
