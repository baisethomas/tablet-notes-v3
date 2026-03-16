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
}
