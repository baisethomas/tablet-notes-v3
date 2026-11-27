import Foundation
import SwiftData
import Testing
@testable import TabletNotes

/// TAB-40: transcript segment timings must survive push and pull so
/// tap-to-seek works on a device that did not record the sermon.
@Suite("Transcript segment sync")
struct TranscriptSegmentsSyncTests {

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

    private let clientSegmentId = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let transcriptId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let userId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    private var clientSegmentsJSON: String {
        #"[{"id":"\#(clientSegmentId.uuidString)","text":"In the beginning","startTime":1.5,"endTime":3.25}]"#
    }

    private var assemblyAIWordsJSON: String {
        #"[{"text":"In","start":0,"end":200},{"text":"the","start":250,"end":400},{"text":"beginning","start":1500,"end":2000}]"#
    }

    @MainActor
    private func makeSermonWithTimedTranscript(
        modelContext: ModelContext,
        remoteId: String? = nil
    ) -> Sermon {
        let sermon = Sermon(
            title: "Timed Sermon",
            audioFileName: "timed.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "pending",
            transcriptionStatus: "complete",
            summaryStatus: "pending",
            remoteId: remoteId,
            updatedAt: Date(),
            transcriptNeedsSync: true
        )
        modelContext.insert(sermon)

        let segment = TranscriptSegment(
            id: clientSegmentId,
            text: "In the beginning",
            startTime: 1.5,
            endTime: 3.25
        )
        let transcript = Transcript(
            id: transcriptId,
            text: "In the beginning",
            segments: [segment],
            updatedAt: Date(),
            needsSync: true
        )
        modelContext.insert(transcript)
        sermon.transcript = transcript
        sermon.markPendingSync(transcript: true)
        TranscriptSnapshotStore.remove(for: sermon.id)
        return sermon
    }

    private func makeRemoteSermon(
        localId: UUID,
        segmentsJSON: String?
    ) -> RemoteSermonData {
        RemoteSermonData(
            id: "remote-1",
            localId: localId,
            title: "Restored Sermon",
            audioFileURL: URL(fileURLWithPath: "/tmp/restored.m4a"),
            audioFilePath: nil,
            date: Date(timeIntervalSince1970: 1_787_000_000),
            serviceType: "Sunday Service",
            speaker: nil,
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            isArchived: false,
            userId: userId,
            updatedAt: Date(timeIntervalSince1970: 1_787_000_100),
            notes: nil,
            transcript: RemoteTranscriptData(
                id: "t-remote",
                localId: transcriptId,
                text: "In the beginning",
                segments: segmentsJSON,
                status: "complete"
            ),
            summary: nil
        )
    }

    private func createPayload(from data: SermonSyncData) -> [String: Any] {
        SermonSyncRemoteGateway.createSermonPayload(
            data: data,
            audioFilePath: "user/timed.m4a",
            audioFileUrl: "https://example.com/timed.m4a",
            audioFileName: "timed.m4a",
            fileSize: 4096
        )
    }

    // MARK: - Push

