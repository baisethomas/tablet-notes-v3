import Foundation
import Testing
@testable import TabletNotes

// TAB-119: the planner picks a sermon's scriptures, a meaningful summary line
// for each, and the mornings they fire. Summary fixtures follow the section
// shapes the summarize prompt asks for, in each heading style the model uses.
struct ScriptureReminderPlannerTests {
    private let planner = ScriptureReminderPlanner()

    private static let newYork = TimeZone(identifier: "America/New_York")!

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static let sunday = date(2026, 9, 27, 11, 30)

    private func plan(_ summary: String, transcript: String? = nil, now: Date = sunday) -> [PlannedScriptureReminder] {
        planner.plan(summaryText: summary, transcriptText: transcript, now: now, calendar: Self.calendar)
    }

    private func references(_ reminders: [PlannedScriptureReminder]) -> [String] {
        reminders.map(\.reference.displayText)
    }

    // Same shape as the App Store screenshot seed: bare-line headings.
    private static let seedSummary = """
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

    // MARK: - Scripture selection

    @Test func seedSummaryKeepsReferenceListOrder() {
        #expect(references(plan(Self.seedSummary)) == ["Romans 8:28", "Philippians 4:13", "John 15:5"])
    }

    // Analyzing a whole section at once reads "good\nJohn" as one book name
    // and silently drops the second entry.
    @Test func referenceListWithDescriptionsKeepsEveryEntry() {
        let summary = """
        Scripture References
        Romans 8:28 - God works all things together for good
        John 15:5 - Apart from the vine we can do nothing
        Psalm 46:10 - Be still and know
        """
        #expect(references(plan(summary)) == ["Romans 8:28", "John 15:5", "Psalm 46:10"])
    }

    @Test func mainScriptureLeadsEvenWhenListedLater() {
        let summary = """
        **Main Scripture Text**
        Romans 8:28

        **Scripture References**
        - Genesis 50:20
        - John 15:5
        """
        #expect(references(plan(summary)) == ["Romans 8:28", "Genesis 50:20", "John 15:5"])
    }

    @Test func inlineBoldHeadingCarriesItsReference() {
        let summary = """
        **Main Scripture Text:** Psalm 23:1-3 (NIV)

        **Scripture References (Complete)**
        - Isaiah 40:31
        """
        #expect(references(plan(summary)) == ["Psalm 23:1-3", "Isaiah 40:31"])
    }

    @Test func hashHeadingsAreRecognised() {
        let summary = """
        ## Scripture References
        1. Hebrews 11:1
        2. James 1:22

        ## Main Scripture Text
        Micah 6:8
        """
        #expect(references(plan(summary)) == ["Micah 6:8", "Hebrews 11:1", "James 1:22"])
    }

    @Test func overlappingPassagesCollapseToTheFirstSeen() {
        let summary = """
        Main Scripture Text
        John 3:16-18

        Scripture References
        John 3:16
        John 3:17
        Romans 5:8
        Psalm 23:1
        Ps 23:1-3
        """
        #expect(references(plan(summary)) == ["John 3:16-18", "Romans 5:8", "Psalm 23:1"])
    }

    @Test func referencesOutsideTheListStillCount() {
        let summary = """
        Key Points
        - Ephesians 2:8 shows that grace meets us before we move.

