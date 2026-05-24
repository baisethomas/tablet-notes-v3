import Foundation
import SwiftData

enum AppStoreScreenshotSeed {
    static let userID = UUID(uuidString: "7A404226-6B9B-4B32-86F7-8C0C66A17516")!

    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        guard ProcessInfo.processInfo.environment["APP_STORE_SCREENSHOTS"] == "1" else { return }

        let descriptor = FetchDescriptor<Sermon>()
        if let existing = try? context.fetch(descriptor),
           existing.contains(where: { $0.userId == userID }) {
            return
        }

        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 11)) ?? Date()

        let transcript = Transcript(
            text: [
                "When Paul writes that all things work together for good, he is calling us to trust God's hands even before we understand the story.",
                "Hope is not denial. Hope is disciplined remembrance.",
                "It looks back at God's faithfulness and carries courage into the next step.",
                "Romans 8:28 becomes more than a verse on a page. It becomes a way to pray, listen, and serve."
            ].joined(separator: "\n\n"),
            segments: [
                TranscriptSegment(text: "When Paul writes that all things work together for good, he is calling us to trust God's hands even before we understand the story.", startTime: 42, endTime: 58),
                TranscriptSegment(text: "Hope is not denial. Hope is disciplined remembrance.", startTime: 75, endTime: 83),
                TranscriptSegment(text: "It looks back at God's faithfulness and carries courage into the next step.", startTime: 84, endTime: 96),
                TranscriptSegment(text: "Romans 8:28 becomes more than a verse on a page. It becomes a way to pray, listen, and serve.", startTime: 128, endTime: 146)
            ]
        )

        let summaryText = """
        Main Theme
        God forms resilient hope through faithful remembrance, patient prayer, and active love.

        Key Insights
        - Romans 8:28 was framed as a promise of God's presence, not a promise of easy circumstances.
        - The message connected spiritual maturity with remembering God's past faithfulness.
        - Prayer was presented as the first act of trust, not a final resort.

        Scripture References
        Romans 8:28
        Philippians 4:13
        John 15:5

        Application
        Name one place where fear is louder than faith, then answer it this week with prayer and a concrete act of love.
        """

        let summary = Summary(
            title: "Hope That Holds",
            text: summaryText,
            type: "Sunday Service",
            status: "complete"
        )

        let notes = [
            Note(text: "Hope is not pretending the storm is small. It is remembering that God is near.", timestamp: 522),
            Note(text: "Pastor connected Romans 8:28 with daily obedience: pray first, serve next.", timestamp: 969),
            Note(text: "Follow up with small group: where are we practicing remembrance this week?", timestamp: 1431)
        ]

        let sermon = Sermon(
            title: "Hope That Holds",
            audioFileName: "app-store-demo.m4a",
            date: date,
            serviceType: "Sunday Service",
            speaker: "Pastor James",
            transcript: transcript,
            notes: notes,
            summary: summary,
            syncStatus: "synced",
            transcriptionStatus: "complete",
            summaryStatus: "complete",
            summaryPreviewText: Sermon.makeSummaryPreview(from: summaryText),
            userId: userID,
            lastSyncedAt: date
        )

        let olderSermons = [
            Sermon(
                title: "The Practice of Prayer",
                audioFileName: "app-store-demo-prayer.m4a",
                date: calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 19)) ?? date,
                serviceType: "Bible Study",
                speaker: "Pastor James",
                summaryPreviewText: "Prayer was presented as the first act of trust, not a final resort.",
                userId: userID,
                lastSyncedAt: date
            ),
            Sermon(
                title: "Grace in the Waiting",
                audioFileName: "app-store-demo-grace.m4a",
                date: calendar.date(from: DateComponents(year: 2026, month: 4, day: 21, hour: 10)) ?? date,
                serviceType: "Sunday Service",
                speaker: "Pastor James",
                syncStatus: "synced",
                transcriptionStatus: "complete",
                summaryStatus: "complete",
                summaryPreviewText: "A message about patience, courage, and grace in seasons that feel unfinished.",
                userId: userID,
                lastSyncedAt: date
            )
        ]

        context.insert(sermon)
        olderSermons.forEach { context.insert($0) }
        try? context.save()
    }
}