    @MainActor
    @Test func syncDataFallsBackToSwiftDataTranscriptWhenSnapshotStoreIsEmpty() throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)
        let sermon = makeSermonWithTimedTranscript(modelContext: modelContext)
        try modelContext.save()
        defer { TranscriptSnapshotStore.remove(for: sermon.id) }

        #expect(TranscriptSnapshotStore.snapshot(for: sermon.id) == nil)

        let syncData = repository.syncData(for: sermon)
        let transcript = try #require(syncData.transcript)
        #expect(transcript.id == transcriptId)
        #expect(transcript.text == "In the beginning")
        #expect(syncData.scopes.transcript)
    }

    @MainActor
    @Test func createPayloadSerializesTranscriptSegmentsInsteadOfNull() throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)
        let sermon = makeSermonWithTimedTranscript(modelContext: modelContext)
        try modelContext.save()
        defer { TranscriptSnapshotStore.remove(for: sermon.id) }

        let syncData = repository.syncData(for: sermon)
        let payload = createPayload(from: syncData)
        let transcript = try #require(payload["transcript"] as? [String: Any])
        #expect(!(transcript["segments"] is NSNull))
        let segments = try #require(transcript["segments"] as? [[String: Any]])
        #expect(segments.count == 1)
        #expect(segments[0]["text"] as? String == "In the beginning")
        #expect(doubleValue(segments[0]["startTime"]) == 1.5)
        #expect(doubleValue(segments[0]["endTime"]) == 3.25)
        #expect(segments[0]["id"] as? String == clientSegmentId.uuidString)
    }

    @MainActor
    @Test func updatePayloadSerializesTranscriptSegmentsInsteadOfNull() throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)
        let sermon = makeSermonWithTimedTranscript(modelContext: modelContext, remoteId: "remote-1")
        try modelContext.save()
        defer { TranscriptSnapshotStore.remove(for: sermon.id) }

        let syncData = repository.syncData(for: sermon)
        let payload = SermonSyncRemoteGateway.updateSermonPayload(remoteId: "remote-1", data: syncData)
        let transcript = try #require(payload["transcript"] as? [String: Any])
        #expect(!(transcript["segments"] is NSNull))
        let segments = try #require(transcript["segments"] as? [[String: Any]])
        #expect(segments.count == 1)
        #expect(doubleValue(segments[0]["startTime"]) == 1.5)
        #expect(doubleValue(segments[0]["endTime"]) == 3.25)
    }

    // MARK: - Pull

    @MainActor
    @Test func pullOntoEmptyStoreRestoresClientSegmentTimings() throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)
        let remote = makeRemoteSermon(
            localId: UUID(),
            segmentsJSON: clientSegmentsJSON
        )

        try repository.createLocalSermon(
            from: remote,
            audioFileURL: URL(fileURLWithPath: "/tmp/restored.m4a")
        )

        let sermons = try modelContext.fetch(FetchDescriptor<Sermon>())
        let sermon = try #require(sermons.first)
        let transcript = try #require(sermon.transcript)
        #expect(transcript.text == "In the beginning")
        let segments = transcript.segments.sorted { $0.startTime < $1.startTime }
        #expect(segments.count == 1)
        #expect(segments[0].text == "In the beginning")
        #expect(segments[0].startTime == 1.5)
        #expect(segments[0].endTime == 3.25)
        #expect(segments[0].id == clientSegmentId)
    }

    @MainActor
    @Test func pullRefreshesSegmentsOnExistingTranscript() throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)
        let sermon = Sermon(
            title: "Existing Sermon",
            audioFileName: "existing.m4a",
            date: Date(),
            serviceType: "Sunday Service",
            syncStatus: "synced",
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            remoteId: "remote-1",
            updatedAt: Date()
        )
        modelContext.insert(sermon)
        let stale = Transcript(
            id: transcriptId,
            text: "In the beginning",
            segments: [],
            remoteId: "t-remote",
            updatedAt: Date(),
            needsSync: false
        )
        modelContext.insert(stale)
        sermon.transcript = stale
        try modelContext.save()

        repository.updateLocalSermon(
            sermon,
            with: makeRemoteSermon(localId: sermon.id, segmentsJSON: clientSegmentsJSON)
        )

        let segments = try #require(sermon.transcript).segments.sorted { $0.startTime < $1.startTime }
        #expect(segments.count == 1)
        #expect(segments[0].text == "In the beginning")
        #expect(segments[0].startTime == 1.5)
        #expect(segments[0].endTime == 3.25)
    }

    @MainActor
    @Test func pullGroupsAssemblyAIWordTimingsTheSameWayAsLocalTranscription() throws {
        let modelContext = try makeModelContext()
        let repository = SermonSyncLocalRepository(modelContext: modelContext)
        let remote = makeRemoteSermon(
            localId: UUID(),
            segmentsJSON: assemblyAIWordsJSON
        )

        try repository.createLocalSermon(
            from: remote,
            audioFileURL: URL(fileURLWithPath: "/tmp/restored.m4a")
        )

        let segments = try #require(
            modelContext.fetch(FetchDescriptor<Sermon>()).first?.transcript
        ).segments.sorted { $0.startTime < $1.startTime }
        #expect(segments.count == 2)
        #expect(segments[0].text == "In the")
        #expect(segments[0].startTime == 0)
        #expect(segments[0].endTime == 0.4)
        #expect(segments[1].text == "beginning")
        #expect(segments[1].startTime == 1.5)
        #expect(segments[1].endTime == 2.0)
    }

    // MARK: - 1.0.1 compatibility

    /// Shipped 1.0.1 synthesized `String?` for `segments`. A JSON array on
    /// that key fails the whole library import; a JSON string does not.
    private struct Shipped101Transcript: Decodable {
        let id: String
        let localId: UUID
        let text: String
        let segments: String?
        let status: String
    }

    @Test func shipped101DecoderAcceptsStringifiedSegments() throws {
        let json = """
        {
          "id": "t-1",
          "localId": "11111111-1111-1111-1111-111111111111",
          "text": "In the beginning",
          "segments": \(String(data: try JSONEncoder().encode(clientSegmentsJSON), encoding: .utf8)!),
          "status": "complete"
        }
        """
        let decoded = try JSONDecoder().decode(Shipped101Transcript.self, from: Data(json.utf8))
        #expect(decoded.segments != nil)
        let parsed = try JSONDecoder().decode([ClientSegmentDTO].self, from: Data(decoded.segments!.utf8))
        #expect(parsed.count == 1)
        #expect(parsed[0].startTime == 1.5)
    }

    @Test func shipped101DecoderRejectsAJsonArrayOnSegments() {
        let json = """
        {
          "id": "t-1",
          "localId": "11111111-1111-1111-1111-111111111111",
          "text": "In the beginning",
          "segments": [{"text":"In","start":0,"end":200}],
          "status": "complete"
        }
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Shipped101Transcript.self, from: Data(json.utf8))
        }
    }

    @Test func stringifiedTimedSegmentsDoNotDropTheRestOfTheLibrary() throws {
        let json = """
        [
          \(sermonJSON(id: "s-local", title: "August local", segmentsJSON: "null")),
          \(sermonJSON(id: "s-old", title: "Older cloud sermon", segmentsJSON: String(data: try JSONEncoder().encode(clientSegmentsJSON), encoding: .utf8)!))
        ]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sermons = try decoder.decode([RemoteSermonData].self, from: Data(json.utf8))
        #expect(sermons.map(\.title) == ["August local", "Older cloud sermon"])
        #expect(sermons[1].transcript?.text == "In the beginning")
        #expect(sermons[1].transcript?.segments == clientSegmentsJSON)
    }

    private struct ClientSegmentDTO: Decodable {
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    private func doubleValue(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? value as? Double
    }

    private func sermonJSON(id: String, title: String, segmentsJSON: String) -> String {
        """
        {
          "id": "\(id)",
          "localId": "22222222-2222-2222-2222-222222222222",
          "title": "\(title)",
          "audioFileURL": "https://example.com/\(id).m4a",
          "audioFilePath": null,
          "date": "2026-08-16T12:00:00Z",
          "serviceType": "Sunday Service",
          "speaker": null,
          "transcriptionStatus": "complete",
          "summaryStatus": "complete",
          "isArchived": false,
          "userId": "33333333-3333-3333-3333-333333333333",
          "updatedAt": "2026-08-16T12:00:00Z",
          "notes": [],
          "transcript": {
            "id": "t-\(id)",
            "localId": "11111111-1111-1111-1111-111111111111",
            "text": "In the beginning",
            "segments": \(segmentsJSON),
            "status": "complete"
          },
          "summary": null
        }
        """
    }
}
