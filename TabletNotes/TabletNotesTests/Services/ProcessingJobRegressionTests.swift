import Foundation
import Testing
import SwiftData
@testable import TabletNotes

struct ProcessingJobRegressionTests {

    @MainActor
    @Test func transcriptionRetryUpdatesExistingSermonAndPreservesNotes() async throws {
        let schema = Schema([
            Sermon.self,
            Note.self,
            Transcript.self,
            Summary.self,
            ProcessingJob.self,
            TranscriptSegment.self,
            User.self,
            UserNotificationSettings.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)

        let note = Note(text: "Preserve this note", timestamp: 42)
        let audioDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent("pending-sermon.m4a")
        let audioData = Data(repeating: 0x01, count: 4096)
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: audioData)

        let sermon = Sermon(
            title: "Pending Sermon",
            audioFileName: audioURL.lastPathComponent,
            date: Date(),
            serviceType: "Sermon",
            transcript: nil,
            notes: [],
            summary: nil,
            syncStatus: "pending",
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            userId: UUID()
        )

        note.sermon = sermon
        sermon.notes.append(note)

        context.insert(sermon)
        context.insert(note)
        try context.save()

        let retryService = TranscriptionRetryService()
        retryService.setModelContext(context)
        retryService.overrideNetworkAvailability(true)
        retryService.transcriptionRunner = { _, completion in
            completion(.success((
                "Recovered transcript",
                [TranscriptSegment(text: "Recovered transcript", startTime: 0, endTime: 4)]
            )))
        }
        retryService.summaryEnqueuer = { _ in }

        retryService.enqueueTranscription(for: sermon.id)
        retryService.processQueue()

        try await Task.sleep(nanoseconds: 100_000_000)

        let sermons = try context.fetch(FetchDescriptor<Sermon>())
        #expect(sermons.count == 1)

        guard let updatedSermon = sermons.first else {
            Issue.record("Expected sermon to exist after retry")
            return
        }

        #expect(updatedSermon.notes.count == 1)
        #expect(updatedSermon.notes.first?.text == "Preserve this note")
        #expect(updatedSermon.notes.first?.timestamp == 42)
        #expect(updatedSermon.transcript?.text == "Recovered transcript")
        #expect(updatedSermon.transcriptionStatus == "complete")
        #expect(updatedSermon.summaryStatus == "processing")

        let jobs = try context.fetch(FetchDescriptor<ProcessingJob>())
        let transcriptionJobs = jobs.filter { $0.kind == .transcription && $0.sermonId == sermon.id }
        #expect(transcriptionJobs.count == 1)
        #expect(transcriptionJobs.first?.status == .complete)

        retryService.transcriptionRunner = nil
        retryService.summaryEnqueuer = nil
        retryService.overrideNetworkAvailability(false)
        try? FileManager.default.removeItem(at: audioURL)
    }

