import Foundation

protocol AnalyticsServiceProtocol {
    func logEvent(_ name: String, parameters: [String: Any]?)
    func setUserProperty(_ value: String?, forName name: String)
} 