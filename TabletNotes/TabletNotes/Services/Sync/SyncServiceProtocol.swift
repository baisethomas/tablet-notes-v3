import Foundation
import Combine

@MainActor
protocol SyncUserProviding: AnyObject {
    var currentUser: User? { get }
}

@MainActor
protocol SyncServiceProtocol {
    var syncStatusPublisher: AnyPublisher<String, Never> { get } // e.g., syncing, synced, error
    var errorPublisher: AnyPublisher<Error?, Never> { get }
    func syncAllData() async
    func deleteAllCloudData() async
}

extension AuthenticationManager: SyncUserProviding {}
