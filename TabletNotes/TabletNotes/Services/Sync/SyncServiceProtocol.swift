import Foundation

@MainActor
protocol SyncUserProviding: AnyObject {
    var currentUser: User? { get }
}

@MainActor
protocol SyncServiceProtocol: AnyObject {
    func syncAllData() async
    func deleteAllCloudData() async
}

extension AuthenticationManager: SyncUserProviding {}
