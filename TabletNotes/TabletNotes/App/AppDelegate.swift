import UIKit

/// Forwards background URLSession events to the process-wide UploadManager.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Touch the singleton at launch so the background session exists before
        // any SyncService / MainAppView rebuild can race it (TAB-73 Part B).
        Task { @MainActor in
            UploadManager.shared.prepareBackgroundSessionIfNeeded()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            UploadManager.shared.handleBackgroundSessionEvents(
                identifier: identifier,
                completionHandler: completionHandler
            )
        }
    }
}
