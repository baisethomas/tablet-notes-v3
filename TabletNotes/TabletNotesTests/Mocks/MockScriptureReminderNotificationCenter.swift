import Foundation
import UserNotifications
@testable import TabletNotes

/// Stands in for `UNUserNotificationCenter` in the scheduler tests (TAB-119).
/// Keeps every added request so tests can inspect content and triggers.
/// Not actor-isolated: the scheduler suite only drives it from the main actor.
final class MockScriptureReminderNotificationCenter: ScriptureReminderNotificationCenter {
    var status: UNAuthorizationStatus = .authorized
    /// What the system prompt answers; it also moves `status` accordingly.
    var grantsAuthorization = true
    var authorizationRequestError: Error?
    private(set) var authorizationRequestCount = 0
    /// Adding a request whose identifier ends with this suffix throws.
    var failingIdentifierSuffix: String?
    /// Delays the next `pendingRequestIdentifiers()` call only, so a test can
    /// run a cancel to completion while one reconcile is suspended there.
    var nextPendingLookupDelayNanoseconds: UInt64 = 0

    private(set) var pending: [UNNotificationRequest] = []
    private(set) var addedIdentifiers: [String] = []
    private(set) var removedIdentifiers: [String] = []

    struct AddFailed: Error {}

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        if let authorizationRequestError { throw authorizationRequestError }
        status = grantsAuthorization ? .authorized : .denied
        return grantsAuthorization
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
        if nextPendingLookupDelayNanoseconds > 0 {
            let delay = nextPendingLookupDelayNanoseconds
            nextPendingLookupDelayNanoseconds = 0
            try? await Task.sleep(nanoseconds: delay)
        }
        return pending.map(\.identifier)
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
    /// Simulates a slow proxy so a test can cancel while a fetch is in flight.
    var delayNanoseconds: UInt64 = 0
    private(set) var requestedReferences: [String] = []

    struct FetchFailed: Error {}

    func verseText(for reference: ScriptureReference) async throws -> String {
        requestedReferences.append(reference.displayText)
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if shouldFail { throw FetchFailed() }
        return verseTextByReference[reference.displayText] ?? "Verse text for \(reference.displayText)."
    }
}
