import Foundation

/// One timed transcript span on the sync wire / JSONB column.
/// Client push uses seconds (`startTime` / `endTime`). Server-transcribed
/// rows store AssemblyAI words (`start` / `end` in milliseconds).
struct TranscriptSegmentSyncPayload: Equatable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval

    var jsonObject: [String: Any] {
        [
            "id": id.uuidString,
            "text": text,
            "startTime": startTime,
            "endTime": endTime
        ]
    }
}

enum TranscriptSegmentCodec {
    static func wireObjects(from segments: [TranscriptSegmentSyncPayload]) -> [[String: Any]] {
        segments.map(\.jsonObject)
    }

    static func parse(_ raw: String?) -> [TranscriptSegmentSyncPayload] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        return parse(jsonObject: (try? JSONSerialization.jsonObject(with: data)))
    }

    static func parse(jsonObject: Any?) -> [TranscriptSegmentSyncPayload] {
        guard let items = jsonObject as? [[String: Any]], !items.isEmpty else { return [] }
        let usesClientKeys = items.contains { $0["startTime"] != nil || $0["endTime"] != nil }
        if usesClientKeys {
            return items.compactMap(parseClientSegment)
        }
        return groupAssemblyAIWords(items)
    }

    private static func parseClientSegment(_ item: [String: Any]) -> TranscriptSegmentSyncPayload? {
        guard let text = item["text"] as? String else { return nil }
        let start = timeInterval(item["startTime"]) ?? 0
        let end = timeInterval(item["endTime"]) ?? start
        let id = (item["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        return TranscriptSegmentSyncPayload(id: id, text: text, startTime: start, endTime: end)
    }

    private static func timeInterval(_ value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Double { return number }
        if let number = value as? Int { return TimeInterval(number) }
        return nil
    }

    /// AssemblyAI words use `start`/`end` in milliseconds. Group by the same
    /// 0.7s gap as local transcription so tap-to-seek rows match the recorder.
    static func groupAssemblyAIWords(_ words: [[String: Any]]) -> [TranscriptSegmentSyncPayload] {
        struct Word {
            let text: String
            let startMs: Double
            let endMs: Double
        }

        let parsed: [Word] = words.compactMap { item in
            guard let text = item["text"] as? String else { return nil }
            let start = timeInterval(item["start"]) ?? 0
            let end = timeInterval(item["end"]) ?? start
            return Word(text: text, startMs: start, endMs: end)
        }
        guard let first = parsed.first else { return [] }

        let gapThreshold: Double = 0.7
        var grouped: [[Word]] = []
        var current: [Word] = [first]

        for index in 1..<parsed.count {
            let previous = parsed[index - 1]
            let word = parsed[index]
            let gap = (word.startMs - previous.endMs) / 1000.0
            if gap > gapThreshold {
                grouped.append(current)
                current = []
            }
            current.append(word)
        }
        grouped.append(current)

        return grouped.map { phrase in
            TranscriptSegmentSyncPayload(
                id: UUID(),
                text: phrase.map(\.text).joined(separator: " "),
                startTime: phrase.first!.startMs / 1000.0,
                endTime: phrase.last!.endMs / 1000.0
            )
        }
    }
}
