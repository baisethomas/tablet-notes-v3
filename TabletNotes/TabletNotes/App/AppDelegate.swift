import UIKit

/// Forwards background URLSession events to the process-wide UploadManager.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Touch the singleton synchronously on the main thread so the background
        // session exists before SyncService / MainAppView can race it (TAB-73 Part B).
        MainActor.assumeIsolated {
            UploadManager.shared.prepareBackgroundSessionIfNeeded()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Also main-thread; keep the completion handler path synchronous so the
        // session is adopted before iOS expects the handler to be stored.
        MainActor.assumeIsolated {
            UploadManager.shared.handleBackgroundSessionEvents(
                identifier: identifier,
                completionHandler: completionHandler
            )
        }
    }
}
