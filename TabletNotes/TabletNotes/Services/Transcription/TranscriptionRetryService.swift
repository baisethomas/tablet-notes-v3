import Foundation
import SwiftData

private struct LegacyPendingTranscription: Codable, Identifiable {
    let id: UUID
    let audioFileURL: URL
    let sermonTitle: String
    let sermonDate: Date
    let serviceType: String
    let createdAt: Date
    let retryCount: Int
}

@MainActor
class TranscriptionRetryService: ObservableObject {
    static let shared = TranscriptionRetryService()

    @Published var isProcessingQueue = false

    static let transcriptionCompletedNotification = Notification.Name("TranscriptionCompleted")

    private var isNetworkAvailable = false

    private let userDefaults = UserDefaults.standard
    private let pendingTranscriptionsKey = "PendingTranscriptions"
    private var modelContext: ModelContext?
    private let maxRetries = 3
    var transcriptionRunner: ((URL, @escaping (Result<(String, [TranscriptSegment]), Error>) -> Void) -> Void)?
    var summaryEnqueuer: (@MainActor (UUID) -> Void)?

    init() {}

    private func upsertTranscript(
        on sermon: Sermon,
        in context: ModelContext,
        text: String,
        segments: [TranscriptSegment]
    ) {
        if let existingTranscript = sermon.transcript {
            let oldSegments = Array(existingTranscript.segments)
            existingTranscript.segments.removeAll()
            for segment in oldSegments {
                context.delete(segment)
            }

            existingTranscript.text = text
            existingTranscript.segments = segments
            existingTranscript.updatedAt = Date()
            existingTranscript.needsSync = true
            return
        }

        let transcript = Transcript(
            text: text,
            segments: segments,
            updatedAt: Date(),
            needsSync: true
        )
        context.insert(transcript)
        sermon.transcript = transcript
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

    func migrateLegacyPendingTranscriptionsIfNeeded() {
        guard let context = modelContext,
              let data = userDefaults.data(forKey: pendingTranscriptionsKey) else {
            return
        }

        do {
            let legacyItems = try JSONDecoder().decode([LegacyPendingTranscription].self, from: data)
            guard !legacyItems.isEmpty else {
                userDefaults.removeObject(forKey: pendingTranscriptionsKey)
                return
            }

            let sermons = try context.fetch(FetchDescriptor<Sermon>())

            for item in legacyItems {
                guard let sermon = sermons.first(where: {
                    $0.audioFileName == item.audioFileURL.lastPathComponent &&
                    $0.serviceType == item.serviceType &&
                    $0.transcriptionStatus != "complete"
                }) else {
                    print("[TranscriptionRetryService] No matching sermon found for legacy pending transcription \(item.audioFileURL.lastPathComponent)")
                    continue
                }

                upsertJob(for: sermon.id, resetAttempts: false)
            }

            try? context.save()
            userDefaults.removeObject(forKey: pendingTranscriptionsKey)
            print("[TranscriptionRetryService] Migrated legacy pending transcription queue to ProcessingJob records")
        } catch {
            print("[TranscriptionRetryService] Failed to migrate legacy pending transcriptions: \(error)")
        }
    }

    func recoverIncompleteTranscriptions() {
        guard let context = modelContext else { return }

        do {
            let sermons = try context.fetch(FetchDescriptor<Sermon>())
            for sermon in sermons where sermon.transcriptionStatus != "complete" && sermon.audioFileExists {
                if job(for: sermon.id) == nil {
                    upsertJob(for: sermon.id, resetAttempts: false)
                    if sermon.transcriptionStatus == "processing" {
                        sermon.transcriptionStatus = "pending"
                        sermon.markPendingSync(metadata: true)
                    }
                }
            }
            try? context.save()
        } catch {
            print("[TranscriptionRetryService] Failed to recover incomplete transcriptions: \(error)")
        }
    }

    @discardableResult
    func enqueueTranscription(for sermonId: UUID) -> Bool {
        guard let context = modelContext,
              let sermon = fetchSermon(withId: sermonId, in: context) else {
            print("[TranscriptionRetryService] Cannot enqueue transcription; sermon \(sermonId) not found")
            return false
        }

        guard sermon.audioFileExists else {
            print("[TranscriptionRetryService] Cannot enqueue transcription; audio file missing for sermon \(sermonId)")
            return false
        }

        upsertJob(for: sermonId, resetAttempts: true)
        sermon.transcriptionStatus = "pending"
        sermon.markPendingSync(metadata: true)
        try? context.save()

        if isNetworkAvailable {
            processQueue()
        }

        return true
    }

    @discardableResult
    func retryTranscriptionNow(for sermonId: UUID) -> Bool {
        guard enqueueTranscription(for: sermonId) else {
            return false
        }

        processJob(for: sermonId)
        return true
    }

    func retryTranscriptionIfNeeded(for sermon: Sermon) {
        guard sermon.transcriptionStatus == "failed" || sermon.transcriptionStatus == "pending" else {
            return
        }
        guard job(for: sermon.id) == nil else { return }
        enqueueTranscription(for: sermon.id)
    }

    func processQueue() {
        guard !isProcessingQueue,
              isNetworkAvailable,
              let context = modelContext,
              let nextJob = nextRunnableJob(in: context),
              let sermon = fetchSermon(withId: nextJob.sermonId, in: context) else {
            return
        }

        startProcessing(job: nextJob, sermon: sermon, in: context)
    }

    private func processJob(for sermonId: UUID) {
        guard !isProcessingQueue,
              let context = modelContext,
              let nextJob = job(for: sermonId),
              nextJob.isRunnable(),
              let sermon = fetchSermon(withId: nextJob.sermonId, in: context) else {
            return
        }

        startProcessing(job: nextJob, sermon: sermon, in: context)
    }

    private func startProcessing(job nextJob: ProcessingJob, sermon: Sermon, in context: ModelContext) {
        isProcessingQueue = true
        nextJob.markRunning()
        sermon.transcriptionStatus = "processing"
        sermon.markPendingSync(metadata: true)
        try? context.save()

        let runner = transcriptionRunner ?? { url, completion in
            let transcriptionService = TranscriptionService()
            transcriptionService.transcribeAudioFileWithResult(url: url, completion: completion)
        }

        runner(sermon.audioFileURL) { [weak self] result in
            Task { @MainActor in
                guard let self, let context = self.modelContext else { return }
                guard let refreshedJob = self.fetchJob(withId: nextJob.id, in: context),
                      let refreshedSermon = self.fetchSermon(withId: nextJob.sermonId, in: context) else {
                    self.isProcessingQueue = false
                    return
                }

                switch result {
                case .success(let (text, segments)):
                    let transcriptSegments = segments.map { segment in
                        TranscriptSegment(
                            id: segment.id,
                            text: segment.text,
                            startTime: segment.startTime,
                            endTime: segment.endTime
                        )
                    }

                    self.upsertTranscript(on: refreshedSermon, in: context, text: text, segments: transcriptSegments)
                    refreshedSermon.transcriptionStatus = "complete"
                    refreshedSermon.summaryStatus = "processing"
                    refreshedSermon.markPendingSync(metadata: true, transcript: true)
                    refreshedJob.markComplete()
                    try? context.save()

                    NotificationCenter.default.post(
                        name: TranscriptionRetryService.transcriptionCompletedNotification,
                        object: refreshedSermon.id
                    )

                    if let summaryEnqueuer = self.summaryEnqueuer {
                        summaryEnqueuer(refreshedSermon.id)
                    } else {
                        SermonProcessingCoordinator.shared.enqueueSummary(for: refreshedSermon.id)
                    }

                case .failure(let error):
                    let nextAttemptAt: Date?
                    if refreshedJob.attemptCount + 1 >= self.maxRetries {
                        nextAttemptAt = nil
                        refreshedSermon.transcriptionStatus = "failed"
                    } else {
                        let retryDelayMinutes = pow(2.0, Double(refreshedJob.attemptCount + 1))
                        nextAttemptAt = Date().addingTimeInterval(retryDelayMinutes * 60)
                        refreshedSermon.transcriptionStatus = "pending"
                        self.scheduleQueueProcessing(after: retryDelayMinutes * 60)
                    }

                    refreshedSermon.markPendingSync(metadata: true)
                    refreshedJob.markFailed(
                        error: error.localizedDescription,
                        nextAttemptAt: nextAttemptAt
                    )
                    try? context.save()
                }

                self.isProcessingQueue = false
                self.processQueue()
            }
        }
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

        let job = ProcessingJob(sermonId: sermonId, kind: .transcription)
        context.insert(job)
    }

    private func job(for sermonId: UUID) -> ProcessingJob? {
        guard let context = modelContext else { return nil }
        let descriptor = FetchDescriptor<ProcessingJob>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor))?.first(where: {
            $0.sermonId == sermonId &&
            $0.kind == .transcription &&
            $0.status != .complete
        })
    }

    private func nextRunnableJob(in context: ModelContext) -> ProcessingJob? {
        let descriptor = FetchDescriptor<ProcessingJob>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor))?.first(where: {
            $0.kind == .transcription && $0.isRunnable()
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
