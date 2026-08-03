import Foundation
import SwiftData
import Testing
@testable import TabletNotes

struct TranscriptionRetryServiceRegressionTests {

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

    /// Regression for TAB-64: `startProcessing` used to read `nextJob.id` /
    /// `nextJob.sermonId` from the captured @Model *inside* the completion
    /// closure, after the runner's async gap. The fix snapshots both ids as
    /// value types before the runner starts so completion never touches the
    /// original `ProcessingJob` reference. NOTE: the EXC_BREAKPOINT this
    /// caused in production requires a real backing-store invalidation
    /// (container teardown) that an in-memory ModelContext can't reproduce —
    /// ARC keeps a deleted @Model's already-read properties accessible, so
    /// this test can't fail-without-fix the way the crash itself would. What
    /// it does verify: if the job is gone by completion time (deleted mid-
    /// flight), the service must not resurrect it or apply a stale result —
    /// exercising the same fetch-by-snapshotted-id path the fix relies on.
    @MainActor
    @Test func startProcessingSurvivesJobInvalidationDuringRunnerGap() async throws {
        let context = try makeModelContext()

        let audioDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent("invalidation-sermon.m4a")
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: Data(repeating: 0x01, count: 4096))
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let sermon = Sermon(
            title: "Invalidation Sermon",
            audioFileName: audioURL.lastPathComponent,
            date: Date(),
            serviceType: "Sunday Service",
            transcript: nil,
            notes: [],
            summary: nil,
            syncStatus: "pending",
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            userId: UUID()
        )
        context.insert(sermon)
        try context.save()

        let retryService = TranscriptionRetryService()
        retryService.setModelContext(context)
        retryService.overrideNetworkAvailability(true)
        defer {
            retryService.transcriptionRunner = nil
            retryService.overrideNetworkAvailability(false)
        }

        var runnerCallCount = 0
        retryService.transcriptionRunner = { _, completion in
            runnerCallCount += 1
            // Simulate the job's backing data being invalidated while the
            // (minutes-long, in production) transcription call is in flight.
            if let staleJob = try? context.fetch(FetchDescriptor<ProcessingJob>()).first {
                context.delete(staleJob)
                try? context.save()
            }
            completion(.success(("Transcribed text", [])))
        }

        retryService.enqueueTranscription(for: sermon.id)

        try await Task.sleep(nanoseconds: 200_000_000)

        // No crash reaching this point is the primary assertion. The job was
        // deleted before completion ran, so fetchJob(withId:) correctly finds
        // nothing and the service must not resurrect it or apply the result.
        let refreshedSermon = try context.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        let jobs = try context.fetch(FetchDescriptor<ProcessingJob>())

        #expect(runnerCallCount == 1)
        #expect(jobs.isEmpty)
        #expect(refreshedSermon?.transcriptionStatus == "processing")
        #expect(refreshedSermon?.transcript == nil)
    }
}
