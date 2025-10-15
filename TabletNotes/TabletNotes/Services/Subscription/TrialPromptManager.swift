import Foundation
import SwiftUI

/// Manages when to show the trial expiration prompt based on user dismissals
class TrialPromptManager: ObservableObject {
    static let shared = TrialPromptManager()

    @AppStorage("lastTrialPromptDismissedDate") private var lastDismissedDateString: String = ""
    @AppStorage("trialPromptDismissCount") private var dismissCount: Int = 0

    private init() {}

    /// Determines if the trial prompt should be shown
    func shouldShowPrompt(for trialState: SubscriptionTrialState) -> Bool {
        guard case .trialExpired = trialState else {
            return false
        }

        // Always show on first dismissal (when lastDismissedDate is empty)
        guard !lastDismissedDateString.isEmpty else {
            return true
        }

        guard let lastDismissedDate = parseDate(lastDismissedDateString) else {
            return true
        }

        let now = Date()
        let daysSinceDismissal = Calendar.current.dateComponents([.day], from: lastDismissedDate, to: now).day ?? 0

        // Frequency based on how many times dismissed
        switch dismissCount {
        case 0:
            // First dismissal - show immediately
            return true
        case 1...7:
            // Days 1-7: Show once per day
            return daysSinceDismissal >= 1
        default:
            // After 7 dismissals: Show once per week
            return daysSinceDismissal >= 7
        }
    }

    /// Records that the user dismissed the prompt
    func recordDismissal() {
        lastDismissedDateString = formatDate(Date())
        dismissCount += 1

        print("[TrialPromptManager] Prompt dismissed. Count: \(dismissCount)")
    }

    /// Resets the prompt tracking (e.g., when user subscribes)
    func reset() {
        lastDismissedDateString = ""
        dismissCount = 0
        print("[TrialPromptManager] Prompt tracking reset")
    }

    // MARK: - Private Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
}
