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
}
