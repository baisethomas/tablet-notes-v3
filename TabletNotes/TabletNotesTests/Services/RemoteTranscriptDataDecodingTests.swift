import Foundation
import Testing
@testable import TabletNotes

/// TAB-93. Production `transcripts.segments` is jsonb. Most rows are null;
/// a minority are word-timing arrays. `RemoteTranscriptData.segments` used
/// to be a synthesized `String?`, so one array failed the entire
/// `[RemoteSermonData]` pull and the local library never imported.
@Suite("Remote transcript segments decode")
struct RemoteTranscriptDataDecodingTests {

    @Test("a jsonb array does not fail the transcript")
    func arraySegmentsAreTolerated() throws {
        let transcript = try decodeTranscript(segmentsJSON: #"[{"text":"In","start":0.0,"end":0.2}]"#)
        #expect(transcript.id == "t-1")
        #expect(transcript.text == "In the beginning")
        #expect(transcript.segments == nil)
    }

    @Test("a string value still decodes")
    func stringSegmentsDecode() throws {
        let transcript = try decodeTranscript(segmentsJSON: #""[]""#)
        #expect(transcript.segments == "[]")
    }

    @Test("null segments decode")
    func nullSegmentsDecode() throws {
        let transcript = try decodeTranscript(segmentsJSON: "null")
        #expect(transcript.segments == nil)
    }

    @Test("a missing segments key decodes")
    func missingSegmentsDecode() throws {
        let json = """
        {
          "id": "t-1",
          "localId": "11111111-1111-1111-1111-111111111111",
          "text": "In the beginning",
          "status": "complete"
        }
        """
        let transcript = try JSONDecoder().decode(RemoteTranscriptData.self, from: Data(json.utf8))
        #expect(transcript.segments == nil)
    }

    @Test("one array-segment sermon does not drop the rest of the library")
    func mixedLibraryDecodes() throws {
        // This is the production failure: JSONDecoder throws on the first
        // jsonb array and the client imports zero rows, including sermons
        // whose own segments are null.
        let json = """
        [
          \(sermonJSON(id: "s-local", title: "August local", segmentsJSON: "null")),
          \(sermonJSON(id: "s-old", title: "Older cloud sermon", segmentsJSON: #"[{"text":"Hello","start":0.0,"end":0.4}]"#))
        ]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sermons = try decoder.decode([RemoteSermonData].self, from: Data(json.utf8))
        #expect(sermons.map(\.title) == ["August local", "Older cloud sermon"])
        #expect(sermons[0].transcript?.segments == nil)
        #expect(sermons[1].transcript?.segments == nil)
        #expect(sermons[1].transcript?.text == "In the beginning")
    }

    private func decodeTranscript(segmentsJSON: String) throws -> RemoteTranscriptData {
        let json = """
        {
          "id": "t-1",
          "localId": "11111111-1111-1111-1111-111111111111",
          "text": "In the beginning",
          "segments": \(segmentsJSON),
          "status": "complete"
        }
        """
        return try JSONDecoder().decode(RemoteTranscriptData.self, from: Data(json.utf8))
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
