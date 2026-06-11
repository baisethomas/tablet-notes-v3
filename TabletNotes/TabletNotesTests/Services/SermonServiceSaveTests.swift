import Foundation
import SwiftData
import Testing
@testable import TabletNotes

@MainActor
struct SermonServiceSaveTests {
    private func makeModelContext() throws -> ModelContext {
        UserDefaults.standard.removeObject(forKey: "SermonService.localDataOwnerUserId")
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
        defer { InterruptedRecordingRecoveryStore.clear() }

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
                startedAt: Date().addingTimeInterval(-120),
                userId: currentUser.id
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
        #expect(recoveredSermon.hasPendingSyncWork == true)
        #expect(InterruptedRecordingRecoveryStore.load() == nil)
        #expect(NoteService(sessionId: "interrupted-session").currentNotes.isEmpty)

        try? FileManager.default.removeItem(at: audioURL)
        InterruptedRecordingRecoveryStore.clear()
    }

    @Test func saveSermonReusesRecoveredDraftWhenAudioFileAlreadyExists() async throws {
        let modelContext = try makeModelContext()
        let mockAuthService = MockAuthService()
        let currentUser = MockAuthService.createMockUser()
        mockAuthService.setAuthState(.authenticated(currentUser))
        let authManager = AuthenticationManager(authService: mockAuthService)
        let sermonService = SermonService(modelContext: modelContext, authManager: authManager)

        let audioDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent("recovered-\(UUID().uuidString).m4a")
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: Data(repeating: 0x07, count: 4096))

        let existingSermon = Sermon(
            title: "Recovered Draft",
            audioFileName: audioURL.lastPathComponent,
            date: Date().addingTimeInterval(-120),
            serviceType: "Bible Study",
            transcript: nil,
            notes: [],
            summary: nil,
            syncStatus: "pending",
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            userId: currentUser.id
        )
        modelContext.insert(existingSermon)
        try modelContext.save()
        sermonService.fetchSermons()

        let note = Note(text: "Recovered note", timestamp: 5)
        sermonService.saveSermon(
            title: "Recovered Draft",
            audioFileURL: audioURL,
            date: existingSermon.date,
            serviceType: existingSermon.serviceType,
            transcript: nil,
            notes: [note],
            summary: nil,
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            id: UUID()
        )

        let saveFinished = await waitUntil {
            let sermons = try? modelContext.fetch(FetchDescriptor<Sermon>())
            return sermons?.count == 1 && sermons?.first?.notes.count == 1
        }
        #expect(saveFinished == true)

        let sermons = try modelContext.fetch(FetchDescriptor<Sermon>())
        #expect(sermons.count == 1)
        #expect(sermons.first?.id == existingSermon.id)
        #expect(sermons.first?.notes.count == 1)
        #expect(sermons.first?.notes.first?.text == "Recovered note")

