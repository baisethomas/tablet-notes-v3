import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import TabletNotes

// TAB-119: the scheduler turns the newest eligible sermon into pending local
// notifications, exactly once, and never acknowledges a partial run.
@MainActor
struct ScriptureReminderSchedulerTests {
    private static let newYork = TimeZone(identifier: "America/New_York")!

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        return calendar
    }

    /// Sunday 2026-09-27 11:30 in New York.
    private static let sunday: Date = calendar.date(
        from: DateComponents(year: 2026, month: 9, day: 27, hour: 11, minute: 30)
    )!

    nonisolated private static let twoScriptureSummary = """
    Scripture References
    Romans 8:28
    John 15:5

    Application
    Name one place where fear is louder than faith, then answer it this week with prayer.
    """

    // MARK: Harness

    /// Everything one test needs. A fresh instance per test keeps the
    /// UserDefaults suite and the in-memory store private to that test.
    @MainActor
    final class Harness {
        let modelContext: ModelContext
        let center = MockScriptureReminderNotificationCenter()
        let verses = MockScriptureVerseFetcher()
        let defaults: UserDefaults
        private let suiteName: String
        var now: Date = ScriptureReminderSchedulerTests.sunday

        init() throws {
            let schema = Schema([
                Sermon.self, Note.self, Transcript.self, Summary.self, ProcessingJob.self,
                TranscriptSegment.self, ChatMessage.self, User.self, UserNotificationSettings.self
            ])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            modelContext = ModelContext(container)
            suiteName = "tabletnotes.tests.scripture-reminders.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.set(true, forKey: ScriptureReminderScheduler.enabledDefaultsKey)
        }

        deinit {
            defaults.removePersistentDomain(forName: suiteName)
        }

        func makeScheduler() -> ScriptureReminderScheduler {
            ScriptureReminderScheduler(
                modelContext: modelContext,
                notificationCenter: center,
                verseFetcher: verses,
                userDefaults: defaults,
                calendar: ScriptureReminderSchedulerTests.calendar,
                now: { [unowned self] in self.now }
            )
        }

        @discardableResult
        func insertSermon(
            title: String = "Hope That Holds",
            recordedAt: Date,
            summaryText: String? = ScriptureReminderSchedulerTests.twoScriptureSummary,
            summaryStatus: String = "complete",
            isArchived: Bool = false,
            transcriptText: String? = nil
        ) throws -> Sermon {
            let sermon = Sermon(
                title: title,
                audioFileName: "\(UUID().uuidString).m4a",
                date: recordedAt,
                serviceType: "Sunday Service",
                transcript: transcriptText.map { Transcript(text: $0) },
                summary: summaryText.map { Summary(text: $0, type: "devotional", status: summaryStatus) },
                transcriptionStatus: "complete",
                summaryStatus: summaryStatus,
                isArchived: isArchived
            )
            modelContext.insert(sermon)
            try modelContext.save()
            return sermon
        }

        func pendingIdentifiers(for sermon: Sermon) -> [String] {
            let prefix = ScriptureReminderScheduler.identifierPrefix + sermon.id.uuidString + "."
            return center.pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        }
    }

    private func hoursAgo(_ hours: Double, from date: Date = sunday) -> Date {
        date.addingTimeInterval(-hours * 60 * 60)
    }

    // MARK: Scheduling

    @Test func schedulesOneRequestPerPlannedReminder() async throws {
        let harness = try Harness()
        let sermon = try harness.insertSermon(recordedAt: hoursAgo(2))
        harness.verses.verseTextByReference["Romans 8:28"] = "And we know that all things work together for good."

        await harness.makeScheduler().reconcile()

        let ids = harness.pendingIdentifiers(for: sermon)
        #expect(ids == [
            ScriptureReminderScheduler.identifier(sermonId: sermon.id, index: 0),
            ScriptureReminderScheduler.identifier(sermonId: sermon.id, index: 1)
        ])

        let first = try #require(harness.center.pending.first)
        #expect(first.content.title == "Romans 8:28 · Hope That Holds")
        #expect(first.content.body == "And we know that all things work together for good.\nName one place where fear is louder than faith, then answer it this week with prayer.")
        #expect(first.content.userInfo[ScriptureReminderScheduler.sermonIdUserInfoKey] as? String == sermon.id.uuidString)

        let trigger = try #require(first.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.day == 28)
        #expect(trigger.dateComponents.hour == 8)
        #expect(trigger.repeats == false)
    }

    @Test func reconcileTwiceSchedulesOnce() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2))
        let scheduler = harness.makeScheduler()

        await scheduler.reconcile()
        await scheduler.reconcile()
        // A fresh scheduler reads the same record, so a relaunch does not re-add either.
        await harness.makeScheduler().reconcile()

        #expect(harness.center.addedIdentifiers.count == 2)
        #expect(harness.center.pending.count == 2)
    }

    @Test func concurrentReconcilesDoNotDoubleSchedule() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2))
        let scheduler = harness.makeScheduler()

        async let first: Void = scheduler.reconcile()
        async let second: Void = scheduler.reconcile()
        _ = await (first, second)

        #expect(harness.center.addedIdentifiers.count == 2)
    }

    @Test func partialFailureRollsBackAndRetriesNextPass() async throws {
        let harness = try Harness()
        let sermon = try harness.insertSermon(recordedAt: hoursAgo(2))
        harness.center.failingIdentifierSuffix = ".1"
        let scheduler = harness.makeScheduler()

        await scheduler.reconcile()

        #expect(harness.pendingIdentifiers(for: sermon).isEmpty)
        #expect(harness.center.removedIdentifiers == [ScriptureReminderScheduler.identifier(sermonId: sermon.id, index: 0)])
        #expect(harness.defaults.stringArray(forKey: ScriptureReminderScheduler.scheduledSermonIdsDefaultsKey)?.isEmpty ?? true)

        harness.center.failingIdentifierSuffix = nil
        await scheduler.reconcile()

        #expect(harness.pendingIdentifiers(for: sermon).count == 2)
    }

    // MARK: Eligibility

    @Test func sermonsOlderThanFortyEightHoursAreNotScheduled() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(49))

        await harness.makeScheduler().reconcile()

        #expect(harness.center.pending.isEmpty)
    }

    @Test func incompleteOrArchivedSermonsAreNotScheduled() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2), summaryStatus: "processing")
        try harness.insertSermon(recordedAt: hoursAgo(3), isArchived: true)
        try harness.insertSermon(recordedAt: hoursAgo(4), summaryText: nil)

        await harness.makeScheduler().reconcile()

        #expect(harness.center.pending.isEmpty)
    }

    private static let noScriptureSummary = """
    Application
    Call one person this week who needs to hear that they are not forgotten.
    """

    @Test func sermonWithoutScriptureSendsNothingAndIsNotRecorded() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2), summaryText: Self.noScriptureSummary)

        await harness.makeScheduler().reconcile()

        #expect(harness.center.pending.isEmpty)
        let recorded = harness.defaults.stringArray(forKey: ScriptureReminderScheduler.scheduledSermonIdsDefaultsKey) ?? []
        #expect(recorded.isEmpty)
    }

    @Test func aSermonThatGainsScriptureLaterIsScheduled() async throws {
        let harness = try Harness()
        let sermon = try harness.insertSermon(recordedAt: hoursAgo(2), summaryText: Self.noScriptureSummary)
        let scheduler = harness.makeScheduler()
        await scheduler.reconcile()
        #expect(harness.center.pending.isEmpty)

        sermon.summary?.text = Self.twoScriptureSummary
        try harness.modelContext.save()
        await scheduler.reconcile()

        #expect(harness.pendingIdentifiers(for: sermon).count == 2)
    }

    @Test func aScriptureLessNewestSermonKeepsTheOlderRun() async throws {
        let harness = try Harness()
        let older = try harness.insertSermon(title: "Saturday", recordedAt: hoursAgo(20))
        let scheduler = harness.makeScheduler()
        await scheduler.reconcile()

        try harness.insertSermon(title: "Sunday", recordedAt: hoursAgo(1), summaryText: Self.noScriptureSummary)
        await scheduler.reconcile()

        #expect(harness.pendingIdentifiers(for: older).count == 2)
        #expect(harness.center.removedIdentifiers.isEmpty)
    }

    @Test func nothingIsScheduledWhenDisabledOrDenied() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2))

        harness.center.status = .denied
        await harness.makeScheduler().reconcile()
        #expect(harness.center.pending.isEmpty)

        harness.center.status = .authorized
        harness.defaults.set(false, forKey: ScriptureReminderScheduler.enabledDefaultsKey)
        await harness.makeScheduler().reconcile()
        #expect(harness.center.pending.isEmpty)
    }

    @Test func enablingSchedulesAndDisablingCancels() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2))
        harness.defaults.set(false, forKey: ScriptureReminderScheduler.enabledDefaultsKey)
        let scheduler = harness.makeScheduler()
        #expect(!scheduler.isEnabled)

        await scheduler.setEnabled(true)
        #expect(scheduler.isEnabled)
        #expect(harness.center.pending.count == 2)

        await scheduler.setEnabled(false)
        #expect(harness.center.pending.isEmpty)
        #expect(harness.defaults.bool(forKey: ScriptureReminderScheduler.enabledDefaultsKey) == false)
    }

    // MARK: Permission

    @Test func grantedPermissionEnablesAndSchedules() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2))
        harness.defaults.set(false, forKey: ScriptureReminderScheduler.enabledDefaultsKey)
        harness.center.status = .notDetermined
        let scheduler = harness.makeScheduler()

        let enabled = await scheduler.requestAuthorizationAndEnable()

        #expect(enabled)
        #expect(scheduler.isEnabled)
        #expect(scheduler.authorizationStatus == .authorized)
        #expect(scheduler.hasSeenOptInPrompt)
        #expect(harness.center.authorizationRequestCount == 1)
        #expect(harness.center.pending.count == 2)
    }

    @Test func deniedPermissionLeavesTheFeatureOff() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2))
        harness.defaults.set(false, forKey: ScriptureReminderScheduler.enabledDefaultsKey)
        harness.center.status = .notDetermined
        harness.center.grantsAuthorization = false
        let scheduler = harness.makeScheduler()

        let enabled = await scheduler.requestAuthorizationAndEnable()

        #expect(!enabled)
        #expect(!scheduler.isEnabled)
        #expect(scheduler.authorizationStatus == .denied)
        #expect(harness.center.pending.isEmpty)
        #expect(harness.defaults.bool(forKey: ScriptureReminderScheduler.enabledDefaultsKey) == false)
    }

    @Test func alreadyDecidedPermissionIsNotAskedAgain() async throws {
        let harness = try Harness()
        harness.center.status = .denied
        let scheduler = harness.makeScheduler()

        let enabled = await scheduler.requestAuthorizationAndEnable()

        #expect(!enabled)
        #expect(harness.center.authorizationRequestCount == 0)
        #expect(scheduler.authorizationStatus == .denied)
    }

    @Test func aFailedPermissionRequestReadsAsNotGranted() async throws {
        let harness = try Harness()
        harness.center.status = .notDetermined
        harness.center.authorizationRequestError = MockScriptureReminderNotificationCenter.AddFailed()
        let scheduler = harness.makeScheduler()

        #expect(await scheduler.requestAuthorizationAndEnable() == false)
        #expect(!scheduler.isEnabled)
    }

    @Test func optInPromptSeenPersistsAcrossInstances() async throws {
        let harness = try Harness()
        let scheduler = harness.makeScheduler()
        #expect(!scheduler.hasSeenOptInPrompt)

        scheduler.markOptInPromptSeen()

        #expect(scheduler.hasSeenOptInPrompt)
        #expect(harness.makeScheduler().hasSeenOptInPrompt)
    }

    @Test func refreshReadsTheCurrentSystemStatus() async throws {
        let harness = try Harness()
        harness.center.status = .provisional
        let scheduler = harness.makeScheduler()
        #expect(scheduler.authorizationStatus == .notDetermined)

        await scheduler.refreshAuthorizationStatus()

        #expect(scheduler.authorizationStatus == .provisional)
    }

    // MARK: Replacement and cancellation

    @Test func newerSermonReplacesTheOlderRunOnlyAfterItsOwnIsInPlace() async throws {
        let harness = try Harness()
        let older = try harness.insertSermon(title: "Last Week", recordedAt: hoursAgo(30))
        let scheduler = harness.makeScheduler()
        await scheduler.reconcile()
        #expect(harness.pendingIdentifiers(for: older).count == 2)

        let newer = try harness.insertSermon(title: "This Week", recordedAt: hoursAgo(1))
        await scheduler.reconcile()

        #expect(harness.pendingIdentifiers(for: newer).count == 2)
        #expect(harness.pendingIdentifiers(for: older).isEmpty)
        let newerFirstAdd = try #require(harness.center.addedIdentifiers.firstIndex { $0.contains(newer.id.uuidString) })
        // The older run was removed after the newer run's requests were added.
        #expect(harness.center.addedIdentifiers.count == 4)
        #expect(newerFirstAdd == 2)
    }

    @Test func aFailedReplacementLeavesTheOlderRunPending() async throws {
        let harness = try Harness()
        let older = try harness.insertSermon(title: "Last Week", recordedAt: hoursAgo(30))
        let scheduler = harness.makeScheduler()
        await scheduler.reconcile()

        try harness.insertSermon(title: "This Week", recordedAt: hoursAgo(1))
        harness.center.failingIdentifierSuffix = ".1"
        await scheduler.reconcile()

        #expect(harness.pendingIdentifiers(for: older).count == 2)
    }

    @Test func onlyTheNewestOfSeveralUnscheduledSermonsIsScheduled() async throws {
        let harness = try Harness()
        let older = try harness.insertSermon(title: "Saturday", recordedAt: hoursAgo(20))
        let newer = try harness.insertSermon(title: "Sunday", recordedAt: hoursAgo(1))
        let scheduler = harness.makeScheduler()

        await scheduler.reconcile()
        await scheduler.reconcile()

        #expect(harness.pendingIdentifiers(for: newer).count == 2)
        #expect(harness.pendingIdentifiers(for: older).isEmpty)
        #expect(harness.center.addedIdentifiers.count == 2)
    }

    @Test func deletingTheNewestSermonLetsAnOlderOneTakeOver() async throws {
        let harness = try Harness()
        let older = try harness.insertSermon(title: "Saturday", recordedAt: hoursAgo(20))
        let newer = try harness.insertSermon(title: "Sunday", recordedAt: hoursAgo(1))
        let scheduler = harness.makeScheduler()
        await scheduler.reconcile()
        #expect(harness.pendingIdentifiers(for: newer).count == 2)
        #expect(harness.pendingIdentifiers(for: older).isEmpty)

        await scheduler.cancelReminders(forSermonId: newer.id)
        harness.modelContext.delete(newer)
        try harness.modelContext.save()
        await scheduler.reconcile()

        #expect(harness.pendingIdentifiers(for: older).count == 2)
    }

    @Test func deletingTheOwnerAfterItReplacedAnOlderRunGivesTheOlderOneItsRunBack() async throws {
        let harness = try Harness()
        let older = try harness.insertSermon(title: "Saturday", recordedAt: hoursAgo(20))
        let scheduler = harness.makeScheduler()
        await scheduler.reconcile()
        #expect(harness.pendingIdentifiers(for: older).count == 2)

        let newer = try harness.insertSermon(title: "Sunday", recordedAt: hoursAgo(1))
        await scheduler.reconcile()
        #expect(harness.pendingIdentifiers(for: newer).count == 2)
        #expect(harness.pendingIdentifiers(for: older).isEmpty)

        await scheduler.cancelReminders(forSermonId: newer.id)
        harness.modelContext.delete(newer)
        try harness.modelContext.save()
        await scheduler.reconcile()

        #expect(harness.pendingIdentifiers(for: older).count == 2)
        #expect(harness.center.pending.count == 2)
    }

    @Test func turningOffAndOnDoesNotRepeatARun() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2))
        let scheduler = harness.makeScheduler()
        await scheduler.reconcile()
        #expect(harness.center.pending.count == 2)

        await scheduler.setEnabled(false)
        #expect(harness.center.pending.isEmpty)
        await scheduler.setEnabled(true)

        #expect(harness.center.pending.isEmpty)
        #expect(harness.center.addedIdentifiers.count == 2)
    }

    @Test func signOutResetForgetsTheScheduleRecord() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2))
        let scheduler = harness.makeScheduler()
        await scheduler.reconcile()

        await scheduler.resetForSignOut()
        #expect(harness.center.pending.isEmpty)
        await scheduler.reconcile()

        #expect(harness.center.pending.count == 2)
        #expect(harness.center.addedIdentifiers.count == 4)
    }

    @Test func turningOffDuringAVerseFetchAddsNothing() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2))
        harness.verses.delayNanoseconds = 300_000_000
        let scheduler = harness.makeScheduler()

        async let pass: Void = scheduler.reconcile()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(harness.verses.requestedReferences.count == 1)
        await scheduler.setEnabled(false)
        await pass

        #expect(harness.center.addedIdentifiers.isEmpty)
        #expect(harness.center.pending.isEmpty)
        let recorded = harness.defaults.stringArray(forKey: ScriptureReminderScheduler.scheduledSermonIdsDefaultsKey) ?? []
        #expect(recorded.isEmpty)
    }

    @Test func deletingDuringAVerseFetchAddsNothing() async throws {
        let harness = try Harness()
        let sermon = try harness.insertSermon(recordedAt: hoursAgo(2))
        harness.verses.delayNanoseconds = 300_000_000
        let scheduler = harness.makeScheduler()

        async let pass: Void = scheduler.reconcile()
        try await Task.sleep(nanoseconds: 50_000_000)
        await scheduler.cancelReminders(forSermonId: sermon.id)
        await pass

        #expect(harness.center.addedIdentifiers.isEmpty)
        #expect(harness.center.pending.isEmpty)
    }

    @Test func signOutDuringTheFinalPendingLookupLeavesNoRecordAndNoRequests() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2))
        // The reconcile's own lookup, after its adds, is the one that stalls.
        harness.center.nextPendingLookupDelayNanoseconds = 300_000_000
        let scheduler = harness.makeScheduler()

        async let pass: Void = scheduler.reconcile()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(harness.center.addedIdentifiers.count == 2)
        await scheduler.resetForSignOut()
        #expect(harness.center.pending.isEmpty)
        await pass

        #expect(harness.center.pending.isEmpty)
        let recorded = harness.defaults.stringArray(forKey: ScriptureReminderScheduler.scheduledSermonIdsDefaultsKey) ?? []
        #expect(recorded.isEmpty)
    }

    @Test func cancellingASermonRemovesOnlyItsRequests() async throws {
        let harness = try Harness()
        let sermon = try harness.insertSermon(recordedAt: hoursAgo(2))
        let scheduler = harness.makeScheduler()
        await scheduler.reconcile()
        let unrelated = UNNotificationRequest(identifier: "other.notification", content: UNMutableNotificationContent(), trigger: nil)
        try await harness.center.add(unrelated)

        await scheduler.cancelReminders(forSermonId: sermon.id)

        #expect(harness.center.pending.map(\.identifier) == ["other.notification"])
    }

    @Test func cancellingAllRemovesEveryReminderAndNothingElse() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2))
        let scheduler = harness.makeScheduler()
        await scheduler.reconcile()
        let unrelated = UNNotificationRequest(identifier: "other.notification", content: UNMutableNotificationContent(), trigger: nil)
        try await harness.center.add(unrelated)

        await scheduler.cancelAllReminders()

        #expect(harness.center.pending.map(\.identifier) == ["other.notification"])
    }

    // MARK: Content

    @Test func verseFetchFailureStillSchedulesWithTheReference() async throws {
        let harness = try Harness()
        try harness.insertSermon(recordedAt: hoursAgo(2))
        harness.verses.shouldFail = true

        await harness.makeScheduler().reconcile()

        let first = try #require(harness.center.pending.first)
        #expect(first.content.body == "Romans 8:28\nName one place where fear is louder than faith, then answer it this week with prayer.")
    }

    @Test func titleIsTheFallbackLineWhenTheSummaryHasNoMeaningfulSentence() async throws {
        let harness = try Harness()
        let summary = """
        Scripture References
        Romans 8:28
        """
        try harness.insertSermon(title: "Grace Upon Grace", recordedAt: hoursAgo(2), summaryText: summary)

        await harness.makeScheduler().reconcile()

        let first = try #require(harness.center.pending.first)
        #expect(first.content.body == "Verse text for Romans 8:28.\nGrace Upon Grace")
    }

    @Test func longVersesAreShortenedAtAWordBoundary() {
        let verse = String(repeating: "word ", count: 60).trimmingCharacters(in: .whitespaces)
        let shortened = ScriptureReminderScheduler.shortened(verse)
        #expect(shortened.hasSuffix("…"))
        #expect(shortened.count <= ScriptureReminderScheduler.maxVerseLength + 1)
        #expect(!shortened.contains("wor…"))
        #expect(ScriptureReminderScheduler.shortened("Be still, and know that I am God.") == "Be still, and know that I am God.")
    }

    @Test func verseHTMLIsReducedToPlainText() {
        let html = "<p class=\"p\"><span data-number=\"28\" class=\"v\">28</span>And we know that all things work together for good to them that love God, &amp; are the called.</p>"
        #expect(BibleVerseTextFetcher.plainText(html) == "And we know that all things work together for good to them that love God, & are the called.")
    }
}
