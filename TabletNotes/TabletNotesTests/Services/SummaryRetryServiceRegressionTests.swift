import Foundation
import SwiftData
import Testing
@testable import TabletNotes

struct SummaryRetryServiceRegressionTests {

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
    @Test func summaryRetryProcessesQueuedJobsWithoutCrossApplyingResults() async throws {
        let context = try makeModelContext()

        let firstTranscript = Transcript(text: String(repeating: "Alpha message ", count: 8))
        let firstSermon = Sermon(
            title: "First Sermon",
            audioFileName: "first.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            transcript: firstTranscript,
            notes: [],
            summary: nil,
            syncStatus: "pending",
            transcriptionStatus: "complete",
            summaryStatus: "pending",
            userId: UUID()
        )
        context.insert(firstTranscript)
        context.insert(firstSermon)

        let secondTranscript = Transcript(text: String(repeating: "Beta message ", count: 8))
        let secondSermon = Sermon(
            title: "Second Sermon",
            audioFileName: "second.m4a",
            date: Date(),
            serviceType: "Bible Study",
            transcript: secondTranscript,
            notes: [],
            summary: nil,
            syncStatus: "pending",
            transcriptionStatus: "complete",
            summaryStatus: "pending",
            userId: UUID()
        )
        context.insert(secondTranscript)
        context.insert(secondSermon)
        try context.save()

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)
        retryService.overrideNetworkAvailability(true)
        defer {
            retryService.summaryRunner = nil
            retryService.basicSummaryGenerator = nil
            retryService.overrideNetworkAvailability(false)
        }
        retryService.summaryRunner = { transcript, serviceType in
            try await Task.sleep(nanoseconds: 50_000_000)

            if transcript.contains("Alpha") {
                return SummaryGenerationResult(
                    title: "Alpha Title",
                    summary: "Alpha Summary for \(serviceType)"
                )
            }

            return SummaryGenerationResult(
                title: "Beta Title",
                summary: "Beta Summary for \(serviceType)"
            )
        }

        retryService.enqueueSummary(for: firstSermon.id)
        retryService.enqueueSummary(for: secondSermon.id)
        retryService.processQueue()

        try await Task.sleep(nanoseconds: 400_000_000)

        let sermons = try context.fetch(FetchDescriptor<Sermon>())
        guard let updatedFirstSermon = sermons.first(where: { $0.id == firstSermon.id }) else {
            Issue.record("Expected first sermon to still exist")
            return
        }
        guard let updatedSecondSermon = sermons.first(where: { $0.id == secondSermon.id }) else {
            Issue.record("Expected second sermon to still exist")
            return
        }

        #expect(updatedFirstSermon.summary?.text == "Alpha Summary for Sunday Service")
        #expect(updatedFirstSermon.summary?.title == "Alpha Title")
        #expect(updatedFirstSermon.title == "Alpha Title")
        #expect(updatedFirstSermon.summaryStatus == "complete")

        #expect(updatedSecondSermon.summary?.text == "Beta Summary for Bible Study")
        #expect(updatedSecondSermon.summary?.title == "Beta Title")
        #expect(updatedSecondSermon.title == "Beta Title")
        #expect(updatedSecondSermon.summaryStatus == "complete")

