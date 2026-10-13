import Foundation
import Observation
import SwiftData
import UserNotifications

// MARK: - Seams

/// The slice of `UNUserNotificationCenter` the scheduler uses, so tests can
/// stand in for the system center (TAB-119).
protocol ScriptureReminderNotificationCenter: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    /// Shows the system permission prompt. True when the user allowed alerts.
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingRequestIdentifiers() async -> [String]
    func removePendingRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: ScriptureReminderNotificationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await requestAuthorization(options: [.alert, .sound, .badge])
    }

    func pendingRequestIdentifiers() async -> [String] {
        await pendingNotificationRequests().map(\.identifier)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Looks up the verse text that a reminder's body shows. Injected so the
/// scheduler's tests never touch the network.
protocol ScriptureVerseFetching {
    func verseText(for reference: ScriptureReference) async throws -> String
}

/// Fetches verse text through the Bible proxy in the user's preferred translation.
/// Built at the app root with the app's `BibleAPIService` (its init is main-actor).
struct BibleVerseTextFetcher: ScriptureVerseFetching {
    private let bibleService: BibleAPIService

    init(bibleService: BibleAPIService) {
        self.bibleService = bibleService
    }

    func verseText(for reference: ScriptureReference) async throws -> String {
        let bibleId = ApiBibleConfig.preferredBibleTranslationId
        let content: String
        if reference.isRange {
            content = try await bibleService.fetchPassage(reference: reference.displayText, bibleId: bibleId).content
        } else {
            content = try await bibleService.fetchVerse(reference: reference.displayText, bibleId: bibleId).content
        }
        return Self.plainText(content)
    }

    private static let tagPattern = try! NSRegularExpression(pattern: "<[^>]+>")
    private static let verseNumberPattern = try! NSRegularExpression(pattern: #"(?<![\w])\d+(?=[A-Za-z])"#)

    /// Strips the proxy's HTML and the leading verse numbers, which read as
    /// noise in a one-line notification body.
    static func plainText(_ html: String) -> String {
        var text = tagPattern.stringByReplacingMatches(
            in: html, range: NSRange(html.startIndex..., in: html), withTemplate: ""
        )
        text = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        text = verseNumberPattern.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ""
        )
        return text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

// MARK: - Scheduler

@MainActor
protocol ScriptureReminderScheduling: AnyObject {
    /// The global opt-in. Turning it off cancels every pending reminder.
    var isEnabled: Bool { get }
    /// The system permission as of the last `refreshAuthorizationStatus()`.
    var authorizationStatus: UNAuthorizationStatus { get }
    /// True once the in-context opt-in card has been answered either way.
    var hasSeenOptInPrompt: Bool { get }
    func setEnabled(_ enabled: Bool) async
    func refreshAuthorizationStatus() async
    /// Asks for permission if needed and turns the feature on when granted.
    /// Returns whether the feature is on afterwards.
    func requestAuthorizationAndEnable() async -> Bool
    func markOptInPromptSeen()
    /// Schedules reminders for the newest eligible sermon. Safe to call on every
    /// launch, foreground, and summary completion: a sermon is scheduled once.
    func reconcile() async
    func cancelReminders(forSermonId sermonId: UUID) async
    /// Removes every pending reminder but keeps the record of which sermons
    /// were scheduled, so turning the feature off and on does not repeat a run.
    func cancelAllReminders() async
    /// Sign-out: removes every pending reminder and forgets the schedule record,
    /// so a later sign-in reschedules whatever is still eligible.
    func resetForSignOut() async
}

/// Schedules a sermon's scripture reminders as local notifications (TAB-119).
///
/// This is a reconciler rather than a completion hook: summaries complete through
/// several paths (legacy retry, the durable pipeline, sync), so instead of hooking
/// each one, `reconcile()` looks at what is eligible now and schedules what is
/// missing. A sermon is recorded as scheduled only after every request has been
/// added, so a partial failure is retried on the next pass instead of being
/// silently acknowledged.
@MainActor
@Observable
final class ScriptureReminderScheduler: ScriptureReminderScheduling {
    static let identifierPrefix = "scripture-reminder."
    static let sermonIdUserInfoKey = "sermonId"
    /// Sermons recorded longer ago than this are never scheduled, so a cloud
    /// restore or reinstall does not fire reminders for old sermons.
    static let eligibilityWindow: TimeInterval = 48 * 60 * 60
    static let maxVerseLength = 180

    static let enabledDefaultsKey = "scriptureRemindersEnabled"
    static let scheduledSermonIdsDefaultsKey = "scriptureReminders.scheduledSermonIds"
    static let optInPromptSeenDefaultsKey = "scriptureReminders.optInPromptSeen"

    private(set) var isEnabled: Bool
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var hasSeenOptInPrompt: Bool

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let planner: ScriptureReminderPlanner
    @ObservationIgnored private let notificationCenter: any ScriptureReminderNotificationCenter
    @ObservationIgnored private let verseFetcher: any ScriptureVerseFetching
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    /// Serialises overlapping `reconcile()` calls (launch and foreground can
    /// arrive together) so two passes never schedule the same sermon twice.
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    /// Bumped by every cancel path. A reconcile that started before the bump
    /// re-checks it after each await so it never adds requests behind a cancel.
    @ObservationIgnored private var cancellationGeneration = 0

    init(
        modelContext: ModelContext,
        planner: ScriptureReminderPlanner = ScriptureReminderPlanner(),
        notificationCenter: any ScriptureReminderNotificationCenter = UNUserNotificationCenter.current(),
        verseFetcher: any ScriptureVerseFetching,
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.planner = planner
        self.notificationCenter = notificationCenter
        self.verseFetcher = verseFetcher
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.now = now
        self.isEnabled = userDefaults.bool(forKey: Self.enabledDefaultsKey)
        self.hasSeenOptInPrompt = userDefaults.bool(forKey: Self.optInPromptSeenDefaultsKey)
    }

    // MARK: Opt-in

    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        userDefaults.set(enabled, forKey: Self.enabledDefaultsKey)
        if enabled {
            await reconcile()
        } else {
            await cancelAllReminders()
        }
    }

    // MARK: Permission

    func refreshAuthorizationStatus() async {
        authorizationStatus = await notificationCenter.authorizationStatus()
    }

    func requestAuthorizationAndEnable() async -> Bool {
        markOptInPromptSeen()
        await refreshAuthorizationStatus()
        if authorizationStatus == .notDetermined {
            // A thrown error reads as "not granted"; the status refresh below
            // reports whatever the system actually recorded.
            _ = try? await notificationCenter.requestAuthorization()
            await refreshAuthorizationStatus()
        }
        guard isAuthorized(authorizationStatus) else {
            if isEnabled {
                await setEnabled(false)
            }
            return false
        }
        await setEnabled(true)
        return true
    }

    func markOptInPromptSeen() {
        guard !hasSeenOptInPrompt else { return }
        hasSeenOptInPrompt = true
        userDefaults.set(true, forKey: Self.optInPromptSeenDefaultsKey)
    }

    // MARK: Reconcile

    func reconcile() async {
        if let inFlight {
            await inFlight.value
        }
        let task = Task { await self.reconcileNow() }
        inFlight = task
        await task.value
        if inFlight == task {
            inFlight = nil
        }
    }

    private func reconcileNow() async {
        guard isEnabled else { return }
        guard await isAuthorized() else { return }
        let generation = cancellationGeneration

        let eligible = eligibleSermons()
        var scheduled = scheduledSermonIds()
        // Ids outside the window can never be scheduled again; drop them so the set stays small.
        scheduled.formIntersection(eligible.map(\.id))

        // The newest eligible sermon that has something to say owns the week. A
        // sermon with no scripture is skipped, not recorded, so a later summary
        // that does carry scripture still gets its run; and once the owner is
        // scheduled, older sermons stay as they are until the owner goes away
        // (deleted or archived), at which point the next one takes over.
        guard let (sermon, plan) = eligible.lazy
            .map({ ($0, self.plan(for: $0)) })
            .first(where: { !$0.1.isEmpty }) else {
            saveScheduledSermonIds(scheduled)
            return
        }
        guard !scheduled.contains(sermon.id) else {
            saveScheduledSermonIds(scheduled)
            return
        }

        let requests = await requests(for: sermon, plan: plan)
        // A cancel (feature off, delete, archive, sign-out) that ran while the
        // verse fetches were in flight wins: nothing is added behind it.
        guard isStillWanted(generation) else { return }

        var added: [String] = []
        for request in requests {
            do {
                try await notificationCenter.add(request)
                added.append(request.identifier)
            } catch {
                // Partial failure is failure: undo what went in and leave the sermon
                // unscheduled so the next pass retries from scratch.
                notificationCenter.removePendingRequests(withIdentifiers: added)
                return
            }
            guard isStillWanted(generation) else {
                notificationCenter.removePendingRequests(withIdentifiers: added)
                return
            }
        }

        // Only one sermon's run is pending at a time (iOS caps pending local
        // notifications at 64, and two runs would double up mornings). Older
        // runs are removed only now, after the new run is fully in place.
        let others = await notificationCenter.pendingRequestIdentifiers().filter {
            $0.hasPrefix(Self.identifierPrefix) && !added.contains($0)
        }
        if !others.isEmpty {
            notificationCenter.removePendingRequests(withIdentifiers: others)
        }

        scheduled.insert(sermon.id)
        saveScheduledSermonIds(scheduled)
    }

    private func isStillWanted(_ generation: Int) -> Bool {
        isEnabled && generation == cancellationGeneration
    }

    // MARK: Cancel

    func cancelReminders(forSermonId sermonId: UUID) async {
        cancellationGeneration += 1
        let prefix = Self.identifierPrefix + sermonId.uuidString + "."
        let identifiers = await notificationCenter.pendingRequestIdentifiers().filter { $0.hasPrefix(prefix) }
        if !identifiers.isEmpty {
            notificationCenter.removePendingRequests(withIdentifiers: identifiers)
        }
    }

    func cancelAllReminders() async {
        cancellationGeneration += 1
        let identifiers = await notificationCenter.pendingRequestIdentifiers().filter {
            $0.hasPrefix(Self.identifierPrefix)
        }
        if !identifiers.isEmpty {
            notificationCenter.removePendingRequests(withIdentifiers: identifiers)
        }
    }

    func resetForSignOut() async {
        await cancelAllReminders()
        saveScheduledSermonIds([])
    }

    // MARK: Eligibility

    private func isAuthorized() async -> Bool {
        await refreshAuthorizationStatus()
        return isAuthorized(authorizationStatus)
    }

    private func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    /// Summary complete, not archived, recorded inside the window; newest first.
    private func eligibleSermons() -> [Sermon] {
        let cutoff = now().addingTimeInterval(-Self.eligibilityWindow)
        let complete = "complete"
        var descriptor = FetchDescriptor<Sermon>(
            predicate: #Predicate<Sermon> { sermon in
                sermon.summaryStatus == complete && sermon.isArchived == false && sermon.date >= cutoff
            },
            sortBy: [SortDescriptor(\Sermon.date, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        let sermons = (try? modelContext.fetch(descriptor)) ?? []
        return sermons.filter { !($0.summary?.text.isEmpty ?? true) }
    }

    private func scheduledSermonIds() -> Set<UUID> {
        let stored = userDefaults.stringArray(forKey: Self.scheduledSermonIdsDefaultsKey) ?? []
        return Set(stored.compactMap(UUID.init(uuidString:)))
    }

    private func saveScheduledSermonIds(_ ids: Set<UUID>) {
        userDefaults.set(ids.map(\.uuidString).sorted(), forKey: Self.scheduledSermonIdsDefaultsKey)
    }

    // MARK: Requests

    private func plan(for sermon: Sermon) -> [PlannedScriptureReminder] {
        planner.plan(
            summaryText: sermon.summary?.text ?? "",
            transcriptText: sermon.transcript?.text,
            now: now(),
            calendar: calendar
        )
    }

    private func requests(for sermon: Sermon, plan: [PlannedScriptureReminder]) async -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        for reminder in plan {
            // Verse text is fetched at scheduling time because the body is static.
            // Offline or a proxy error still sends the reminder, with the reference alone.
            let verseText = try? await verseFetcher.verseText(for: reminder.reference)
            let content = Self.content(for: reminder, sermonTitle: sermon.title, verseText: verseText)
            content.userInfo = [Self.sermonIdUserInfoKey: sermon.id.uuidString]
            requests.append(UNNotificationRequest(
                identifier: Self.identifier(sermonId: sermon.id, index: reminder.index),
                content: content,
                trigger: Self.trigger(for: reminder)
            ))
        }
        return requests
    }

    private static func trigger(for reminder: PlannedScriptureReminder) -> UNNotificationTrigger {
        #if DEBUG
        // Manual verification only: SCRIPTURE_REMINDER_DEBUG_DELAY_SECONDS=20 fires
        // the run 20s, 40s, 60s... after scheduling instead of on the planned mornings.
        if let raw = ProcessInfo.processInfo.environment["SCRIPTURE_REMINDER_DEBUG_DELAY_SECONDS"],
           let seconds = TimeInterval(raw), seconds >= 1 {
            return UNTimeIntervalNotificationTrigger(timeInterval: seconds * TimeInterval(reminder.index + 1), repeats: false)
        }
        #endif
        return UNCalendarNotificationTrigger(dateMatching: reminder.fireDateComponents, repeats: false)
    }

    static func identifier(sermonId: UUID, index: Int) -> String {
        "\(identifierPrefix)\(sermonId.uuidString).\(index)"
    }

    /// Title: "Romans 8:28 · Hope That Holds". Body: the verse (shortened at a
    /// word boundary) and the summary line, or the sermon title when the
    /// planner found no meaningful line.
    static func content(
        for reminder: PlannedScriptureReminder,
        sermonTitle: String,
        verseText: String?
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let reference = reminder.reference.displayText
        let title = sermonTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        content.title = title.isEmpty ? reference : "\(reference) · \(title)"

        let line = reminder.message ?? (title.isEmpty ? nil : title)
        if let verse = verseText.map(shortened), !verse.isEmpty {
            content.body = [verse, line].compactMap { $0 }.joined(separator: "\n")
        } else {
            content.body = [reference, line].compactMap { $0 }.joined(separator: "\n")
        }
        content.sound = .default
        return content
    }

    static func shortened(_ verse: String) -> String {
        let text = verse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > maxVerseLength else { return text }
        let head = text.prefix(maxVerseLength)
        let cut = head.lastIndex(where: \.isWhitespace).map { head[..<$0] } ?? head
        let trimmed = cut.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
        return trimmed + "…"
    }
}