        try? FileManager.default.removeItem(at: audioURL)
    }

    @Test func deleteAllLocalUserDataRemovesSermonRowsAudioOrphansAndNoteSessions() async throws {
        InterruptedRecordingRecoveryStore.clear()

        let modelContext = try makeModelContext()
        let mockAuthService = MockAuthService()
        let currentUser = MockAuthService.createMockUser()
        mockAuthService.setAuthState(.authenticated(currentUser))
        let authManager = AuthenticationManager(authService: mockAuthService)

        let audioDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let sermonAudioURL = audioDirectory.appendingPathComponent("sermon-\(UUID().uuidString).m4a")
        let orphanAudioURL = audioDirectory.appendingPathComponent("orphan-\(UUID().uuidString).m4a")
        #expect(FileManager.default.createFile(atPath: sermonAudioURL.path, contents: Data(repeating: 0x01, count: 1024)))
        #expect(FileManager.default.createFile(atPath: orphanAudioURL.path, contents: Data(repeating: 0x02, count: 1024)))

        let sermon = Sermon(
            title: "Delete Me",
            audioFileName: sermonAudioURL.lastPathComponent,
            date: Date(),
            serviceType: "Sunday Service",
            userId: currentUser.id
        )
        modelContext.insert(sermon)
        try modelContext.save()

        let sermonService = SermonService(modelContext: modelContext, authManager: authManager)
        #expect(sermonService.sermons.count == 1)

        let noteService = NoteService(sessionId: "delete-account-session")
        noteService.addNote(text: "Pending note", timestamp: 1)
        InterruptedRecordingRecoveryStore.save(
            InterruptedRecordingManifest(
                sessionId: "delete-account-session",
                serviceType: "Sunday Service",
                audioFileName: orphanAudioURL.lastPathComponent,
                startedAt: Date(),
                userId: currentUser.id
            )
        )

        sermonService.deleteAllLocalUserData()

        let remainingSermons = try modelContext.fetch(FetchDescriptor<Sermon>())
        #expect(remainingSermons.isEmpty)
        #expect(FileManager.default.fileExists(atPath: sermonAudioURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: orphanAudioURL.path) == false)
        #expect(InterruptedRecordingRecoveryStore.load() == nil)
        #expect(NoteService(sessionId: "delete-account-session").currentNotes.isEmpty)
        #expect(sermonService.sermons.isEmpty)
    }

    @Test func signOutClearsLocalDataAndDoesNotReassignOrphansToNextUser() async throws {
        let modelContext = try makeModelContext()
        let mockAuthService = MockAuthService()
        let userA = MockAuthService.createMockUser(email: "user-a@test.com", name: "User A")
        mockAuthService.setAuthState(.authenticated(userA))
        let authManager = AuthenticationManager(authService: mockAuthService)

        let userASermon = Sermon(
            title: "User A Sermon",
            audioFileName: "user-a.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            userId: userA.id
        )
        let orphanSermon = Sermon(
            title: "Orphan Sermon",
            audioFileName: "orphan.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            userId: nil
        )
        modelContext.insert(userASermon)
        modelContext.insert(orphanSermon)
        try modelContext.save()

        let sermonService = SermonService(modelContext: modelContext, authManager: authManager)
        #expect(sermonService.sermons.count == 1)
        #expect(sermonService.sermons.first?.title == "User A Sermon")

        try await authManager.signOut()

        let signOutFinished = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            sermonService.sermons.isEmpty
        }
        #expect(signOutFinished == true)

        let remainingAfterSignOut = try modelContext.fetch(FetchDescriptor<Sermon>())
        #expect(remainingAfterSignOut.isEmpty)

        let userB = MockAuthService.createMockUser(email: "user-b@test.com", name: "User B")
        mockAuthService.setAuthState(.authenticated(userB))

        let userBLoaded = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            authManager.currentUser?.id == userB.id
        }
        #expect(userBLoaded == true)
        #expect(sermonService.sermons.isEmpty)

        let orphanAfterUserB = try modelContext.fetch(FetchDescriptor<Sermon>())
        #expect(orphanAfterUserB.isEmpty)
    }

    @Test func failedSignOutDoesNotWipeLocalData() async throws {
        let modelContext = try makeModelContext()
        let mockAuthService = MockAuthService()
        let currentUser = MockAuthService.createMockUser()
        mockAuthService.setAuthState(.authenticated(currentUser))
        let authManager = AuthenticationManager(authService: mockAuthService)

        let sermon = Sermon(
            title: "Keep Me",
            audioFileName: "keep-me.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            userId: currentUser.id
        )
        modelContext.insert(sermon)
        try modelContext.save()

        let sermonService = SermonService(modelContext: modelContext, authManager: authManager)
        #expect(sermonService.sermons.count == 1)

        mockAuthService.setShouldFailNextCall(true, error: .networkError)
        do {
            try await authManager.signOut()
        } catch {
            // Expected failed sign-out
        }

        let preserved = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            sermonService.sermons.count == 1
        }
        #expect(preserved == true)

        let remaining = try modelContext.fetch(FetchDescriptor<Sermon>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.title == "Keep Me")
    }

    @Test func interruptedRecordingManifestFromAnotherUserIsNotRecovered() async throws {
        InterruptedRecordingRecoveryStore.clear()
        defer { InterruptedRecordingRecoveryStore.clear() }

        let modelContext = try makeModelContext()
        let mockAuthService = MockAuthService()
        let userA = MockAuthService.createMockUser(email: "user-a@test.com", name: "User A")
        let userB = MockAuthService.createMockUser(email: "user-b@test.com", name: "User B")

        let audioDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let audioURL = audioDirectory.appendingPathComponent("foreign-\(UUID().uuidString).m4a")
        _ = FileManager.default.createFile(atPath: audioURL.path, contents: Data(repeating: 0x03, count: 4096))
        defer { try? FileManager.default.removeItem(at: audioURL) }

        InterruptedRecordingRecoveryStore.save(
            InterruptedRecordingManifest(
                sessionId: "foreign-session",
                serviceType: "Sermon",
                audioFileName: audioURL.lastPathComponent,
                startedAt: Date(),
                userId: userA.id
            )
        )

        mockAuthService.setAuthState(.authenticated(userB))
        let authManager = AuthenticationManager(authService: mockAuthService)
        let sermonService = SermonService(modelContext: modelContext, authManager: authManager)

        #expect(sermonService.sermons.isEmpty)
        #expect(InterruptedRecordingRecoveryStore.load() == nil)

        let sermons = try modelContext.fetch(FetchDescriptor<Sermon>())
        #expect(sermons.isEmpty)
    }

    @Test func migrationRecoveryRequiresMatchingOwnership() async throws {
        let modelContext = try makeModelContext()
        let mockAuthService = MockAuthService()
        let userA = MockAuthService.createMockUser(email: "user-a@test.com", name: "User A")
        let userB = MockAuthService.createMockUser(email: "user-b@test.com", name: "User B")

        UserDefaults.standard.set(userB.id.uuidString, forKey: "SermonService.localDataOwnerUserId")
        UserDefaults.standard.set(userA.id.uuidString, forKey: "DataMigration.recoveryOwnerUserId")
        UserDefaults.standard.set(true, forKey: "has_recoverable_audio_files")
        defer {
            DataMigration.clearRecoveryFlags()
            UserDefaults.standard.removeObject(forKey: "SermonService.localDataOwnerUserId")
        }

        mockAuthService.setAuthState(.authenticated(userB))
        let authManager = AuthenticationManager(authService: mockAuthService)
        let sermonService = SermonService(modelContext: modelContext, authManager: authManager)

        #expect(sermonService.sermons.isEmpty)
        #expect(DataMigration.hasRecoverableAudioFiles() == false)
        #expect(DataMigration.recoveryOwnerUserId() == nil)
    }
}
