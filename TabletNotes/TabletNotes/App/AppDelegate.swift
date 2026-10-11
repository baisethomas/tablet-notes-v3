import UIKit
import UserNotifications

/// Forwards background URLSession events to the process-wide UploadManager.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Must be set before launch finishes so a tap that started the app is delivered (TAB-119).
        UNUserNotificationCenter.current().delegate = ScriptureReminderTapRouter.shared
        UploadManager.shared.prepareBackgroundSessionIfNeeded()
        Task { @MainActor in
            await UploadManager.shared.continueIncompleteBackgroundUploads()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        UploadManager.shared.handleBackgroundSessionEvents(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }
}
