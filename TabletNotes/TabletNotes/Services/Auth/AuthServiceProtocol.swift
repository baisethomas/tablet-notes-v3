import Foundation
import Combine

protocol AuthServiceProtocol {
    var currentUserPublisher: AnyPublisher<User?, Never> { get }
    func signIn(email: String, password: String) -> AnyPublisher<Bool, Error>
    func signOut() -> AnyPublisher<Bool, Error>
}

// Placeholder User type for protocol
class User {} 