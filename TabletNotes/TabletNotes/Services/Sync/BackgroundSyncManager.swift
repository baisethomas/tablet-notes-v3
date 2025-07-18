import Foundation
import UIKit
import Network

class BackgroundSyncManager: ObservableObject {
    
    // MARK: - Properties
    
    private let syncService: SyncServiceProtocol
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    @Published private(set) var networkStatus: NetworkStatus = .unknown
    @Published private(set) var isBackgroundSyncEnabled = true
    
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var syncTimer: Timer?
    
    // MARK: - Network Status
    
    enum NetworkStatus {
        case unknown
        case connected
        case disconnected
        case expensive // Cellular data
    }
    
    // MARK: - Initialization
    
    init(syncService: SyncServiceProtocol) {
        self.syncService = syncService
        setupNetworkMonitoring()
        setupAppLifecycleObservers()
        setupPeriodicSync()
    }
    
    deinit {
        networkMonitor.cancel()
        syncTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handleNetworkStatusChange(path)
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    private func handleNetworkStatusChange(_ path: NWPath) {
        let newStatus: NetworkStatus
        
        if path.status == .satisfied {
            if path.isExpensive {
                newStatus = .expensive
            } else {
                newStatus = .connected
            }
        } else {
            newStatus = .disconnected
        }
        
        if newStatus != networkStatus {
            networkStatus = newStatus
            
            // Trigger sync when network becomes available
            if newStatus == .connected {
                scheduleImmediateSync()
            }
        }
    }
    
    // MARK: - App Lifecycle Observers
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        startBackgroundSync()
    }
    
    @objc private func appWillEnterForeground() {
        endBackgroundSync()
        scheduleImmediateSync()
    }
    
    @objc private func appWillTerminate() {
        endBackgroundSync()
    }
    
    // MARK: - Background Sync
    
    private func startBackgroundSync() {
        guard backgroundTaskID == .invalid else { return }
        
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SyncData") { [weak self] in
            self?.endBackgroundSync()
        }
        
        // Perform sync if network is available
        if networkStatus == .connected {
            Task {
                await performBackgroundSync()
            }
        }
    }
    
    private func endBackgroundSync() {
        guard backgroundTaskID != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
    
    private func performBackgroundSync() async {
        guard isBackgroundSyncEnabled else { return }
        
        do {
            await syncService.syncAllData()
        } catch {
            print("[BackgroundSyncManager] Background sync failed: \(error)")
        }
        
        endBackgroundSync()
    }
    
    // MARK: - Periodic Sync
    
    private func setupPeriodicSync() {
        // Sync every 5 minutes when app is active
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.schedulePeriodicSync()
        }
    }
    
    private func schedulePeriodicSync() {
        guard isBackgroundSyncEnabled,
              networkStatus == .connected else { return }
        
        Task {
            await syncService.syncAllData()
        }
    }
    
    // MARK: - Manual Sync Controls
    
    func scheduleImmediateSync() {
        guard networkStatus == .connected else { return }
        
        Task {
            await syncService.syncAllData()
        }
    }
    
    func enableBackgroundSync() {
        isBackgroundSyncEnabled = true
        UserDefaults.standard.set(true, forKey: "backgroundSyncEnabled")
    }
    
    func disableBackgroundSync() {
        isBackgroundSyncEnabled = false
        UserDefaults.standard.set(false, forKey: "backgroundSyncEnabled")
        endBackgroundSync()
    }
    
    // MARK: - Sync Policies
    
    func shouldSyncOnCellular() -> Bool {
        return UserDefaults.standard.bool(forKey: "syncOnCellular")
    }
    
    func setSyncOnCellular(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "syncOnCellular")
    }
    
    func canSyncNow() -> Bool {
        switch networkStatus {
        case .connected:
            return true
        case .expensive:
            return shouldSyncOnCellular()
        case .disconnected, .unknown:
            return false
        }
    }
}