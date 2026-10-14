import Foundation
import UserNotifications
@testable import TabletNotes

/// Records which cancel paths `SermonService` drives (TAB-119).
@MainActor
final class MockScriptureReminderScheduling: ScriptureReminderScheduling {
    private(set) var isEnabled = true
    private(set) var authorizationStatus: UNAuthorizationStatus = .authorized
    private(set) var hasSeenOptInPrompt = true
    private(set) var cancelledSermonIds: [UUID] = []
    private(set) var cancelAllCount = 0
    private(set) var resetForSignOutCount = 0
    private(set) var reconcileCount = 0

    func setEnabled(_ enabled: Bool) async { isEnabled = enabled }
    func refreshAuthorizationStatus() async {}
    func requestAuthorizationAndEnable() async -> Bool { true }
    func markOptInPromptSeen() { hasSeenOptInPrompt = true }
    func reconcile() async { reconcileCount += 1 }
    func cancelReminders(forSermonId sermonId: UUID) async { cancelledSermonIds.append(sermonId) }
    func cancelAllReminders() async { cancelAllCount += 1 }
    func resetForSignOut() async { resetForSignOutCount += 1 }
}