        Scripture References
        Romans 8:28
        """
        #expect(references(plan(summary)) == ["Romans 8:28", "Ephesians 2:8"])
    }

    @Test func atMostFourReminders() {
        let summary = """
        Scripture References
        Genesis 1:1
        Exodus 3:14
        Psalm 46:10
        Isaiah 43:2
        Matthew 6:33
        """
        #expect(references(plan(summary)) == ["Genesis 1:1", "Exodus 3:14", "Psalm 46:10", "Isaiah 43:2"])
    }

    @Test func transcriptIsTheFallbackWhenTheSummaryHasNoScripture() {
        let summary = """
        Key Points
        - Rest is an act of trust, not a reward for finishing.
        """
        let transcript = "Good morning church.\nMatthew 11:28 is where we start today."
        #expect(references(plan(summary, transcript: transcript)) == ["Matthew 11:28"])
    }

    @Test func transcriptIsNotConsultedOnceFourAreFound() {
        let summary = """
        Scripture References
        Genesis 1:1
        Exodus 3:14
        Psalm 46:10
        Isaiah 43:2
        """
        let transcript = "Matthew 11:28 was read at the close."
        #expect(!references(plan(summary, transcript: transcript)).contains("Matthew 11:28"))
    }

    @Test func noScriptureMeansNoReminders() {
        let summary = """
        Application
        Call one person this week who needs to hear that they are not forgotten.
        """
        #expect(plan(summary, transcript: "No references were read aloud today.").isEmpty)
    }

    // MARK: - Schedule

    // Compared field by field: Foundation also sets `isLeapMonth` when `.month`
    // is requested, so whole-struct equality with a hand-built value is unreliable.
    private func fireComponents(_ reminders: [PlannedScriptureReminder]) -> [[Int?]] {
        reminders.map { reminder in
            let components = reminder.fireDateComponents
            return [components.year, components.month, components.day, components.hour, components.minute]
        }
    }

    private static func morning(_ year: Int, _ month: Int, _ day: Int) -> [Int?] {
        [year, month, day, 8, 0]
    }

    private static let fourReferences = """
    Scripture References
    Genesis 1:1
    Exodus 3:14
    Psalm 46:10
    Isaiah 43:2
    """

    @Test func fourRemindersOnDaysOneThreeFiveSevenAtEight() {
        #expect(fireComponents(plan(Self.fourReferences)) == [
            Self.morning(2026, 9, 28), Self.morning(2026, 9, 30),
            Self.morning(2026, 10, 2), Self.morning(2026, 10, 4)
        ])
    }

    @Test func fewerScripturesUseTheEarliestDays() {
        let summary = """
        Scripture References
        Romans 8:28
        John 15:5
        """
        #expect(fireComponents(plan(summary)) == [Self.morning(2026, 9, 28), Self.morning(2026, 9, 30)])
    }

    @Test func scheduleCrossesMonthBoundaries() {
        let reminders = plan(Self.fourReferences, now: Self.date(2026, 1, 30, 10))
        #expect(fireComponents(reminders) == [
            Self.morning(2026, 1, 31), Self.morning(2026, 2, 2),
            Self.morning(2026, 2, 4), Self.morning(2026, 2, 6)
        ])
    }

    @Test func scheduleStaysAtEightAcrossTheDaylightSavingChange() {
        // US daylight saving time ends on 2026-11-01.
        let reminders = plan(Self.fourReferences, now: Self.date(2026, 10, 30, 11))
        #expect(fireComponents(reminders) == [
            Self.morning(2026, 10, 31), Self.morning(2026, 11, 2),
            Self.morning(2026, 11, 4), Self.morning(2026, 11, 6)
        ])
        for components in reminders.map(\.fireDateComponents) {
            let fireDate = Self.calendar.date(from: components)!
            #expect(Self.calendar.component(.hour, from: fireDate) == 8)
        }
    }

    @Test func lateNightPlanningStillStartsTheNextMorning() {
        let reminders = plan(Self.fourReferences, now: Self.date(2026, 9, 27, 23, 50))
        #expect(fireComponents(reminders).first == Self.morning(2026, 9, 28))
    }

    // MARK: - Messages

    @Test func seedSummaryMessagesLeadWithTheApplication() {
        #expect(plan(Self.seedSummary).map(\.message) == [
            "Name one place where fear is louder than faith, then answer it this week with prayer and a concrete act of love.",
            "Romans 8:28 was framed as a promise of God's presence, not a promise of easy circumstances.",
            "Prayer was presented as the first act of trust, not a final resort."
        ])
    }

    @Test func messagesFollowSectionPriorityNotDocumentOrder() {
        let summary = """
        **Brief Summary**
        God keeps every promise he makes to his people.

        **Key Points**
        - Waiting on God is active trust, not passive delay

        **Study Questions**
        1. Where are you tempted to run ahead of God this week?

        **Application**
        - Write down one promise of God and read it aloud each morning.

        **Scripture References**
        Isaiah 40:31
        Psalm 27:14
        Lamentations 3:25
        Habakkuk 2:3
        """
        #expect(plan(summary).map(\.message) == [
            "Write down one promise of God and read it aloud each morning.",
            "Where are you tempted to run ahead of God this week?",
            "Waiting on God is active trust, not passive delay.",
            "God keeps every promise he makes to his people."
        ])
    }

    @Test func messageIsNilWhenNothingMeaningfulRemains() {
        let summary = """
        Key Points
        - Faith
        - Hope and love

        Scripture References
        Romans 8:28
        """
        #expect(plan(summary).map(\.message) == [nil])
    }

    @Test func missingMessagesDoNotShiftOrRepeat() {
        let summary = """
        Application
        - Pray for one neighbor by name every day this week.

        Scripture References
        Romans 12:13
        Luke 10:27
        """
        #expect(plan(summary).map(\.message) == ["Pray for one neighbor by name every day this week.", nil])
    }

    @Test func offlineFallbackSummaryNoteIsNeverAMessage() {
        let summary = """
        **Sunday Service Summary**

        **Key Points:** God is faithful to finish what he starts in us

