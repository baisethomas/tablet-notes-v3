import Foundation
import SwiftData
import Testing
@testable import TabletNotes

@MainActor
struct SermonServiceSaveTests {
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

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollIntervalNanoseconds: UInt64 = 25_000_000,
        condition: () -> Bool
    ) async -> Bool {
        var waited: UInt64 = 0

        while waited < timeoutNanoseconds {
            if condition() {
                return true
            }

            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            waited += pollIntervalNanoseconds
        }

        return condition()
    }

    @Test func saveSermonMetadataUpdatePreservesUnchangedChildEntities() async throws {
        let modelContext = try makeModelContext()
        let mockAuthService = MockAuthService()
        let currentUser = MockAuthService.createMockUser()
        mockAuthService.setAuthState(.authenticated(currentUser))
        let authManager = AuthenticationManager(authService: mockAuthService)
        let sermonService = SermonService(modelContext: modelContext, authManager: authManager)

        let sermonID = UUID()
        let sermonDate = Date()
        let existingNote = Note(
            id: UUID(),
            text: "Original note",
            timestamp: 42,
            remoteId: "remote-note",
            updatedAt: Date().addingTimeInterval(-300),
            needsSync: false
        )
        let existingTranscript = Transcript(
            id: UUID(),
            text: "Existing transcript",
            segments: [],
            remoteId: "remote-transcript",
            updatedAt: Date().addingTimeInterval(-300),
            needsSync: false
        )
        let existingSummary = Summary(
            id: UUID(),
            title: "Existing Summary",
            text: "Existing summary text",
            type: "Sunday Service",
            status: "complete",
            remoteId: "remote-summary",
            updatedAt: Date().addingTimeInterval(-300),
            needsSync: false
        )
        let sermon = Sermon(
            id: sermonID,
            title: "Original Title",
            audioFileName: "sermon.m4a",
            date: sermonDate,
            serviceType: "Sunday Service",
            speaker: "Original Speaker",
            transcript: existingTranscript,
            notes: [existingNote],
            summary: existingSummary,
            syncStatus: "synced",
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            isArchived: false,
            userId: currentUser.id,
            remoteId: "remote-sermon",
            updatedAt: Date().addingTimeInterval(-300),
            needsSync: false
        )
        existingNote.sermon = sermon
        modelContext.insert(existingTranscript)
        modelContext.insert(existingSummary)
        modelContext.insert(existingNote)
        modelContext.insert(sermon)
        try modelContext.save()
        sermonService.fetchSermons()

        sermonService.saveSermon(
            title: "Updated Title",
            audioFileURL: sermon.audioFileURL,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: sermon.speaker,
            transcript: sermon.transcript,
            notes: sermon.notes,
            summary: sermon.summary,
            transcriptionStatus: sermon.transcriptionStatus,
            summaryStatus: sermon.summaryStatus,
            id: sermon.id
        )

        let saveFinished = await waitUntil {
            let descriptor = FetchDescriptor<Sermon>(predicate: #Predicate<Sermon> { sermon in
                sermon.id == sermonID
            })
            return (try? modelContext.fetch(descriptor).first?.title) == "Updated Title"
        }
        #expect(saveFinished == true)

        let descriptor = FetchDescriptor<Sermon>(predicate: #Predicate<Sermon> { sermon in
            sermon.id == sermonID
        })
        guard let updatedSermon = try modelContext.fetch(descriptor).first else {
            Issue.record("Expected updated sermon to exist")
            return
        }

        #expect(updatedSermon.notes.count == 1)
        #expect(updatedSermon.notes.first?.id == existingNote.id)
        #expect(updatedSermon.notes.first?.text == "Original note")
        #expect(updatedSermon.notes.first?.needsSync == false)
        #expect(updatedSermon.notesNeedSync == false)
        #expect(updatedSermon.transcript?.id == existingTranscript.id)
        #expect(updatedSermon.transcript?.needsSync == false)
        #expect(updatedSermon.transcriptNeedsSync == false)
        #expect(updatedSermon.summary?.id == existingSummary.id)
        #expect(updatedSermon.summary?.needsSync == false)
        #expect(updatedSermon.summaryNeedsSync == false)
        #expect(updatedSermon.metadataNeedsSync == true)
    }

    @Test func interruptedRecordingRecoveryCreatesDraftEvenWhenExistingSermonsArePresent() async throws {
        InterruptedRecordingRecoveryStore.clear()

        let modelContext = try makeModelContext()
        let mockAuthService = MockAuthService()
        let currentUser = MockAuthService.createMockUser()
        mockAuthService.setAuthState(.authenticated(currentUser))
        let authManager = AuthenticationManager(authService: mockAuthService)

        let existingSermon = Sermon(
            title: "Existing Sermon",
            audioFileName: "existing.m4a",
            date: Date().addingTimeInterval(-3600),
            serviceType: "Sunday Service",
            transcript: nil,
            notes: [],
            summary: nil,
            syncStatus: "synced",
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            userId: currentUser.id
        )
        modelContext.insert(existingSermon)
        try modelContext.save()

        let audioDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent("interrupted-\(UUID().uuidString).m4a")
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: Data(repeating: 0x05, count: 4096))

        let noteService = NoteService(sessionId: "interrupted-session")
        noteService.addNote(text: "Recovered note", timestamp: 12)

        InterruptedRecordingRecoveryStore.save(
            InterruptedRecordingManifest(
                sessionId: "interrupted-session",
                serviceType: "Bible Study",
                audioFileName: audioURL.lastPathComponent,
                startedAt: Date().addingTimeInterval(-120)
            )
        )

        let sermonService = SermonService(modelContext: modelContext, authManager: authManager)

        let allSermons = sermonService.sermons
        #expect(allSermons.count == 2)

        guard let recoveredSermon = allSermons.first(where: { $0.audioFileName == audioURL.lastPathComponent }) else {
            Issue.record("Expected interrupted recording to be recovered into a sermon")
            try? FileManager.default.removeItem(at: audioURL)
            InterruptedRecordingRecoveryStore.clear()
            return
        }

        #expect(recoveredSermon.serviceType == "Bible Study")
        #expect(recoveredSermon.transcriptionStatus == "pending")
        #expect(recoveredSermon.summaryStatus == "pending")
        #expect(recoveredSermon.notes.count == 1)
        #expect(recoveredSermon.notes.first?.text == "Recovered note")
        #expect(InterruptedRecordingRecoveryStore.load() == nil)
        #expect(NoteService(sessionId: "interrupted-session").currentNotes.isEmpty)

        try? FileManager.default.removeItem(at: audioURL)
        InterruptedRecordingRecoveryStore.clear()
    }
}
