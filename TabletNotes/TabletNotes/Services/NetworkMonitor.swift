import Foundation
import Network
import Observation

/// Monitors network connectivity and path changes using NWPathMonitor
/// Follows best practices from swift-networking skill
@Observable
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    // Observable properties (no @Published needed with @Observable)
    private(set) var isConnected = false
    private(set) var connectionType: ConnectionType = .unknown
    private(set) var isExpensive = false

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.tabletnotes.networkmonitor")

    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
    }

    private init() {
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            // Update connection status on main thread for SwiftUI observation
            Task { @MainActor in
                self.isConnected = path.status == .satisfied
                self.isExpensive = path.isExpensive

                // Determine connection type
                if path.usesInterfaceType(.wifi) {
                    self.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self.connectionType = .ethernet
                } else {
                    self.connectionType = .unknown
                }

                // Log network changes for debugging
                print("[NetworkMonitor] Network status changed:")
                print("  - Connected: \(self.isConnected)")
                print("  - Type: \(self.connectionType)")
                print("  - Expensive: \(self.isExpensive)")
            }
        }

        monitor.start(queue: monitorQueue)
        print("[NetworkMonitor] Started monitoring network path")
    }

    deinit {
        monitor.cancel()
    }
}
