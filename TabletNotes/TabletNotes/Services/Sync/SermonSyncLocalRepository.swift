import Foundation
import SwiftData

@MainActor
protocol SermonSyncLocalRepositoryProtocol: AnyObject {
    func sermonsNeedingSync() throws -> [Sermon]
    func syncData(for sermon: Sermon) -> SermonSyncData
    func markSermonSynced(_ sermon: Sermon, remoteId: String?, syncedAt: Date, scopes: SermonSyncScopes) throws
    func findSermon(remoteId: String) throws -> Sermon?
    func refreshSermon(id: UUID) throws -> Sermon?
    func markAudioDownloaded(fileName: String, for sermonId: UUID) throws
    func updateLocalSermon(_ sermon: Sermon, with remoteData: RemoteSermonData)
    func createLocalSermon(from remoteData: RemoteSermonData, audioFileURL: URL) throws
    func resetCloudSyncState() throws
    func save() throws
}

@MainActor
final class SermonSyncLocalRepository: SermonSyncLocalRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func sermonsNeedingSync() throws -> [Sermon] {
        try modelContext.fetch(FetchDescriptor<Sermon>())
            .filter(\.hasPendingSyncWork)
    }

    func syncData(for sermon: Sermon) -> SermonSyncData {
        let isCreate = sermon.remoteId?.isEmpty != false
        let legacyPendingMarker = sermon.needsSync &&
            !sermon.metadataNeedsSync &&
            !sermon.notesNeedSync &&
            !sermon.transcriptNeedsSync &&
            !sermon.summaryNeedsSync &&
            !sermon.notes.contains(where: \.needsSync) &&
            sermon.transcript?.needsSync != true &&
            sermon.summary?.needsSync != true

        let scopes = SermonSyncScopes(
            metadata: isCreate || sermon.metadataNeedsSync || legacyPendingMarker,
            notes: isCreate || sermon.notesNeedSync || sermon.notes.contains(where: \.needsSync),
            transcript: isCreate || sermon.transcriptNeedsSync || sermon.transcript?.needsSync == true,
            summary: isCreate || sermon.summaryNeedsSync || sermon.summary?.needsSync == true
        )

        let notesSnapshot = sermon.notes.map { note in
            NoteSyncPayload(id: note.id, text: note.text, timestamp: note.timestamp)
        }
        let transcriptSnapshot = sermon.transcript.map { transcript in
            TranscriptSyncPayload(id: transcript.id, text: transcript.text)
        }
        let summarySnapshot = sermon.summary.map { summary in
            SummarySyncPayload(
                id: summary.id,
                title: summary.title,
                text: summary.text,
                type: summary.type,
                status: summary.status
            )
        }

        return SermonSyncData(
            id: sermon.id,
            title: sermon.title,
            audioFileURL: sermon.audioFileURL,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: sermon.speaker,
            transcriptionStatus: sermon.transcriptionStatus,
            summaryStatus: sermon.summaryStatus,
            isArchived: sermon.isArchived,
            userId: sermon.userId,
            updatedAt: sermon.updatedAt ?? Date(),
            notes: scopes.notes ? notesSnapshot : nil,
            transcript: scopes.transcript ? transcriptSnapshot : nil,
            summary: scopes.summary ? summarySnapshot : nil,
            scopes: scopes
        )
    }

    func markSermonSynced(
        _ sermon: Sermon,
        remoteId: String? = nil,
        syncedAt: Date = Date(),
        scopes: SermonSyncScopes
    ) throws {
        if let remoteId, !remoteId.isEmpty {
            sermon.remoteId = remoteId
        }

        sermon.lastSyncedAt = syncedAt
        sermon.syncStatus = "synced"
        sermon.clearPendingSync(
            metadata: scopes.metadata,
            notes: scopes.notes,
            transcript: scopes.transcript,
            summary: scopes.summary
        )
        markChildEntitiesSynced(for: sermon, syncedAt: syncedAt, scopes: scopes)
        sermon.refreshPendingSyncState()
        try modelContext.save()
    }

    func findSermon(remoteId: String) throws -> Sermon? {
        let descriptor = FetchDescriptor<Sermon>(
            predicate: #Predicate<Sermon> { sermon in
                sermon.remoteId == remoteId
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    func refreshSermon(id: UUID) throws -> Sermon? {
        let descriptor = FetchDescriptor<Sermon>(
            predicate: #Predicate<Sermon> { sermon in
                sermon.id == id
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    func markAudioDownloaded(fileName: String, for sermonId: UUID) throws {
        guard let sermon = try refreshSermon(id: sermonId) else { return }
        sermon.audioFileName = fileName
        try modelContext.save()
    }

    func updateLocalSermon(_ sermon: Sermon, with remoteData: RemoteSermonData) {
        print("[SyncService] 🔄 Updating local sermon: \(remoteData.title)")

        if sermon.metadataNeedsSync {
            print("[SyncService] ⚠️ Preserving dirty local sermon metadata")
        } else {
            sermon.title = remoteData.title
            sermon.serviceType = remoteData.serviceType
            sermon.speaker = remoteData.speaker
            sermon.isArchived = remoteData.isArchived
            sermon.transcriptionStatus = remoteData.transcriptionStatus
            sermon.summaryStatus = remoteData.summaryStatus
        }
        sermon.updatedAt = remoteData.updatedAt
        sermon.lastSyncedAt = Date()
        sermon.syncStatus = "synced"

        mergeRemoteNotes(remoteData.notes, into: sermon, remoteUpdatedAt: remoteData.updatedAt)
        mergeRemoteTranscript(remoteData.transcript, into: sermon, remoteUpdatedAt: remoteData.updatedAt)
        mergeRemoteSummary(remoteData.summary, into: sermon, remoteUpdatedAt: remoteData.updatedAt)
    }

    func createLocalSermon(from remoteData: RemoteSermonData, audioFileURL: URL) throws {
        print("[SyncService] 📥 Creating local sermon from remote data: \(remoteData.title)")

        let sermon = Sermon(
            id: remoteData.localId,
            title: remoteData.title,
            audioFileURL: audioFileURL,
            date: remoteData.date,
            serviceType: remoteData.serviceType,
            speaker: remoteData.speaker,
            syncStatus: "synced",
            transcriptionStatus: remoteData.transcriptionStatus,
            summaryStatus: remoteData.summaryStatus,
            isArchived: remoteData.isArchived,
            userId: remoteData.userId,
            lastSyncedAt: Date(),
            remoteId: remoteData.id,
            updatedAt: remoteData.updatedAt
        )

        modelContext.insert(sermon)

        if let remoteNotes = remoteData.notes {
            print("[SyncService] Creating \(remoteNotes.count) notes")
            for noteData in remoteNotes {
                let note = Note(
                    id: noteData.localId,
                    text: noteData.text,
                    timestamp: noteData.timestamp,
                    remoteId: noteData.id
                )
                note.sermon = sermon
                modelContext.insert(note)
                sermon.notes.append(note)
            }
        }

        if let transcriptData = remoteData.transcript {
            applyTranscriptSnapshot(
                transcriptSnapshot(from: transcriptData, sermonUpdatedAt: remoteData.updatedAt),
                to: sermon
            )
        }

        if let summaryData = remoteData.summary {
            applySummarySnapshot(
                summarySnapshot(from: summaryData, sermonUpdatedAt: remoteData.updatedAt),
                to: sermon
            )

            if !summaryData.title.isEmpty {
                sermon.title = summaryData.title
            }
        }

        try modelContext.save()
        print("[SyncService] ✅ Local sermon created and saved: \(sermon.title)")
    }

    func resetCloudSyncState() throws {
        let sermons = try modelContext.fetch(FetchDescriptor<Sermon>())
        for sermon in sermons {
            sermon.remoteId = nil
            sermon.lastSyncedAt = nil
            sermon.syncStatus = "localOnly"
            sermon.needsSync = false
            sermon.metadataNeedsSync = false
            sermon.notesNeedSync = false
            sermon.transcriptNeedsSync = false
            sermon.summaryNeedsSync = false
        }
        try modelContext.save()
    }

    func save() throws {
        try modelContext.save()
    }

    private struct TranscriptSegmentSnapshot {
        let id: UUID
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    private struct TranscriptSnapshot {
        let id: UUID
        let text: String
        let segments: [TranscriptSegmentSnapshot]
        let remoteId: String?
        let updatedAt: Date?
    }

    private struct SummarySnapshot {
        let id: UUID
        let title: String
        let text: String
        let type: String
        let status: String
        let remoteId: String?
        let updatedAt: Date?
    }

    private func applyTranscriptSnapshot(_ snapshot: TranscriptSnapshot?, to sermon: Sermon) {
        if let existingTranscript = sermon.transcript {
            sermon.transcript = nil
            modelContext.delete(existingTranscript)
        }

        guard let snapshot else { return }

        let newSegments = snapshot.segments.map { segment in
            TranscriptSegment(
                id: segment.id,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime
            )
        }

        let transcript = Transcript(
            id: snapshot.id,
            text: snapshot.text,
            segments: newSegments,
            remoteId: snapshot.remoteId,
            updatedAt: snapshot.updatedAt,
            needsSync: false
        )
        modelContext.insert(transcript)
        sermon.transcript = transcript
    }

    private func applySummarySnapshot(_ snapshot: SummarySnapshot?, to sermon: Sermon) {
        if let existingSummary = sermon.summary {
            sermon.summary = nil
            modelContext.delete(existingSummary)
        }

        guard let snapshot else {
            sermon.summaryPreviewText = nil
            return
        }

        let summary = Summary(
            id: snapshot.id,
            title: snapshot.title,
            text: snapshot.text,
            type: snapshot.type,
            status: snapshot.status,
            remoteId: snapshot.remoteId,
            updatedAt: snapshot.updatedAt,
            needsSync: false
        )
        modelContext.insert(summary)
        sermon.summary = summary
        sermon.summaryPreviewText = Sermon.makeSummaryPreview(from: snapshot.text)
    }

    private func transcriptSnapshot(from remoteData: RemoteTranscriptData, sermonUpdatedAt: Date) -> TranscriptSnapshot {
        TranscriptSnapshot(
            id: remoteData.localId,
            text: remoteData.text,
            segments: [],
            remoteId: remoteData.id,
            updatedAt: sermonUpdatedAt
        )
    }

    private func summarySnapshot(from remoteData: RemoteSummaryData, sermonUpdatedAt: Date) -> SummarySnapshot {
        SummarySnapshot(
            id: remoteData.localId,
            title: remoteData.title,
            text: remoteData.text,
            type: remoteData.type,
            status: remoteData.status,
            remoteId: remoteData.id,
            updatedAt: sermonUpdatedAt
        )
    }

    private func shouldPreserveLocalChildData(for sermon: Sermon, childNeedsSync: Bool) -> Bool {
        sermon.hasPendingSyncWork && childNeedsSync
    }

    private func mergeRemoteNotes(_ remoteNotes: [RemoteNoteData]?, into sermon: Sermon, remoteUpdatedAt: Date) {
        guard let remoteNotes else {
            if !sermon.notes.isEmpty {
                print("[SyncService] ⚠️ Preserving \(sermon.notes.count) local notes (remote returned no notes)")
            }
            return
        }

        if remoteNotes.isEmpty {
            if sermon.notes.isEmpty {
                print("[SyncService] ℹ️ Both local and remote notes are empty")
            } else {
                print("[SyncService] ⚠️ Preserving \(sermon.notes.count) local notes (remote note list was empty)")
            }
            return
        }

        print("[SyncService] Merging \(remoteNotes.count) remote notes")

        for remoteNote in remoteNotes {
            if let localNote = sermon.notes.first(where: { $0.id == remoteNote.localId || $0.remoteId == remoteNote.id }) {
                if shouldPreserveLocalChildData(for: sermon, childNeedsSync: localNote.needsSync) {
                    if localNote.remoteId == nil {
                        localNote.remoteId = remoteNote.id
                    }
                    print("[SyncService] ⚠️ Preserving dirty local note \(localNote.id)")
                    continue
                }

                localNote.text = remoteNote.text
                localNote.timestamp = remoteNote.timestamp
                localNote.remoteId = remoteNote.id
                localNote.updatedAt = remoteUpdatedAt
                localNote.needsSync = false
            } else {
                let note = Note(
                    id: remoteNote.localId,
                    text: remoteNote.text,
                    timestamp: remoteNote.timestamp,
                    remoteId: remoteNote.id,
                    updatedAt: remoteUpdatedAt,
                    needsSync: false
                )
                note.sermon = sermon
                modelContext.insert(note)
                sermon.notes.append(note)
            }
        }

        print("[SyncService] ✅ Note merge completed. Local sermon now has \(sermon.notes.count) notes")
    }

    private func mergeRemoteTranscript(_ remoteTranscript: RemoteTranscriptData?, into sermon: Sermon, remoteUpdatedAt: Date) {
        guard let remoteTranscript else {
            if sermon.transcript != nil {
                print("[SyncService] ⚠️ Preserving local transcript - remote returned no transcript")
            } else {
                print("[SyncService] ℹ️ No transcript on local or remote")
            }
            return
        }

        if let localTranscript = sermon.transcript,
           shouldPreserveLocalChildData(for: sermon, childNeedsSync: localTranscript.needsSync) {
            if localTranscript.remoteId == nil {
                localTranscript.remoteId = remoteTranscript.id
            }
            print("[SyncService] ⚠️ Preserving dirty local transcript")
            return
        }

        print("[SyncService] Updating transcript from remote (length: \(remoteTranscript.text.count) chars)")
        applyTranscriptSnapshot(
            transcriptSnapshot(from: remoteTranscript, sermonUpdatedAt: remoteUpdatedAt),
            to: sermon
        )
        print("[SyncService] ✅ Transcript upserted from remote")
    }

    private func mergeRemoteSummary(_ remoteSummary: RemoteSummaryData?, into sermon: Sermon, remoteUpdatedAt: Date) {
        guard let remoteSummary else {
            if sermon.summary != nil {
                print("[SyncService] ⚠️ Preserving local summary - remote returned no summary")
            } else {
                print("[SyncService] ℹ️ No summary on local or remote")
            }
            return
        }

        if let localSummary = sermon.summary,
           shouldPreserveLocalChildData(for: sermon, childNeedsSync: localSummary.needsSync) {
            if localSummary.remoteId == nil {
                localSummary.remoteId = remoteSummary.id
            }
            print("[SyncService] ⚠️ Preserving dirty local summary")
            return
        }

        print("[SyncService] Updating summary from remote (length: \(remoteSummary.text.count) chars)")
        applySummarySnapshot(
            summarySnapshot(from: remoteSummary, sermonUpdatedAt: remoteUpdatedAt),
            to: sermon
        )

        if !remoteSummary.title.isEmpty {
            print("[SyncService] 📝 Updating sermon title from '\(sermon.title)' to '\(remoteSummary.title)'")
            sermon.title = remoteSummary.title
        }

        print("[SyncService] ✅ Summary upserted from remote")
    }

    private func markChildEntitiesSynced(for sermon: Sermon, syncedAt: Date, scopes: SermonSyncScopes) {
        if scopes.notes {
            for note in sermon.notes {
                note.needsSync = false
                note.updatedAt = syncedAt
            }
        }

        if scopes.transcript, let transcript = sermon.transcript {
            transcript.needsSync = false
            transcript.updatedAt = syncedAt
        }

        if scopes.summary, let summary = sermon.summary {
            summary.needsSync = false
            summary.updatedAt = syncedAt
        }
    }
}
