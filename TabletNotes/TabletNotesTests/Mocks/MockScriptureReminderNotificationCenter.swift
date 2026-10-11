import Foundation
import UserNotifications
@testable import TabletNotes

/// Stands in for `UNUserNotificationCenter` in the scheduler tests (TAB-119).
/// Keeps every added request so tests can inspect content and triggers.
/// Not actor-isolated: the scheduler suite only drives it from the main actor.
final class MockScriptureReminderNotificationCenter: ScriptureReminderNotificationCenter {
    var status: UNAuthorizationStatus = .authorized
    /// Adding a request whose identifier ends with this suffix throws.
    var failingIdentifierSuffix: String?

    private(set) var pending: [UNNotificationRequest] = []
    private(set) var addedIdentifiers: [String] = []
    private(set) var removedIdentifiers: [String] = []

    struct AddFailed: Error {}

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func add(_ request: UNNotificationRequest) async throws {
        if let failingIdentifierSuffix, request.identifier.hasSuffix(failingIdentifierSuffix) {
            throw AddFailed()
        }
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
        addedIdentifiers.append(request.identifier)
    }

    func pendingRequestIdentifiers() async -> [String] {
        pending.map(\.identifier)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
        pending.removeAll { identifiers.contains($0.identifier) }
    }
}

/// Returns canned verse text, or throws, so the scheduler is tested offline.
final class MockScriptureVerseFetcher: ScriptureVerseFetching {
    var verseTextByReference: [String: String] = [:]
    var shouldFail = false
    private(set) var requestedReferences: [String] = []

    struct FetchFailed: Error {}

    func verseText(for reference: ScriptureReference) async throws -> String {
        requestedReferences.append(reference.displayText)
        if shouldFail { throw FetchFailed() }
        return verseTextByReference[reference.displayText] ?? "Verse text for \(reference.displayText)."
    }
}