        let jobs = try context.fetch(FetchDescriptor<ProcessingJob>())
        let completedSummaryJobs = jobs.filter { $0.kind == .summary && $0.status == .complete }
        #expect(completedSummaryJobs.count == 2)
    }

    @MainActor
    @Test func manualSummaryRetryRunsEvenWhenReachabilityStateIsStale() async throws {
        let context = try makeModelContext()

        let transcript = Transcript(text: String(repeating: "Gamma message ", count: 8))
        let sermon = Sermon(
            title: "Gamma Sermon",
            audioFileName: "gamma.m4a",
            date: Date(),
            serviceType: "Midweek",
            transcript: transcript,
            notes: [],
            summary: nil,
            syncStatus: "pending",
            transcriptionStatus: "complete",
            summaryStatus: "failed",
            userId: UUID()
        )
        context.insert(transcript)
        context.insert(sermon)
        try context.save()

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)

        var runnerCallCount = 0
        retryService.summaryRunner = { transcript, serviceType in
            runnerCallCount += 1
            return SummaryGenerationResult(
                title: "Gamma Title",
                summary: "Gamma Summary for \(serviceType) from \(transcript.prefix(5))"
            )
        }

        let accepted = retryService.retrySummaryNow(for: sermon.id)

        try await Task.sleep(nanoseconds: 100_000_000)

        let refreshed = try context.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        #expect(accepted)
        #expect(runnerCallCount == 1)
        #expect(refreshed?.summaryStatus == "complete")
        #expect(refreshed?.summary?.title == "Gamma Title")
        #expect(refreshed?.summary?.text.contains("Gamma Summary for Midweek") == true)

        retryService.summaryRunner = nil
        retryService.basicSummaryGenerator = nil
    }

    @MainActor
    @Test func recoverIncompleteSummariesRequeuesStaleRunningJobsAfterRelaunch() async throws {
        let context = try makeModelContext()

        let transcript = Transcript(text: String(repeating: "Recovered long-form summary text ", count: 16))
        let sermon = Sermon(
            title: "Recovered Sermon",
            audioFileName: "recovered-summary.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            transcript: transcript,
            notes: [],
            summary: nil,
            syncStatus: "pending",
            transcriptionStatus: "complete",
            summaryStatus: "processing",
            userId: UUID()
        )
        let staleJob = ProcessingJob(
            sermonId: sermon.id,
            kind: .summary,
            status: .running,
            attemptCount: 1,
            createdAt: Date().addingTimeInterval(-900),
            updatedAt: Date().addingTimeInterval(-900),
            nextAttemptAt: nil,
            lastAttemptAt: Date().addingTimeInterval(-900),
            lastError: "App terminated mid-summary"
        )

        context.insert(transcript)
        context.insert(sermon)
        context.insert(staleJob)
        try context.save()

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)
        retryService.overrideNetworkAvailability(true)
        defer {
            retryService.summaryRunner = nil
            retryService.basicSummaryGenerator = nil
            retryService.overrideNetworkAvailability(false)
        }

        var runnerCallCount = 0
        retryService.summaryRunner = { transcript, serviceType in
            runnerCallCount += 1
            return SummaryGenerationResult(
                title: "Recovered Summary Title",
                summary: "Recovered summary for \(serviceType) from \(transcript.prefix(12))"
            )
        }

        retryService.recoverIncompleteSummaries()
        retryService.processQueue()

        try await Task.sleep(nanoseconds: 100_000_000)

        let refreshedSermon = try context.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        let refreshedJobs = try context.fetch(FetchDescriptor<ProcessingJob>())
            .filter { $0.sermonId == sermon.id && $0.kind == .summary }

        #expect(runnerCallCount == 1)
        #expect(refreshedSermon?.summaryStatus == "complete")
        #expect(refreshedSermon?.summary?.title == "Recovered Summary Title")
        #expect(refreshedJobs.count == 1)
        #expect(refreshedJobs.first?.status == .complete)
        #expect(refreshedJobs.first?.attemptCount == 1)
    }

    @MainActor
    @Test func recoverIncompleteSummariesRequeuesFailedBackoffJobsForProcessingSermons() async throws {
        let context = try makeModelContext()

        let transcript = Transcript(text: String(repeating: "Queued recovery summary text ", count: 16))
        let sermon = Sermon(
            title: "Queued Recovery Sermon",
            audioFileName: "queued-recovery-summary.m4a",
            date: Date(),
            serviceType: "Bible Study",
            transcript: transcript,
            notes: [],
            summary: nil,
            syncStatus: "pending",
            transcriptionStatus: "complete",
            summaryStatus: "processing",
            userId: UUID()
        )
        let delayedJob = ProcessingJob(
            sermonId: sermon.id,
            kind: .summary,
            status: .failed,
            attemptCount: 1,
            createdAt: Date().addingTimeInterval(-300),
            updatedAt: Date().addingTimeInterval(-300),
            nextAttemptAt: Date().addingTimeInterval(600),
            lastAttemptAt: Date().addingTimeInterval(-300),
            lastError: "Timed out"
        )

        context.insert(transcript)
        context.insert(sermon)
        context.insert(delayedJob)
        try context.save()

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)
        retryService.overrideNetworkAvailability(true)
        defer {
            retryService.summaryRunner = nil
            retryService.basicSummaryGenerator = nil
            retryService.overrideNetworkAvailability(false)
        }

        var runnerCallCount = 0
        retryService.summaryRunner = { transcript, serviceType in
            runnerCallCount += 1
            return SummaryGenerationResult(
                title: "Recovered Backoff Title",
                summary: "Recovered backoff summary for \(serviceType) from \(transcript.prefix(12))"
            )
        }

        retryService.recoverIncompleteSummaries()
        retryService.processQueue()

        try await Task.sleep(nanoseconds: 100_000_000)

        let refreshedSermon = try context.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        let refreshedJob = try context.fetch(FetchDescriptor<ProcessingJob>())
            .first(where: { $0.sermonId == sermon.id && $0.kind == .summary })

        #expect(runnerCallCount == 1)
        #expect(refreshedSermon?.summaryStatus == "complete")
        #expect(refreshedSermon?.summary?.title == "Recovered Backoff Title")
        #expect(refreshedJob?.status == .complete)
        #expect(refreshedJob?.attemptCount == 1)
    }

    @MainActor
    @Test func recoverIncompleteSummariesCreatesJobsForPendingSummariesWithoutExistingJobs() async throws {
        let context = try makeModelContext()

        let transcript = Transcript(text: String(repeating: "Pending summary transcript ", count: 16))
        let sermon = Sermon(
            title: "Pending Summary Sermon",
            audioFileName: "pending-summary.m4a",
            date: Date(),
            serviceType: "Sermon",
            transcript: transcript,
            notes: [],
            summary: nil,
            syncStatus: "pending",
            transcriptionStatus: "complete",
            summaryStatus: "pending",
            userId: UUID()
        )

        context.insert(transcript)
        context.insert(sermon)
        try context.save()

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)
        retryService.overrideNetworkAvailability(true)
        defer {
            retryService.summaryRunner = nil
            retryService.basicSummaryGenerator = nil
            retryService.overrideNetworkAvailability(false)
        }

        var runnerCallCount = 0
        retryService.summaryRunner = { transcript, serviceType in
            runnerCallCount += 1
            return SummaryGenerationResult(
                title: "Pending Recovery Title",
                summary: "Pending recovery summary for \(serviceType) from \(transcript.prefix(12))"
            )
        }

        retryService.recoverIncompleteSummaries()
        retryService.processQueue()

        try await Task.sleep(nanoseconds: 100_000_000)

        let refreshedSermon = try context.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        let refreshedJob = try context.fetch(FetchDescriptor<ProcessingJob>())
            .first(where: { $0.sermonId == sermon.id && $0.kind == .summary })

        #expect(runnerCallCount == 1)
        #expect(refreshedSermon?.summaryStatus == "complete")
        #expect(refreshedSermon?.summary?.title == "Pending Recovery Title")
        #expect(refreshedJob?.status == .complete)
    }

    @MainActor
    @Test func nonRetryableSummaryFailuresFallBackImmediately() async throws {
        let context = try makeModelContext()

        let transcript = Transcript(text: String(repeating: "Long transcript content ", count: 40))
        let sermon = Sermon(
            title: "Fallback Sermon",
            audioFileName: "fallback-summary.m4a",
            date: Date(),
            serviceType: "Conference",
            transcript: transcript,
            notes: [],
            summary: nil,
            syncStatus: "pending",
            transcriptionStatus: "complete",
            summaryStatus: "failed",
            userId: UUID()
        )
        context.insert(transcript)
        context.insert(sermon)
        try context.save()

        let retryService = SummaryRetryService()
        retryService.setModelContext(context)
        defer {
            retryService.summaryRunner = nil
            retryService.basicSummaryGenerator = nil
        }

        var runnerCallCount = 0
        retryService.summaryRunner = { _, _ in
            runnerCallCount += 1
            throw SummaryService.SummaryError.requestRejected(
                413,
                "Text must be less than 150000 characters."
            )
        }

        let accepted = retryService.retrySummaryNow(for: sermon.id)

        try await Task.sleep(nanoseconds: 100_000_000)

        let refreshedSermon = try context.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        let refreshedJob = try context.fetch(FetchDescriptor<ProcessingJob>())
            .first(where: { $0.sermonId == sermon.id && $0.kind == .summary })

        #expect(accepted)
        #expect(runnerCallCount == 1)
        #expect(refreshedSermon?.summaryStatus == "complete")
        #expect(refreshedSermon?.summary?.text.isEmpty == false)
        #expect(refreshedJob?.status == .complete)
        #expect(refreshedJob?.attemptCount == 0)
    }
}