        **Note:** This is a basic summary generated offline. For a more detailed AI-powered summary, please try again when the summarization service is available.

        Romans 8:28
        """
        #expect(plan(summary).map(\.message) == ["God is faithful to finish what he starts in us."])
    }

    @Test func memorableElementLabelsAreStripped() {
        let summary = """
        **Memorable Elements**
        - **Key Quotes**: "Hope is not denial. Hope is disciplined remembrance."

        Romans 5:5
        """
        #expect(plan(summary).map(\.message) == ["\"Hope is not denial. Hope is disciplined remembrance.\""])
    }

    // MARK: - What counts as meaningful

    @Test func headingsAndBareReferencesAreNotMeaningful() {
        #expect(!ScriptureReminderPlanner.isMeaningful("Key Points"))
        #expect(!ScriptureReminderPlanner.isMeaningful("Romans 8:28"))
        #expect(!ScriptureReminderPlanner.isMeaningful("Romans 8:28, John 15:5, Psalm 23:1"))
    }

    @Test func narrationAndBoilerplateAreNotMeaningful() {
        #expect(!ScriptureReminderPlanner.isMeaningful("In this sermon, we learned to trust God in hard seasons."))
        #expect(!ScriptureReminderPlanner.isMeaningful("The speaker encouraged everyone to pray more often."))
        #expect(!ScriptureReminderPlanner.isMeaningful("The pastor challenged the church to serve the city."))
        #expect(!ScriptureReminderPlanner.isMeaningful("This summary captures the main points of the message."))
    }

    @Test func fragmentsAndCutOffTextAreNotMeaningful() {
        #expect(!ScriptureReminderPlanner.isMeaningful("Trust God."))
        #expect(!ScriptureReminderPlanner.isMeaningful("When we trust God with the outcome and let go..."))
        #expect(!ScriptureReminderPlanner.isMeaningful("Remember what God has done for you in the past:"))
        #expect(!ScriptureReminderPlanner.isMeaningful("\"Hope is not pretending the storm is small, it is"))
    }

    @Test func overlongSentencesAreSkippedNotTruncated() {
        let long = String(repeating: "God is faithful in every season of life and ", count: 4) + "forever."
        #expect(long.count > ScriptureReminderPlanner.maxMessageLength)
        #expect(!ScriptureReminderPlanner.isMeaningful(long))
    }

    @Test func completeSentencesAndQuestionsAreMeaningful() {
        #expect(ScriptureReminderPlanner.isMeaningful("Prayer is the first act of trust, not a final resort."))
        #expect(ScriptureReminderPlanner.isMeaningful("Where is fear louder than faith in your life right now?"))
    }

    @Test func laterSentencesThatLeanOnTheOneBeforeAreDropped() {
        let sentences = ScriptureReminderPlanner.meaningfulSentences(
            in: "Hope is disciplined remembrance of what God has done. It looks back before it steps forward."
        )
        #expect(sentences == ["Hope is disciplined remembrance of what God has done."])
    }

    @Test func aPossiblyCutOffFinalLineIsNeverAMessage() {
        let summary = """
        Scripture References
        Romans 8:28

        Application
        - Spend five quiet minutes with God before you check your phone.
        - Choose one person to encourage this week and tell them what God
        """
        #expect(plan(summary).map(\.message) == ["Spend five quiet minutes with God before you check your phone."])
    }

    // MARK: - Headings

    @Test func headingFormsAreClassified() {
        #expect(SummaryDocument.heading(in: "**Main Scripture Text**") == .section(.mainScripture, remainder: nil))
        #expect(SummaryDocument.heading(in: "## Key Points (Comprehensive)") == .section(.keyPoints, remainder: nil))
        #expect(SummaryDocument.heading(in: "Scripture References:") == .section(.scriptureReferences, remainder: nil))
        #expect(SummaryDocument.heading(in: "**Application:** Pray daily.") == .section(.application, remainder: "Pray daily."))
        #expect(SummaryDocument.heading(in: "**Main Scripture Text**: John 1:1") == .section(.mainScripture, remainder: "John 1:1"))
        #expect(SummaryDocument.heading(in: "### Stories & Testimonies") == .section(.memorableElements, remainder: nil))
        #expect(SummaryDocument.heading(in: "**Hope That Holds**") == .subheading)
    }

    @Test func contentLinesAreNotHeadings() {
        #expect(SummaryDocument.heading(in: "- **Key Quotes**: \"Grace is enough.\"") == nil)
        #expect(SummaryDocument.heading(in: "Romans 8:28 was framed as a promise.") == nil)
        #expect(SummaryDocument.heading(in: "**Grace** is enough for today.") == nil)
    }
}
