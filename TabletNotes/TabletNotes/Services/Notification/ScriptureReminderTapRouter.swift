import Foundation
import Observation
import UserNotifications

/// Receives scripture reminder taps and hands the sermon id to the UI (TAB-119).
///
/// `UNUserNotificationCenter`'s delegate must be set before the app finishes
/// launching, which is earlier than any view exists, so this is a process-wide
/// object like `SermonProcessingCoordinator`: `AppDelegate` installs it and
/// `MainAppView` watches `pendingSermonId`. It has no side effects of its own.
@MainActor
@Observable
final class ScriptureReminderTapRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ScriptureReminderTapRouter()

    /// The sermon the user asked to open. Stays set until the UI consumes it,
    /// so a tap that lands before the main view appears is not lost.
    private(set) var pendingSermonId: UUID?

    func consumePendingSermonId() -> UUID? {
        defer { pendingSermonId = nil }
        return pendingSermonId
    }

    /// The sermon a notification names, or nil when it is not a scripture reminder.
    nonisolated static func sermonId(in content: UNNotificationContent) -> UUID? {
        guard let raw = content.userInfo[ScriptureReminderScheduler.sermonIdUserInfoKey] as? String else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Reminders show as a banner even while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard Self.sermonId(in: notification.request.content) != nil else { return [] }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let sermonId = Self.sermonId(in: response.notification.request.content) else {
            return
        }
        await MainActor.run {
            pendingSermonId = sermonId
        }
    }
}
