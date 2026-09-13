import Foundation
import os

/// Breadcrumbs for the recording-notes pipeline (TAB-113).
///
/// `print()` never reaches the device log on an App Store build, so the two
/// real-length sermons that lost their note (9/6, 9/13) left nothing to read.
/// These go through the unified logging system: visible in Xcode's console
/// AND in Console.app / `log show` for a release build with the phone attached.
enum NotesLog {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Creative-Native.TabletNotes",
        category: "notes"
    )
}
