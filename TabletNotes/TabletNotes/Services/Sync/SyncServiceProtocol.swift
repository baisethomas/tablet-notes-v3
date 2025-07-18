import Foundation
import Combine

protocol SyncServiceProtocol {
    var syncStatusPublisher: AnyPublisher<String, Never> { get } // e.g., syncing, synced, error
    var errorPublisher: AnyPublisher<Error?, Never> { get }
    func syncAllData() async
    func deleteAllCloudData() async
} 