    @MainActor
    @Test func manualTranscriptionRetryRunsEvenWhenReachabilityStateIsStale() async throws {
        let schema = Schema([
            Sermon.self,
            Note.self,
            Transcript.self,
            Summary.self,
            ProcessingJob.self,
            TranscriptSegment.self,
            User.self,
            UserNotificationSettings.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)

        let audioDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent("stale-reachability-sermon.m4a")
        let audioData = Data(repeating: 0x02, count: 4096)
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: audioData)

        let sermon = Sermon(
            title: "Retry Sermon",
            audioFileName: audioURL.lastPathComponent,
            date: Date(),
            serviceType: "Sermon",
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

        var runnerCallCount = 0
        retryService.transcriptionRunner = { _, completion in
            runnerCallCount += 1
            completion(.success((
                "Immediate retry transcript",
                [TranscriptSegment(text: "Immediate retry transcript", startTime: 0, endTime: 2)]
            )))
        }
        retryService.summaryEnqueuer = { _ in }

        let accepted = retryService.retryTranscriptionNow(for: sermon.id)

        try await Task.sleep(nanoseconds: 100_000_000)

        let refreshed = try context.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        #expect(accepted)
        #expect(runnerCallCount == 1)
        #expect(refreshed?.transcriptionStatus == "complete")
        #expect(refreshed?.transcript?.text == "Immediate retry transcript")

        retryService.transcriptionRunner = nil
        retryService.summaryEnqueuer = nil
        try? FileManager.default.removeItem(at: audioURL)
    }

    @MainActor
    @Test func transcriptionCompletionStartsSummaryEvenWhenSummaryReachabilityStateIsStale() async throws {
        let schema = Schema([
            Sermon.self,
            Note.self,
            Transcript.self,
            Summary.self,
            ProcessingJob.self,
            TranscriptSegment.self,
            User.self,
            UserNotificationSettings.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)

        let audioDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent("summary-handoff-sermon.m4a")
        let audioData = Data(repeating: 0x03, count: 4096)
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: audioData)

        let sermon = Sermon(
            title: "Summary Handoff Sermon",
            audioFileName: audioURL.lastPathComponent,
            date: Date(),
            serviceType: "Sermon",
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

        let transcriptionRetryService = TranscriptionRetryService()
        transcriptionRetryService.setModelContext(context)
        transcriptionRetryService.transcriptionRunner = { _, completion in
            completion(.success((
                "Transcript ready for summary",
                [TranscriptSegment(text: "Transcript ready for summary", startTime: 0, endTime: 2)]
            )))
        }

        let summaryRetryService = SummaryRetryService()
        summaryRetryService.setModelContext(context)
        summaryRetryService.summaryRunner = { _, serviceType in
            SummaryGenerationResult(
                title: "Completed Summary",
                summary: "Summary created for \(serviceType)"
            )
        }

        transcriptionRetryService.summaryEnqueuer = { sermonId in
            _ = summaryRetryService.retrySummaryNow(for: sermonId)
        }

        let accepted = transcriptionRetryService.retryTranscriptionNow(for: sermon.id)

        try await Task.sleep(nanoseconds: 200_000_000)

        let refreshed = try context.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        #expect(accepted)
        #expect(refreshed?.transcriptionStatus == "complete")
        #expect(refreshed?.summaryStatus == "complete")
        #expect(refreshed?.summary?.title == "Completed Summary")
        #expect(refreshed?.summary?.text == "Summary created for Sermon")

        transcriptionRetryService.transcriptionRunner = nil
        transcriptionRetryService.summaryEnqueuer = nil
        summaryRetryService.summaryRunner = nil
        summaryRetryService.basicSummaryGenerator = nil
        try? FileManager.default.removeItem(at: audioURL)
    }

    @MainActor
    @Test func recoverIncompleteTranscriptionsRequeuesStaleRunningJobsAfterRelaunch() async throws {
        let schema = Schema([
            Sermon.self,
            Note.self,
            Transcript.self,
            Summary.self,
            ProcessingJob.self,
            TranscriptSegment.self,
            User.self,
            UserNotificationSettings.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)

        let audioDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent("stale-running-job-sermon.m4a")
        let audioData = Data(repeating: 0x04, count: 4096)
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: audioData)

        let sermon = Sermon(
            title: "Recovered Relaunch Sermon",
            audioFileName: audioURL.lastPathComponent,
            date: Date(),
            serviceType: "Sermon",
            transcript: nil,
            notes: [],
            summary: nil,
            syncStatus: "pending",
            transcriptionStatus: "processing",
            summaryStatus: "pending",
            userId: UUID()
        )
        let staleJob = ProcessingJob(
            sermonId: sermon.id,
            kind: .transcription,
            status: .running,
            attemptCount: 1,
            createdAt: Date().addingTimeInterval(-120),
            updatedAt: Date().addingTimeInterval(-120),
            lastAttemptAt: Date().addingTimeInterval(-120)
        )

        context.insert(sermon)
        context.insert(staleJob)
        try context.save()

        let retryService = TranscriptionRetryService()
        retryService.setModelContext(context)
        retryService.overrideNetworkAvailability(true)
        retryService.transcriptionRunner = { _, completion in
            completion(.success((
                "Recovered after relaunch",
                [TranscriptSegment(text: "Recovered after relaunch", startTime: 0, endTime: 2)]
            )))
        }
        retryService.summaryEnqueuer = { _ in }

        retryService.recoverIncompleteTranscriptions()
        retryService.processQueue()

        try await Task.sleep(nanoseconds: 100_000_000)

        let refreshed = try context.fetch(FetchDescriptor<Sermon>()).first(where: { $0.id == sermon.id })
        let jobs = try context.fetch(FetchDescriptor<ProcessingJob>())
        let transcriptionJobs = jobs.filter { $0.kind == .transcription && $0.sermonId == sermon.id }

        #expect(refreshed?.transcriptionStatus == "complete")
        #expect(refreshed?.transcript?.text == "Recovered after relaunch")
        #expect(transcriptionJobs.count == 1)
        #expect(transcriptionJobs.first?.status == .complete)
        #expect(transcriptionJobs.first?.attemptCount == 1)

        retryService.transcriptionRunner = nil
        retryService.summaryEnqueuer = nil
        retryService.overrideNetworkAvailability(false)
        try? FileManager.default.removeItem(at: audioURL)
    }
}
