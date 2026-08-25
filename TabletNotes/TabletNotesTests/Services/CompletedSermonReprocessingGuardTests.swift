import Foundation
import SwiftData
import Testing
@testable import TabletNotes

/// Regression tests for TAB-94: a sermon that already owns its transcript (or
/// summary) must never be re-run by the retry queues or sweeps, whatever its
/// status string says. Sync can walk a completed stage status back to
/// "processing"/"pending" (TAB-95), and before the guard that poisoned string
/// was enough to re-bill AssemblyAI for work that had already succeeded.
struct CompletedSermonReprocessingGuardTests {

    @MainActor
    private func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            Sermon.self,
            Note.self,
            Transcript.self,
            Summary.self,
            ProcessingJob.self,
            TranscriptSegment.self,
            ChatMessage.self,
            User.self,
            UserNotificationSettings.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }

    @MainActor
    private func makeAudioFile(named fileName: String) throws -> URL {
        let audioDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent(fileName)
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: Data(repeating: 0x01, count: 4096))
        return audioURL
    }

    @MainActor
    private func makeTranscribedSermon(
        audioFileName: String,
        transcriptionStatus: String,
        date: Date = Date()
    ) -> Sermon {
        let transcript = Transcript(text: "Already transcribed text", needsSync: false)
        return Sermon(
            title: "Completed Sermon",
            audioFileName: audioFileName,
            date: date,
            serviceType: "Sunday Service",
            transcript: transcript,
            notes: [],
            summary: nil,
            syncStatus: "synced",
            transcriptionStatus: transcriptionStatus,
            summaryStatus: "complete",
            userId: UUID()
        )
    }

    // MARK: - Transcription

    /// The exact incident: a stale/poisoned "processing" status plus a runnable
    /// job must not reach the transcription runner when the transcript already
    /// exists. The job is closed and the status repaired forward instead.
    @MainActor
    @Test func processQueueClosesJobInsteadOfRerunningTranscribedSermon() async throws {
        let context = try makeModelContext()
        let audioURL = try makeAudioFile(named: "tab94-queue.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let sermon = makeTranscribedSermon(
            audioFileName: audioURL.lastPathComponent,
            transcriptionStatus: "processing"
        )
        context.insert(sermon)
        let staleJob = ProcessingJob(sermonId: sermon.id, kind: .transcription)
        context.insert(staleJob)
        try context.save()

        let retryService = TranscriptionRetryService()
        retryService.setModelContext(context)
        defer {
            retryService.transcriptionRunner = nil
            retryService.overrideNetworkAvailability(false)
        }

        var runnerCallCount = 0
        retryService.transcriptionRunner = { _, completion in
            runnerCallCount += 1
            completion(.success(("Re-transcribed text", [])))
        }

        // false -> true triggers processQueue(), which picks up the stale job.
        retryService.overrideNetworkAvailability(true)
        try await Task.sleep(nanoseconds: 200_000_000)

        let jobs = try context.fetch(FetchDescriptor<ProcessingJob>())
        #expect(runnerCallCount == 0)
        #expect(jobs.allSatisfy { $0.status == .complete })
        #expect(sermon.transcriptionStatus == "complete")
        #expect(sermon.metadataNeedsSync)
    }

    /// The stuck-processing sweep used to see the poisoned "processing" status,
    /// mint a fresh job, and flip the sermon to "pending" — queueing a paid
    /// re-transcription. It must repair the status instead.
    @MainActor
    @Test func stuckSweepRepairsTranscribedSermonInsteadOfRequeueing() async throws {
        let context = try makeModelContext()
        let audioURL = try makeAudioFile(named: "tab94-sweep.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        // Old enough to be past the 15-minute stuck threshold, well inside the
        // 30-day automatic recovery window.
        let sermon = makeTranscribedSermon(
            audioFileName: audioURL.lastPathComponent,
            transcriptionStatus: "processing",
            date: Date().addingTimeInterval(-3600)
        )
        context.insert(sermon)
        try context.save()

        let retryService = TranscriptionRetryService()
        retryService.setModelContext(context)

        retryService.checkForStuckProcessingTranscriptions()

        let jobs = try context.fetch(FetchDescriptor<ProcessingJob>())
        #expect(jobs.filter { $0.status != .complete }.isEmpty)
        #expect(sermon.transcriptionStatus == "complete")
        #expect(sermon.metadataNeedsSync)

        // The repair must be persisted, not pending autosave: a fresh context
        // sees only saved state.
        let freshContext = ModelContext(context.container)
        let persisted = try freshContext.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        #expect(persisted?.transcriptionStatus == "complete")
        #expect(persisted?.metadataNeedsSync == true)
    }

    /// A deliberate Retry tap on a sermon whose transcript already exists (the
    /// retry affordance is visible precisely because the status is poisoned)
    /// must keep the completed work rather than re-billing the provider.
    @MainActor
    @Test func enqueueTranscriptionRefusesWhenTranscriptExists() async throws {
        let context = try makeModelContext()
        let audioURL = try makeAudioFile(named: "tab94-enqueue.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let sermon = makeTranscribedSermon(
            audioFileName: audioURL.lastPathComponent,
            transcriptionStatus: "failed"
        )
        context.insert(sermon)
        try context.save()

        let retryService = TranscriptionRetryService()
        retryService.setModelContext(context)

        let enqueued = retryService.enqueueTranscription(for: sermon.id)

        let jobs = try context.fetch(FetchDescriptor<ProcessingJob>())
        #expect(!enqueued)
        #expect(jobs.filter { $0.status != .complete }.isEmpty)
        #expect(sermon.transcriptionStatus == "complete")
    }

    // MARK: - Summary

    @MainActor
    private func makeSummarizedSermon(summaryStatus: String, updatedAt: Date = Date()) -> Sermon {
        let transcript = Transcript(text: String(repeating: "Sermon text ", count: 20))
        let summary = Summary(
            title: "Existing Summary",
            text: "The summary that already exists.",
            type: "Sunday Service",
            status: "complete"
        )
        return Sermon(
            title: "Summarized Sermon",
            audioFileName: "tab94-summary.m4a",
            date: Date().addingTimeInterval(-3600),
            serviceType: "Sunday Service",
            transcript: transcript,
            notes: [],
            summary: summary,
            syncStatus: "synced",
            transcriptionStatus: "complete",
            summaryStatus: summaryStatus,
            userId: UUID(),
            updatedAt: updatedAt
        )
    }

    /// The bootstrap sweep saw a poisoned "pending" summary status with no live
    /// job and recreated the job — a paid summary re-run over a summary that
    /// already exists. With no job in flight there is no work to resume; repair
    /// the status instead. (Only a regeneration running right now is spared —
    /// see summarySweepClosesRelicJobInsteadOfResuming.)
    @MainActor
    @Test func summaryBootstrapSweepRepairsPoisonedStatusWithoutNewJob() async throws {
        let context = try makeModelContext()

        let sermon = makeSummarizedSermon(summaryStatus: "pending")
        context.insert(sermon)
        try context.save()
        TranscriptSnapshotStore.save(
            transcriptId: sermon.transcript?.id ?? UUID(),
            text: sermon.transcript?.text ?? "",
            for: sermon.id
        )
        defer { TranscriptSnapshotStore.remove(for: sermon.id) }

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)

        retryService.recoverIncompleteSummaries()

        let jobs = try context.fetch(FetchDescriptor<ProcessingJob>())
        #expect(jobs.isEmpty)
        #expect(sermon.summaryStatus == "complete")
        #expect(sermon.metadataNeedsSync)

        // The repair must be persisted, not pending autosave: a fresh context
        // sees only saved state.
        let freshContext = ModelContext(context.container)
        let persisted = try freshContext.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        #expect(persisted?.summaryStatus == "complete")
        #expect(persisted?.metadataNeedsSync == true)
    }

    /// Same poisoned state, caught by the stuck-processing sweep.
    @MainActor
    @Test func stuckSummarySweepRepairsPoisonedStatusWithoutNewJob() async throws {
        let context = try makeModelContext()

        let sermon = makeSummarizedSermon(
            summaryStatus: "processing",
            updatedAt: Date().addingTimeInterval(-3600)
        )
        context.insert(sermon)
        try context.save()

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)

        retryService.checkForStuckProcessingSummaries()

        let jobs = try context.fetch(FetchDescriptor<ProcessingJob>())
        #expect(jobs.isEmpty)
        #expect(sermon.summaryStatus == "complete")

        // The repair must be persisted, not pending autosave: a fresh context
        // sees only saved state.
        let freshContext = ModelContext(context.container)
        let persisted = try freshContext.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        #expect(persisted?.summaryStatus == "complete")
        #expect(persisted?.metadataNeedsSync == true)
    }

    /// Review round 2, finding 1: a sync pull can land a remote transcript
    /// while a legitimate transcription run is in flight. The sweep must spare
    /// the live job — closing it mid-run would orphan the runner's completion
    /// — while still repairing nothing prematurely; the run finishes and
    /// reports through its own completion.
    @MainActor
    @Test func sweepSparesLiveTranscriptionRunWhenPullLandsTranscript() async throws {
        let context = try makeModelContext()
        let audioURL = try makeAudioFile(named: "tab94-live-run.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let sermon = Sermon(
            title: "Live Run Sermon",
            audioFileName: audioURL.lastPathComponent,
            date: Date().addingTimeInterval(-3600),
            serviceType: "Sunday Service",
            transcript: nil,
            notes: [],
            summary: nil,
            syncStatus: "synced",
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            userId: UUID()
        )
        context.insert(sermon)
        try context.save()

        let retryService = TranscriptionRetryService()
        retryService.setModelContext(context)
        retryService.summaryEnqueuer = { _, _ in }
        defer {
            retryService.transcriptionRunner = nil
            retryService.summaryEnqueuer = nil
            retryService.overrideNetworkAvailability(false)
        }

        var storedCompletion: ((Result<(String, [TranscriptSegment]), Error>) -> Void)?
        retryService.transcriptionRunner = { _, completion in
            storedCompletion = completion // hold the run in flight
        }

        retryService.overrideNetworkAvailability(true)
        retryService.enqueueTranscription(for: sermon.id)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(storedCompletion != nil)

        // A pull lands the remote transcript mid-run.
        let pulledTranscript = Transcript(text: "Transcript from pull", needsSync: false)
        context.insert(pulledTranscript)
        sermon.transcript = pulledTranscript
        try context.save()

        retryService.checkForStuckProcessingTranscriptions()

        let liveJob = try context.fetch(FetchDescriptor<ProcessingJob>())
            .first(where: { $0.sermonId == sermon.id && $0.kind == .transcription })
        #expect(liveJob?.status == .running)

        storedCompletion?(.success(("Transcript from live run", [])))
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(liveJob?.status == .complete)
        #expect(sermon.transcriptionStatus == "complete")
        #expect(sermon.transcript?.text == "Transcript from live run")
        #expect(!retryService.isProcessingQueue)
    }

    /// Review round 3: the live-job exemption must identify the exact active
    /// job, not "any job is running". While sermon A's runner is live, a
    /// `.running` relic on completed sermon B is a killed-app leftover and is
    /// closed immediately — not preserved until the queue goes idle.
    @MainActor
    @Test func sweepClosesRunningRelicWhileUnrelatedRunIsLive() async throws {
        let context = try makeModelContext()
        let liveAudioURL = try makeAudioFile(named: "tab94-live-a.m4a")
        let relicAudioURL = try makeAudioFile(named: "tab94-relic-b.m4a")
        defer {
            try? FileManager.default.removeItem(at: liveAudioURL)
            try? FileManager.default.removeItem(at: relicAudioURL)
        }

        let liveSermon = Sermon(
            title: "Live Sermon A",
            audioFileName: liveAudioURL.lastPathComponent,
            date: Date(),
            serviceType: "Sunday Service",
            transcript: nil,
            notes: [],
            summary: nil,
            syncStatus: "synced",
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            userId: UUID()
        )
        context.insert(liveSermon)

        let completedSermon = makeTranscribedSermon(
            audioFileName: relicAudioURL.lastPathComponent,
            transcriptionStatus: "processing",
            date: Date().addingTimeInterval(-3600)
        )
        context.insert(completedSermon)
        let relicJob = ProcessingJob(sermonId: completedSermon.id, kind: .transcription, status: .running)
        context.insert(relicJob)
        try context.save()

        let retryService = TranscriptionRetryService()
        retryService.setModelContext(context)
        retryService.summaryEnqueuer = { _, _ in }
        defer {
            retryService.transcriptionRunner = nil
            retryService.summaryEnqueuer = nil
            retryService.overrideNetworkAvailability(false)
        }

        var storedCompletion: ((Result<(String, [TranscriptSegment]), Error>) -> Void)?
        retryService.transcriptionRunner = { _, completion in
            storedCompletion = completion // hold sermon A's run in flight
        }

        // The relic is .running (not runnable), so the queue picks sermon A's
        // pending work; enqueue creates A's job and starts it.
        retryService.overrideNetworkAvailability(true)
        retryService.enqueueTranscription(for: liveSermon.id)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(storedCompletion != nil)

        retryService.checkForStuckProcessingTranscriptions()

        let jobs = try context.fetch(FetchDescriptor<ProcessingJob>())
        let liveJob = jobs.first(where: { $0.sermonId == liveSermon.id })
        #expect(relicJob.status == .complete)
        #expect(completedSermon.transcriptionStatus == "complete")
        #expect(liveJob?.status == .running)

        storedCompletion?(.success(("Live transcript", [])))
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(liveJob?.status == .complete)
        #expect(liveSermon.transcript?.text == "Live transcript")
    }

    /// Review round 2, finding 3: a non-running summary job alongside an
    /// existing summary is a relic — most likely minted by the pre-TAB-94
    /// sweeps against the same poisoned state this PR fixes — and resuming it
    /// after an app upgrade would re-bill. The sweep closes it and repairs the
    /// status instead.
    @MainActor
    @Test func summarySweepClosesRelicJobInsteadOfResuming() async throws {
        let context = try makeModelContext()

        let sermon = makeSummarizedSermon(summaryStatus: "pending")
        context.insert(sermon)
        let relicJob = ProcessingJob(sermonId: sermon.id, kind: .summary)
        context.insert(relicJob)
        try context.save()
        TranscriptSnapshotStore.save(
            transcriptId: sermon.transcript?.id ?? UUID(),
            text: sermon.transcript?.text ?? "",
            for: sermon.id
        )
        defer { TranscriptSnapshotStore.remove(for: sermon.id) }

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)

        retryService.recoverIncompleteSummaries()

        #expect(relicJob.status == .complete)
        #expect(sermon.summaryStatus == "complete")
        #expect(sermon.metadataNeedsSync)

        let freshContext = ModelContext(context.container)
        let persisted = try freshContext.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        #expect(persisted?.summaryStatus == "complete")
    }

    /// Review round 3, summary side: while sermon A's summary runner is live,
    /// a `.running` relic on summarized sermon B is closed and B repaired —
    /// the exemption applies only to the exact active job.
    @MainActor
    @Test func summarySweepClosesRunningRelicWhileUnrelatedRunIsLive() async throws {
        let context = try makeModelContext()

        let liveSermon = Sermon(
            title: "Live Summary Sermon A",
            audioFileName: "tab94-live-summary-a.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            transcript: Transcript(text: String(repeating: "Live text ", count: 20)),
            notes: [],
            summary: nil,
            syncStatus: "synced",
            transcriptionStatus: "complete",
            summaryStatus: "pending",
            userId: UUID()
        )
        context.insert(liveSermon)

        let summarizedSermon = makeSummarizedSermon(
            summaryStatus: "processing",
            updatedAt: Date().addingTimeInterval(-3600)
        )
        context.insert(summarizedSermon)
        let relicJob = ProcessingJob(sermonId: summarizedSermon.id, kind: .summary, status: .running)
        context.insert(relicJob)
        try context.save()

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)
        retryService.overrideNetworkAvailability(true)
        defer {
            retryService.summaryRunner = nil
            retryService.overrideNetworkAvailability(false)
        }

        var resumeRunner: CheckedContinuation<SummaryGenerationResult, Never>?
        retryService.summaryRunner = { _, _ in
            await withCheckedContinuation { continuation in
                resumeRunner = continuation // hold sermon A's run in flight
            }
        }

        let started = retryService.retrySummaryNow(
            for: liveSermon.id,
            transcriptText: String(repeating: "Live text ", count: 20)
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(started)
        #expect(resumeRunner != nil)

        retryService.checkForStuckProcessingSummaries()

        let liveJob = try context.fetch(FetchDescriptor<ProcessingJob>())
            .first(where: { $0.sermonId == liveSermon.id && $0.kind == .summary })
        #expect(relicJob.status == .complete)
        #expect(summarizedSermon.summaryStatus == "complete")
        #expect(liveJob?.status == .running)

        resumeRunner?.resume(returning: SummaryGenerationResult(title: "Live", summary: "Live summary."))
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(liveJob?.status == .complete)
        #expect(liveSermon.summary?.text == "Live summary.")
        #expect(liveSermon.summaryStatus == "complete")
    }

    /// Review round 4: a stale sibling job on the SAME sermon as the live
    /// regeneration is closed by the sweep — the active-job exemption spares
    /// exactly one job, and never shields its siblings. The live run's status
    /// is left alone and it finishes normally.
    @MainActor
    @Test func summaryGuardClosesStaleSiblingWhileRegenerationIsLive() async throws {
        let context = try makeModelContext()

        let sermon = makeSummarizedSermon(summaryStatus: "complete")
        context.insert(sermon)
        try context.save()

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)
        retryService.overrideNetworkAvailability(true)
        defer {
            retryService.summaryRunner = nil
            retryService.overrideNetworkAvailability(false)
        }

        var resumeRunner: CheckedContinuation<SummaryGenerationResult, Never>?
        retryService.summaryRunner = { _, _ in
            await withCheckedContinuation { continuation in
                resumeRunner = continuation // hold the regeneration in flight
            }
        }

        let started = retryService.retrySummaryNow(
            for: sermon.id,
            transcriptText: String(repeating: "Fresh text ", count: 20)
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(started)
        #expect(resumeRunner != nil)

        // A stale sibling appears alongside the live job (e.g. left by an
        // older build); status is "processing" because the regen is running.
        let siblingJob = ProcessingJob(sermonId: sermon.id, kind: .summary)
        context.insert(siblingJob)
        try context.save()

        retryService.checkForStuckProcessingSummaries()

        let activeJob = try context.fetch(FetchDescriptor<ProcessingJob>())
            .first(where: { $0.sermonId == sermon.id && $0.id != siblingJob.id })
        #expect(siblingJob.status == .complete)
        #expect(activeJob?.status == .running)
        #expect(sermon.summaryStatus == "processing") // live run owns the status

        resumeRunner?.resume(returning: SummaryGenerationResult(title: "Regen", summary: "Regenerated summary."))
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(activeJob?.status == .complete)
        #expect(sermon.summary?.text == "Regenerated summary.")
        #expect(sermon.summaryStatus == "complete")
    }

    /// Review round 5: the queue itself must not trust the status string. A
    /// queued relic beside an existing summary and a poisoned "processing"
    /// status is retired when processQueue is kicked directly (network
    /// restored, completion chains) — before any sweep has run.
    @MainActor
    @Test func processQueueRetiresRelicSummaryJobWithoutSweep() async throws {
        let context = try makeModelContext()

        let sermon = makeSummarizedSermon(summaryStatus: "processing")
        context.insert(sermon)
        let relicJob = ProcessingJob(sermonId: sermon.id, kind: .summary)
        context.insert(relicJob)
        try context.save()
        TranscriptSnapshotStore.save(
            transcriptId: sermon.transcript?.id ?? UUID(),
            text: sermon.transcript?.text ?? "",
            for: sermon.id
        )
        defer { TranscriptSnapshotStore.remove(for: sermon.id) }

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)
        defer {
            retryService.summaryRunner = nil
            retryService.overrideNetworkAvailability(false)
        }

        var runnerCallCount = 0
        retryService.summaryRunner = { _, _ in
            runnerCallCount += 1
            return SummaryGenerationResult(title: "Should not run", summary: "Should not run.")
        }

        // false -> true kicks processQueue directly, with no sweep involved.
        retryService.overrideNetworkAvailability(true)
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(runnerCallCount == 0)
        #expect(relicJob.status == .complete)
        #expect(sermon.summary?.text == "The summary that already exists.")
    }

    /// Review round 5, the reviewer's literal scenario: an existing summary
    /// with summaryStatus == "complete" and a persisted queued job. Pinned:
    /// the queue retires the job without running it.
    @MainActor
    @Test func processQueueRetiresPendingJobForCompleteSummarizedSermon() async throws {
        let context = try makeModelContext()

        let sermon = makeSummarizedSermon(summaryStatus: "complete")
        context.insert(sermon)
        let staleJob = ProcessingJob(sermonId: sermon.id, kind: .summary)
        context.insert(staleJob)
        try context.save()

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)
        defer {
            retryService.summaryRunner = nil
            retryService.overrideNetworkAvailability(false)
        }

        var runnerCallCount = 0
        retryService.summaryRunner = { _, _ in
            runnerCallCount += 1
            return SummaryGenerationResult(title: "Should not run", summary: "Should not run.")
        }

        retryService.overrideNetworkAvailability(true)
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(runnerCallCount == 0)
        #expect(staleJob.status == .complete)
    }

    /// Guard-overreach protection: a deliberate regeneration (retrySummaryNow
    /// with fresh transcript text) replaces an existing summary today and must
    /// keep doing so — the guard only stops job-less automatic sweeps.
    @MainActor
    @Test func deliberateSummaryRegenerationStillReplacesExistingSummary() async throws {
        let context = try makeModelContext()

        let sermon = makeSummarizedSermon(summaryStatus: "complete")
        context.insert(sermon)
        try context.save()

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)
        retryService.overrideNetworkAvailability(true)
        defer {
            retryService.summaryRunner = nil
            retryService.overrideNetworkAvailability(false)
        }

        var runnerCallCount = 0
        retryService.summaryRunner = { _, _ in
            runnerCallCount += 1
            return SummaryGenerationResult(title: "Regenerated", summary: "A fresh summary.")
        }

        let started = retryService.retrySummaryNow(
            for: sermon.id,
            transcriptText: String(repeating: "Fresh transcript ", count: 20)
        )
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(started)
        #expect(runnerCallCount == 1)
        #expect(sermon.summary?.text == "A fresh summary.")
        #expect(sermon.summaryStatus == "complete")
    }
}
