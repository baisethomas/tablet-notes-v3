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

    /// The job whose runner is executing right now. More precise than
    /// `isProcessingQueue` for the completed-sermon guard: a queue-wide flag
    /// would treat every `.running` row as live while any job runs, leaving
    /// killed-app relics open until the queue went idle (TAB-94 round 3).
    private var activeJobId: UUID?

    /// Jobs enqueued by an explicit user request this session (TAB-94 round
    /// 5). Only these may run against a sermon that already has a summary —
    /// the queue retires any other such job as a relic instead of re-billing.
    /// In-memory on purpose: a deliberate regeneration interrupted by process
    /// death is already treated as a relic on relaunch (the round-2 trade-off),
    /// so the intent does not need to survive it. Never pruned — job ids are
    /// unique per row, and a completed job's id can never match a future open
    /// job, so a stale entry is inert.
    private var deliberateJobIds: Set<UUID> = []

    static let summaryCompletedNotification = Notification.Name("SummaryCompleted")

    private var isNetworkAvailable = false

    private let userDefaults = UserDefaults.standard
    private let pendingSummariesKey = "PendingSummaries"
    private var modelContext: ModelContext?
    private let maxRetries = 3
    private let processingTimeoutMinutes: TimeInterval = 10
    private let automaticRecoveryWindow: TimeInterval = 7 * 24 * 60 * 60
    private let summaryService: any SummaryServiceProtocol
    var summaryRunner: ((String, String) async throws -> SummaryGenerationResult)?
    var basicSummaryGenerator: ((String, String) -> SummaryGenerationResult)?

    init(summaryService: any SummaryServiceProtocol = SummaryService()) {
        self.summaryService = summaryService
    }

    private func normalizedTranscriptText(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    private func resolvedTranscriptText(
        for sermon: Sermon,
        fallbackText: String? = nil,
        allowRelationshipFallback: Bool
    ) -> String? {
        if let fallbackText = normalizedTranscriptText(fallbackText) {
            return fallbackText
        }

        if let cachedText = normalizedTranscriptText(
            TranscriptSnapshotStore.snapshot(for: sermon.id)?.text
        ) {
            return cachedText
        }

        guard allowRelationshipFallback,
              let transcript = sermon.transcript else {
            return nil
        }

        return normalizedTranscriptText(transcript.text)
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
        backfillMissingTranscriptSnapshots()
    }

    /// Writes a transcript snapshot for any sermon that already has transcript
    /// text but no snapshot (TAB-79).
    ///
    /// `TranscriptSnapshotStore` was introduced by the same change that made the
    /// automatic recovery paths read the snapshot and *only* the snapshot
    /// (`allowRelationshipFallback: false`). A sermon transcribed before that —
    /// or one whose snapshot never got written for any other reason — therefore
    /// has its transcript text sitting in the `Transcript` relationship where no
    /// automatic path will ever look, and its summary can never be recovered.
    ///
    /// This normalizes the data rather than loosening the guard: recovery keeps
    /// its "snapshot required" invariant. Reading the relationship here is
    /// deliberate and safe — it happens outside any recovery decision.
    ///
    /// Scoped to sermons automatic recovery would actually act on
    /// (`shouldAutomaticallyRecoverSummary`, which includes the 7-day
    /// `automaticRecoveryWindow`). An unfiltered pass would JSON-encode every
    /// completed transcript in the library into `UserDefaults` on a `@MainActor`
    /// call during startup — potentially megabytes of text — to benefit only the
    /// handful of sermons still inside the window. Sermons outside it are
    /// unaffected either way: they are reachable through manual retry, which
    /// allows the relationship fallback.
    @discardableResult
    func backfillMissingTranscriptSnapshots() -> Int {
        guard let context = modelContext else { return 0 }

        do {
            let sermons = try context.fetch(FetchDescriptor<Sermon>())
            var backfilled = 0

            for sermon in sermons where sermon.transcriptionStatus == "complete" {
                guard shouldAutomaticallyRecoverSummary(
                        for: sermon,
                        job: job(for: sermon.id)
                      ),
                      TranscriptSnapshotStore.snapshot(for: sermon.id) == nil,
                      let transcript = sermon.transcript,
                      normalizedTranscriptText(transcript.text) != nil else {
                    continue
                }

                TranscriptSnapshotStore.save(
                    transcriptId: transcript.id,
                    text: transcript.text,
                    for: sermon.id
                )
                backfilled += 1
            }

            if backfilled > 0 {
                print("[SummaryRetryService] Backfilled \(backfilled) missing transcript snapshot(s)")
            }
            return backfilled
        } catch {
            // Non-fatal: recovery simply keeps skipping these sermons, exactly
            // as it did before. Nothing is written, so nothing can be corrupted.
            print("[SummaryRetryService] Failed to backfill transcript snapshots: \(error.localizedDescription)")
            return 0
        }
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

    @discardableResult
    private func enqueueSummary(
        for sermonId: UUID,
        transcriptText: String?,
        allowRelationshipFallback: Bool
    ) -> Bool {
        guard let context = modelContext,
              let sermon = fetchSermon(withId: sermonId, in: context),
              sermon.transcriptionStatus == "complete",
              let transcriptText = resolvedTranscriptText(
                  for: sermon,
                  fallbackText: transcriptText,
                  allowRelationshipFallback: allowRelationshipFallback
              ) else {
            print("[SummaryRetryService] Cannot enqueue summary; transcript unavailable")
            return false
        }

        print("[SummaryRetryService] Enqueuing summary for sermon \(sermonId) with transcript length \(transcriptText.count)")
        upsertJob(for: sermonId, resetAttempts: true)
        // Every public enqueue is an explicit request (the sweeps call
        // upsertJob directly); record the intent so the queue lets this job
        // run even against an existing summary.
        if let deliberateJob = job(for: sermonId) {
            deliberateJobIds.insert(deliberateJob.id)
        }
        sermon.summaryStatus = "processing"
        sermon.markPendingSync(metadata: true)
        try? context.save()

        if isNetworkAvailable {
            processQueue()
        }

        return true
    }

    @discardableResult
    func enqueueSummary(for sermonId: UUID) -> Bool {
        enqueueSummary(
            for: sermonId,
            transcriptText: nil,
            allowRelationshipFallback: true
        )
    }

    @discardableResult
    func enqueueSummary(for sermonId: UUID, transcriptText: String) -> Bool {
        enqueueSummary(
            for: sermonId,
            transcriptText: transcriptText,
            allowRelationshipFallback: false
        )
    }

    @discardableResult
    private func retrySummaryNow(
        for sermonId: UUID,
        transcriptText: String?,
        allowRelationshipFallback: Bool
    ) -> Bool {
        guard enqueueSummary(
            for: sermonId,
            transcriptText: transcriptText,
            allowRelationshipFallback: allowRelationshipFallback
        ) else {
            return false
        }

        processJob(
            for: sermonId,
            transcriptText: transcriptText,
            allowRelationshipFallback: allowRelationshipFallback
        )
        return true
    }

    @discardableResult
    func retrySummaryNow(for sermonId: UUID) -> Bool {
        retrySummaryNow(
            for: sermonId,
            transcriptText: nil,
            allowRelationshipFallback: true
        )
    }

    @discardableResult
    func retrySummaryNow(for sermonId: UUID, transcriptText: String) -> Bool {
        retrySummaryNow(
            for: sermonId,
            transcriptText: transcriptText,
            allowRelationshipFallback: false
        )
    }

    /// TAB-94 companion: a sermon whose summary already exists needs no
    /// automatic summary work. When the status string has been walked back to
    /// "pending"/"processing" (TAB-95), repair it forward instead of minting
    /// or resuming a job, which re-ran a paid summary over one that already
    /// exists. Only a job that is running right now (a live deliberate
    /// regeneration) is spared; any other open job is a relic — most likely
    /// minted by the pre-TAB-94 sweeps against this same poisoned state — and
    /// resuming it would re-bill, so it is closed. The manual retry paths are
    /// untouched.
    @discardableResult
    private func repairSummarizedSermonIfNeeded(_ sermon: Sermon) -> Bool {
        guard sermon.summary != nil,
              sermon.summaryStatus == "pending" || sermon.summaryStatus == "processing" else {
            return false
        }

        // Relic siblings are closed even while this sermon's own regeneration
        // is live — only the exact active job is spared, ever.
        let openJobs = openSummaryJobs(for: sermon.id)
        var closedRelic = false
        for staleJob in openJobs where staleJob.id != activeJobId {
            staleJob.markComplete()
            closedRelic = true
        }

        if openJobs.contains(where: { $0.id == activeJobId }) {
            // The live regeneration owns this sermon's status; report and
            // repair nothing, but persist the sibling closures.
            if closedRelic {
                try? modelContext?.save()
            }
            return false
        }

        print("[SummaryRetryService] Sermon \(sermon.id) already has a summary; repairing status \(sermon.summaryStatus) -> complete")
        sermon.summaryStatus = "complete"
        sermon.markPendingSync(metadata: true)
        try? modelContext?.save()
        return true
    }

    /// TAB-97 companion to TranscriptionRetryService.repairAlreadyTranscribedStatuses:
    /// the durable pipeline skips this service's recovery sweeps (pumping both
    /// pipelines would double-bill), which also skipped the repair above — a
    /// sermon whose summary already exists but whose status was walked back to
    /// "pending"/"processing" stayed "preparing" forever. Status-only: no jobs
    /// minted, no summary re-run, no network touched.
    func repairAlreadySummarizedStatuses() {
        guard let context = modelContext else { return }
        // Only repair candidates are fetched: after one pass their statuses
        // are terminal, so the steady-state fetch on every foreground refresh
        // returns nothing. The summary-exists half of the check lives in
        // repairSummarizedSermonIfNeeded — optional-relationship predicates
        // are unreliable in SwiftData (see dispatchPendingDurableJobs).
        let descriptor = FetchDescriptor<Sermon>(
            predicate: #Predicate<Sermon> { sermon in
                sermon.summaryStatus == "pending" ||
                sermon.summaryStatus == "processing"
            }
        )
        let sermons = (try? context.fetch(descriptor)) ?? []
        for sermon in sermons {
            repairSummarizedSermonIfNeeded(sermon)
        }
    }

    private func openSummaryJobs(for sermonId: UUID) -> [ProcessingJob] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<ProcessingJob>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter {
            $0.sermonId == sermonId &&
            $0.kind == .summary &&
            $0.status != .complete
        }
    }

    func retrySummaryIfNeeded(for sermon: Sermon) {
        if repairSummarizedSermonIfNeeded(sermon) {
            try? modelContext?.save()
            return
        }
        guard shouldAutomaticallyRecoverSummary(for: sermon) else {
            return
        }
        guard job(for: sermon.id) == nil else { return }
        _ = enqueueSummary(
            for: sermon.id,
            transcriptText: nil,
            allowRelationshipFallback: false
        )
    }

    func recoverIncompleteSummaries() {
        guard let context = modelContext else { return }

        do {
            let sermons = try context.fetch(FetchDescriptor<Sermon>())
            print("[SummaryRetryService] Recovering incomplete summaries from \(sermons.count) sermons")
            for sermon in sermons where sermon.transcriptionStatus == "complete" {
                if repairSummarizedSermonIfNeeded(sermon) { continue }
                guard resolvedTranscriptText(
                    for: sermon,
                    allowRelationshipFallback: false
                ) != nil else {
                    continue
                }
                let existingJob = job(for: sermon.id)
                guard shouldAutomaticallyRecoverSummary(for: sermon, job: existingJob) else { continue }
                print("[SummaryRetryService] Inspecting sermon \(sermon.id) with summaryStatus=\(sermon.summaryStatus)")
                if let existingJob {
                    if sermon.summaryStatus == "processing" || sermon.summaryStatus == "pending" || sermon.summary == nil {
                        if reactivateStaleProcessingJob(existingJob, for: sermon) {
                            print("[SummaryRetryService] Reactivated stale summary job for sermon \(sermon.id)")
                        } else if existingJob.isRunnable() {
                            print("[SummaryRetryService] Summary job is already runnable for sermon \(sermon.id)")
                        }
                    } else if existingJob.status == .running && !isProcessingQueue {
                        existingJob.status = .queued
                        existingJob.nextAttemptAt = nil
                        existingJob.updatedAt = Date()
                        existingJob.lastError = nil
                        sermon.markPendingSync(metadata: true)
                    }
                } else {
                    print("[SummaryRetryService] Recreated missing summary job for sermon \(sermon.id)")
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
                if repairSummarizedSermonIfNeeded(sermon) { continue }
                guard let updatedAt = sermon.updatedAt, updatedAt < timeoutThreshold else { continue }
                guard isWithinAutomaticRecoveryWindow(for: sermon, job: job(for: sermon.id)) else { continue }
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
              let nextCandidate = nextProcessableJob(in: context) else {
            return
        }

        let nextJob = nextCandidate.job
        let sermon = nextCandidate.sermon
        let transcriptText = nextCandidate.transcriptText
        print("[SummaryRetryService] Starting queued summary job for sermon \(nextJob.sermonId)")
        startProcessing(
            job: nextJob,
            sermon: sermon,
            transcriptText: transcriptText,
            in: context
        )
    }

    private func processJob(
        for sermonId: UUID,
        transcriptText: String?,
        allowRelationshipFallback: Bool
    ) {
        guard !isProcessingQueue,
              let context = modelContext,
              let nextJob = job(for: sermonId),
              nextJob.isRunnable(),
              let sermon = fetchSermon(withId: nextJob.sermonId, in: context),
              let transcriptText = resolvedTranscriptText(
                  for: sermon,
                  fallbackText: transcriptText,
                  allowRelationshipFallback: allowRelationshipFallback
              ) else {
            return
        }

        print("[SummaryRetryService] Starting manual summary job for sermon \(sermonId)")
        startProcessing(
            job: nextJob,
            sermon: sermon,
            transcriptText: transcriptText,
            in: context
        )
    }

    private func startProcessing(
        job nextJob: ProcessingJob,
        sermon: Sermon,
        transcriptText: String,
        in context: ModelContext
    ) {
        isProcessingQueue = true
        activeJobId = nextJob.id
        nextJob.markRunning()
        sermon.summaryStatus = "processing"
        sermon.markPendingSync(metadata: true)
        try? context.save()

        let sermonId = sermon.id
        let jobId = nextJob.id
        let serviceType = sermon.serviceType
        let summaryService = self.summaryService
        let runner = summaryRunner ?? { transcript, type in
            try await summaryService.generateSummaryResult(for: transcript, type: type)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            defer {
                self.activeJobId = nil
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
                refreshedSermon.markPendingSync(metadata: true, summary: true)
                refreshedJob.markComplete()
                try? context.save()

                NotificationCenter.default.post(
                    name: SummaryRetryService.summaryCompletedNotification,
                    object: refreshedSermon.id
                )
            } catch {
                print("[SummaryRetryService] Summary generation failed for sermon \(sermonId): \(error.localizedDescription)")
                guard let context = self.modelContext,
                      let refreshedJob = self.fetchJob(withId: jobId, in: context),
                      let refreshedSermon = self.fetchSermon(withId: sermonId, in: context) else {
                    return
                }

                self.handleSummaryFailure(
                    job: refreshedJob,
                    sermon: refreshedSermon,
                    transcript: transcriptText,
                    error: error,
                    in: context
                )
            }
        }
    }

    private func handleSummaryFailure(
        job: ProcessingJob,
        sermon: Sermon,
        transcript: String,
        error: Error,
        in context: ModelContext
    ) {
        let sermonSyncDate = Date()
        let errorDescription: String
        if let summaryError = error as? SummaryService.SummaryError {
            errorDescription = summaryError.userFacingMessage
        } else {
            errorDescription = error.localizedDescription
        }

        let nextAttemptAt: Date?
        if !shouldRetry(error) {
            nextAttemptAt = nil
            if attemptBasicSummaryFallback(for: sermon, job: job, transcript: transcript, in: context) {
                return
            }
            sermon.summaryStatus = "failed"
        } else if job.attemptCount + 1 >= maxRetries {
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

        sermon.markPendingSync(metadata: true, updatedAt: sermonSyncDate)
        job.markFailed(error: errorDescription, nextAttemptAt: nextAttemptAt)
        try? context.save()
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if let summaryError = error as? SummaryService.SummaryError {
            return summaryError.isRetryable
        }

        return true
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
        sermon.markPendingSync(metadata: true, summary: true)
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

    private func shouldAutomaticallyRecoverSummary(
        for sermon: Sermon,
        job: ProcessingJob? = nil
    ) -> Bool {
        guard sermon.transcriptionStatus == "complete" else { return false }
        guard sermon.summaryStatus == "pending" || sermon.summaryStatus == "processing" else { return false }
        guard isWithinAutomaticRecoveryWindow(for: sermon, job: job) else { return false }

        return sermon.summaryStatus != "complete" || sermon.summary == nil
    }

    private func isWithinAutomaticRecoveryWindow(
        for sermon: Sermon,
        job: ProcessingJob? = nil
    ) -> Bool {
        automaticRecoveryAnchorDate(for: sermon, job: job) >= Date().addingTimeInterval(-automaticRecoveryWindow)
    }

    private func automaticRecoveryAnchorDate(
        for sermon: Sermon,
        job: ProcessingJob? = nil
    ) -> Date {
        [
            job?.updatedAt,
            job?.lastAttemptAt,
            sermon.updatedAt,
            sermon.date
        ]
        .compactMap { $0 }
        .max() ?? sermon.date
    }

    @discardableResult
    private func reactivateStaleProcessingJob(_ job: ProcessingJob, for sermon: Sermon) -> Bool {
        guard !isProcessingQueue else { return false }

        switch job.status {
        case .running, .failed:
            job.status = .queued
            job.nextAttemptAt = nil
            job.updatedAt = Date()
            job.lastError = nil
            sermon.summaryStatus = "processing"
            sermon.markPendingSync(metadata: true)
            return true
        case .queued:
            guard job.nextAttemptAt != nil else { return false }
            job.nextAttemptAt = nil
            job.updatedAt = Date()
            job.lastError = nil
            sermon.summaryStatus = "processing"
            sermon.markPendingSync(metadata: true)
            return true
        case .complete:
            return false
        }
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

    private func nextProcessableJob(in context: ModelContext) -> (
        job: ProcessingJob,
        sermon: Sermon,
        transcriptText: String
    )? {
        let descriptor = FetchDescriptor<ProcessingJob>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let jobs = try? context.fetch(descriptor) else { return nil }

        var mutatedQueue = false

        for job in jobs where job.kind == .summary && job.isRunnable() {
            guard let sermon = fetchSermon(withId: job.sermonId, in: context) else {
                print("[SummaryRetryService] Removing orphaned summary job for sermon \(job.sermonId)")
                context.delete(job)
                mutatedQueue = true
                continue
            }

            if sermon.summaryStatus == "complete", sermon.summary != nil {
                print("[SummaryRetryService] Completing stale summary job for sermon \(sermon.id)")
                job.markComplete()
                mutatedQueue = true
                continue
            }

            // TAB-94 round 5: a runnable job for a sermon that already has a
            // summary is a relic unless it was explicitly requested this
            // session — the status string alone can't distinguish a poisoned
            // "processing"/"pending" (TAB-95) from a live regeneration, and
            // the sweeps may not have run yet when the queue is kicked
            // directly (network restored, completion chains).
            if sermon.summary != nil, !deliberateJobIds.contains(job.id) {
                print("[SummaryRetryService] Retiring relic summary job for already-summarized sermon \(sermon.id)")
                job.markComplete()
                mutatedQueue = true
                continue
            }

            guard sermon.transcriptionStatus == "complete",
                  let transcriptText = resolvedTranscriptText(
                      for: sermon,
                      allowRelationshipFallback: false
                  ) else {
                print("[SummaryRetryService] Skipping summary job for sermon \(sermon.id); transcript unavailable")
                continue
            }

            if mutatedQueue {
                try? context.save()
            }

            return (job, sermon, transcriptText)
        }

        if mutatedQueue {
            try? context.save()
        }

        return nil
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
