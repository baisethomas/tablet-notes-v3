import Foundation

@MainActor
protocol SyncUserProviding: AnyObject {
    var currentUser: User? { get }
}

@MainActor
protocol SyncServiceProtocol: AnyObject {
    func syncAllData() async
    /// Runs a full sync and reports whether it actually completed successfully.
    /// Used by cloud restore (TAB-53) to clear the store-reset signal only on a
    /// confirmed success — connectivity alone doesn't prove the backend/auth sync
    /// worked.
    @discardableResult
    func syncAllDataReportingSuccess() async -> Bool
    func deleteRemoteSermon(remoteId: String) async throws
    func deleteAllCloudData() async
}

extension AuthenticationManager: SyncUserProviding {}
