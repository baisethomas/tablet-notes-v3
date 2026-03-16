import Foundation
import SwiftData
import Testing
@testable import TabletNotes

@MainActor
struct SyncServiceMergeTests {
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

    @Test func updateLocalSermonPreservesDirtyLocalNotesWhileMergingRemoteNotes() throws {
        let modelContext = try makeModelContext()
        let syncService = SyncService(
            modelContext: modelContext,
            supabaseService: MockSupabaseService(),
            authService: AuthenticationManager.shared
        )

        let sermon = Sermon(
            title: "Local Sermon",
            audioFileName: "local.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "pending",
            transcriptionStatus: "pending",
            summaryStatus: "pending",
            updatedAt: Date(),
            needsSync: true
        )
        modelContext.insert(sermon)

        let dirtyNoteId = UUID()
        let syncedNoteId = UUID()
        let remoteOnlyNoteId = UUID()

        let dirtyNote = Note(
            id: dirtyNoteId,
            text: "Local dirty note",
            timestamp: 12,
            remoteId: "remote-dirty-note",
            updatedAt: Date(),
            needsSync: true
        )
        dirtyNote.sermon = sermon
        modelContext.insert(dirtyNote)
        sermon.notes.append(dirtyNote)

        let syncedNote = Note(
            id: syncedNoteId,
            text: "Old synced note",
            timestamp: 24,
            remoteId: "remote-synced-note",
            updatedAt: Date().addingTimeInterval(-600),
            needsSync: false
        )
        syncedNote.sermon = sermon
        modelContext.insert(syncedNote)
        sermon.notes.append(syncedNote)

        let remoteSermon = RemoteSermonData(
            id: "remote-sermon",
            localId: sermon.id,
            title: "Remote Sermon",
            audioFileURL: URL(fileURLWithPath: "/tmp/remote.m4a"),
            audioFilePath: nil,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: nil,
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            isArchived: false,
            userId: UUID(),
            updatedAt: Date().addingTimeInterval(300),
            notes: [
                RemoteNoteData(
                    id: "remote-dirty-note",
                    localId: dirtyNoteId,
                    text: "Remote dirty overwrite",
                    timestamp: 99
                ),
                RemoteNoteData(
                    id: "remote-synced-note",
                    localId: syncedNoteId,
                    text: "Remote synced note",
                    timestamp: 30
                ),
                RemoteNoteData(
                    id: "remote-new-note",
                    localId: remoteOnlyNoteId,
                    text: "Remote added note",
                    timestamp: 45
                )
            ],
            transcript: nil,
            summary: nil
        )

        syncService.updateLocalSermon(sermon, with: remoteSermon)

        #expect(sermon.notes.count == 3)

        guard let mergedDirtyNote = sermon.notes.first(where: { $0.id == dirtyNoteId }) else {
            Issue.record("Expected dirty local note to remain after merge")
            return
        }

        #expect(mergedDirtyNote.text == "Local dirty note")
        #expect(mergedDirtyNote.timestamp == 12)
        #expect(mergedDirtyNote.needsSync == true)

        guard let mergedSyncedNote = sermon.notes.first(where: { $0.id == syncedNoteId }) else {
            Issue.record("Expected synced note to remain after merge")
            return
        }

        #expect(mergedSyncedNote.text == "Remote synced note")
        #expect(mergedSyncedNote.timestamp == 30)
        #expect(mergedSyncedNote.needsSync == false)

        guard let remoteOnlyNote = sermon.notes.first(where: { $0.id == remoteOnlyNoteId }) else {
            Issue.record("Expected remote-only note to be added during merge")
            return
        }

        #expect(remoteOnlyNote.text == "Remote added note")
        #expect(remoteOnlyNote.remoteId == "remote-new-note")
    }

    @Test func updateLocalSermonPreservesDirtyLocalSummaryWhenRemoteParentIsNewer() throws {
        let modelContext = try makeModelContext()
        let syncService = SyncService(
            modelContext: modelContext,
            supabaseService: MockSupabaseService(),
            authService: AuthenticationManager.shared
        )

        let sermon = Sermon(
            title: "Local Sermon",
            audioFileName: "local.m4a",
            date: Date(),
            serviceType: "Bible Study",
            syncStatus: "pending",
            transcriptionStatus: "complete",
            summaryStatus: "pending",
            updatedAt: Date(),
            needsSync: true
        )
        modelContext.insert(sermon)

        let localSummary = Summary(
            id: UUID(),
            title: "Local Summary Title",
            text: "Local summary body",
            type: "Bible Study",
            status: "complete",
            remoteId: "remote-summary",
            updatedAt: Date(),
            needsSync: true
        )
        modelContext.insert(localSummary)
        sermon.summary = localSummary
        sermon.summaryPreviewText = Sermon.makeSummaryPreview(from: localSummary.text)

        let remoteSermon = RemoteSermonData(
            id: "remote-sermon",
            localId: sermon.id,
            title: "Remote Sermon Title",
            audioFileURL: URL(fileURLWithPath: "/tmp/remote.m4a"),
            audioFilePath: nil,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: nil,
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            isArchived: false,
            userId: UUID(),
            updatedAt: Date().addingTimeInterval(300),
            notes: nil,
            transcript: nil,
            summary: RemoteSummaryData(
                id: "remote-summary",
                localId: localSummary.id,
                title: "Remote Summary Title",
                text: "Remote summary body",
                type: "Bible Study",
                status: "complete"
            )
        )

        syncService.updateLocalSermon(sermon, with: remoteSermon)

        #expect(sermon.summary?.title == "Local Summary Title")
        #expect(sermon.summary?.text == "Local summary body")
        #expect(sermon.summary?.needsSync == true)
    }
}
