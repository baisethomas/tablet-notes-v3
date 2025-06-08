import Foundation

protocol NotificationServiceProtocol {
    func showBanner(message: String, action: (() -> Void)?)
} 