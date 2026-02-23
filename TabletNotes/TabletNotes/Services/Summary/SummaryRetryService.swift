import Foundation
import SwiftData
import Network
import Combine

struct PendingSummary: Codable, Identifiable {
    let id: UUID
    let sermonId: UUID
    let transcript: String
    let serviceType: String
    let createdAt: Date
    let retryCount: Int
    let lastAttemptAt: Date?
    
    init(sermonId: UUID, transcript: String, serviceType: String) {
        self.id = UUID()
        self.sermonId = sermonId
        self.transcript = transcript
        self.serviceType = serviceType
        self.createdAt = Date()
        self.retryCount = 0
        self.lastAttemptAt = nil
    }
    
    private init(id: UUID, sermonId: UUID, transcript: String, serviceType: String, createdAt: Date, retryCount: Int, lastAttemptAt: Date?) {
        self.id = id
        self.sermonId = sermonId
        self.transcript = transcript
        self.serviceType = serviceType
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastAttemptAt = lastAttemptAt
    }
    
    func withIncrementedRetryCount() -> PendingSummary {
        return PendingSummary(
            id: self.id,
            sermonId: self.sermonId,
            transcript: self.transcript,
            serviceType: self.serviceType,
            createdAt: self.createdAt,
            retryCount: self.retryCount + 1,
            lastAttemptAt: Date()
        )
    }
}

@MainActor
class SummaryRetryService: ObservableObject {
    static let shared = SummaryRetryService()
    
    @Published var pendingSummaries: [PendingSummary] = []
    @Published var isProcessingQueue = false
    
    // Notification for when summary completes
    static let summaryCompletedNotification = Notification.Name("SummaryCompleted")
    
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "SummaryNetworkMonitor")
    private var isNetworkAvailable = false
    
    private let userDefaults = UserDefaults.standard
    private let pendingSummariesKey = "PendingSummaries"
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private let maxRetries = 3
    private let processingTimeoutMinutes: TimeInterval = 10 // 10 minutes timeout
    
    private init() {
        loadPendingSummaries()
        startNetworkMonitoring()
    }

    private func upsertSummary(
        on sermon: Sermon,
        in context: ModelContext,
        title: String,
        text: String,
        type: String,
        status: String
    ) {
        if let existingSummary = sermon.summary {
            existingSummary.title = title
            existingSummary.text = text
            existingSummary.type = type
            existingSummary.status = status
            sermon.summaryPreviewText = Sermon.makeSummaryPreview(from: text)
            return
        }

        let summary = Summary(
            title: title,
            text: text,
            type: type,
            status: status
        )
        context.insert(summary)
        sermon.summary = summary
        sermon.summaryPreviewText = Sermon.makeSummaryPreview(from: text)
    }

    private func resetActiveRequestSubscriptions() {
        cancellables.removeAll()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasAvailable = self?.isNetworkAvailable ?? false
                self?.isNetworkAvailable = path.status == .satisfied
                
                // If network just became available and we have pending summaries, process them
                if !wasAvailable && path.status == .satisfied && !(self?.pendingSummaries.isEmpty ?? true) {
                    self?.processQueue()
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    func addPendingSummary(_ summary: PendingSummary) {
        // Check if already exists
        if !pendingSummaries.contains(where: { $0.sermonId == summary.sermonId }) {
            pendingSummaries.append(summary)
            savePendingSummaries()
            
            // Try to process immediately if network is available
            if isNetworkAvailable {
                processQueue()
            }
        }
    }
    
    func removePendingSummary(withId id: UUID) {
        pendingSummaries.removeAll { $0.id == id }
        savePendingSummaries()
    }
    
    func retrySummaryIfNeeded(for sermon: Sermon) {
        // Check if there's a pending summary for this sermon
        let hasPendingSummary = pendingSummaries.contains { pending in
            pending.sermonId == sermon.id
        }
        
        // If sermon has failed or processing summary status and no pending retry, add it to queue
        if (sermon.summaryStatus == "failed" || sermon.summaryStatus == "processing") && !hasPendingSummary {
            guard let transcript = sermon.transcript, !transcript.text.isEmpty else {
                print("[SummaryRetryService] Cannot retry: No transcript available for sermon \(sermon.id)")
                return
            }
            
            let pendingSummary = PendingSummary(
                sermonId: sermon.id,
                transcript: transcript.text,
                serviceType: sermon.serviceType
            )
            addPendingSummary(pendingSummary)
        }
    }
    
    // Check for sermons stuck in "processing" status
    func checkForStuckProcessingSummaries() {
        guard let context = modelContext else {
            print("[SummaryRetryService] No model context available")
            return
        }
        
        let fetchDescriptor = FetchDescriptor<Sermon>(
            predicate: #Predicate<Sermon> { sermon in
                sermon.summaryStatus == "processing"
            }
        )
        
        guard let processingSermons = try? context.fetch(fetchDescriptor) else {
            return
        }
        
        let timeoutThreshold = Date().addingTimeInterval(-processingTimeoutMinutes * 60)
        
        for sermon in processingSermons {
            // Check if sermon has been processing too long
            if let updatedAt = sermon.updatedAt, updatedAt < timeoutThreshold {
                print("[SummaryRetryService] Found stuck processing summary for sermon \(sermon.id), adding to retry queue")
                
                guard let transcript = sermon.transcript, !transcript.text.isEmpty else {
                    // Mark as failed if no transcript
                    sermon.summaryStatus = "failed"
                    try? context.save()
                    continue
                }
                
                // Add to retry queue
                let pendingSummary = PendingSummary(
                    sermonId: sermon.id,
                    transcript: transcript.text,
                    serviceType: sermon.serviceType
                )
                addPendingSummary(pendingSummary)
            }
        }
    }
    
    func processQueue() {
        guard !isProcessingQueue && !pendingSummaries.isEmpty && isNetworkAvailable else { return }

        // SummaryService is a shared singleton. Avoid stealing/cancelling an in-flight UI request.
        if SummaryService.shared.statusSubject.value == "pending" {
            print("[SummaryRetryService] ⏳ SummaryService busy (pending); deferring queue processing")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                Task { @MainActor in
                    self?.processQueue()
                }
            }
            return
        }

        isProcessingQueue = true

        // Process one at a time to avoid overwhelming the service
        if let nextSummary = pendingSummaries.first {
            print("[SummaryRetryService] Processing pending summary for sermon \(nextSummary.sermonId)")

            let summaryService = SummaryService.shared
            resetActiveRequestSubscriptions()

            var hasSeenPending = false

            // Subscribe to summary completion
            summaryService.statusPublisher
                .combineLatest(summaryService.titlePublisher, summaryService.summaryPublisher)
                .dropFirst() // Ignore stale replay from previous SummaryService requests.
                .sink { [weak self] (status, titleText, summaryText) in
                    Task { @MainActor in
                        guard let self = self else { return }

                        if status == "pending" {
                            hasSeenPending = true
                            print("[SummaryRetryService] 🔄 Summary retry request started for sermon \(nextSummary.sermonId)")
                            return
                        }

                        if (status == "complete" || status == "failed") && !hasSeenPending {
                            print("[SummaryRetryService] ⚠️ Ignoring stale terminal state '\(status)'")
                            return
                        }

                        var shouldAdvanceQueue = false

                        switch status {
                        case "complete":
                            if let summaryText = summaryText, let context = self.modelContext {
                                // Find the sermon and update it
                                let fetchDescriptor = FetchDescriptor<Sermon>(
                                    predicate: #Predicate<Sermon> { sermon in
                                        sermon.id == nextSummary.sermonId
                                    }
                                )
                                
                                if let sermon = try? context.fetch(fetchDescriptor).first {
                                    let summaryTitle = titleText ?? "Sermon Summary"
                                    self.upsertSummary(
                                        on: sermon,
                                        in: context,
                                        title: summaryTitle,
                                        text: summaryText,
                                        type: nextSummary.serviceType,
                                        status: "complete"
                                    )
                                    sermon.summaryStatus = "complete"
                                    
                                    // Mark for sync
                                    sermon.needsSync = true
                                    sermon.updatedAt = Date()
                                    sermon.syncStatus = "pending"
                                    
                                    try? context.save()
                                    
                                    print("[SummaryRetryService] ✅ Summary completed for sermon \(sermon.id)")
                                    
                                    // Notify UI
                                    NotificationCenter.default.post(
                                        name: SummaryRetryService.summaryCompletedNotification,
                                        object: sermon.id
                                    )
                                }
                            }

                            self.removePendingSummary(withId: nextSummary.id)
                            shouldAdvanceQueue = true

                        case "failed":
                            print("[SummaryRetryService] Summary generation failed for sermon \(nextSummary.sermonId), retry count: \(nextSummary.retryCount)")

                            if nextSummary.retryCount < self.maxRetries {
                                // Update retry count and move to end of queue with exponential backoff delay
                                self.removePendingSummary(withId: nextSummary.id)
                                let updatedSummary = nextSummary.withIncrementedRetryCount()
                                
                                // Exponential backoff: wait 2^retryCount minutes
                                let backoffMinutes = pow(2.0, Double(updatedSummary.retryCount))
                                let delay = backoffMinutes * 60
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    Task { @MainActor in
                                        self.addPendingSummary(updatedSummary)
                                    }
                                }
                                
                                print("[SummaryRetryService] Will retry summary in \(backoffMinutes) minutes")
                            } else {
                                // Max retries reached, try basic summary as fallback
                                print("[SummaryRetryService] Max retries reached, attempting basic summary fallback")
                                self.attemptBasicSummaryFallback(for: nextSummary)
                                self.removePendingSummary(withId: nextSummary.id)
                                // Queue advancement is handled by the fallback subscription terminal state.
                                shouldAdvanceQueue = false
                            }
                            if nextSummary.retryCount < self.maxRetries {
                                shouldAdvanceQueue = true
                            }

                        default:
                            return
                        }

                        guard shouldAdvanceQueue else { return }
                        self.resetActiveRequestSubscriptions()
                        self.isProcessingQueue = false

                        // Continue processing if there are more items
                        if !self.pendingSummaries.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                Task { @MainActor in
                                    self.processQueue()
                                }
                            }
                        }
                    }
                }
                .store(in: &cancellables)

            // Start generation after subscription is attached.
            summaryService.generateSummary(for: nextSummary.transcript, type: nextSummary.serviceType)
        }
    }
    
    private func attemptBasicSummaryFallback(for pendingSummary: PendingSummary) {
        let summaryService = SummaryService.shared
        resetActiveRequestSubscriptions()

        var hasSeenPending = false

        // Subscribe to basic summary completion
        summaryService.statusPublisher
            .combineLatest(summaryService.titlePublisher, summaryService.summaryPublisher)
            .dropFirst() // Ignore stale replay from the previous request.
            .sink { (status, titleText, summaryText) in
                Task { @MainActor in
                    if status == "pending" {
                        hasSeenPending = true
                        print("[SummaryRetryService] 🔄 Basic summary fallback started for sermon \(pendingSummary.sermonId)")
                        return
                    }

                    if (status == "complete" || status == "failed") && !hasSeenPending {
                        print("[SummaryRetryService] ⚠️ Ignoring stale basic-summary terminal state '\(status)'")
                        return
                    }

                    guard let context = self.modelContext else {
                        print("[SummaryRetryService] No model context available for basic summary fallback")
                        self.resetActiveRequestSubscriptions()
                        return
                    }

                    let fetchDescriptor = FetchDescriptor<Sermon>(
                        predicate: #Predicate<Sermon> { sermon in
                            sermon.id == pendingSummary.sermonId
                        }
                    )

                    guard let sermon = try? context.fetch(fetchDescriptor).first else {
                        print("[SummaryRetryService] Sermon \(pendingSummary.sermonId) not found for basic summary fallback")
                        self.resetActiveRequestSubscriptions()
                        return
                    }

                    switch status {
                    case "complete":
                        if let summaryText {
                            let summaryTitle = titleText ?? "Sermon Summary"
                            self.upsertSummary(
                                on: sermon,
                                in: context,
                                title: summaryTitle,
                                text: summaryText,
                                type: pendingSummary.serviceType,
                                status: "complete"
                            )
                            sermon.summaryStatus = "complete"

                            // Mark for sync
                            sermon.needsSync = true
                            sermon.updatedAt = Date()
                            sermon.syncStatus = "pending"

                            try? context.save()

                            print("[SummaryRetryService] ✅ Basic summary fallback completed for sermon \(sermon.id)")

                            // Notify UI
                            NotificationCenter.default.post(
                                name: SummaryRetryService.summaryCompletedNotification,
                                object: sermon.id
                            )
                        } else {
                            sermon.summaryStatus = "failed"
                            try? context.save()
                            print("[SummaryRetryService] ❌ Basic summary fallback reported complete without summary text")
                        }

                    case "failed":
                        sermon.summaryStatus = "failed"
                        try? context.save()
                        print("[SummaryRetryService] ❌ Basic summary fallback failed for sermon \(sermon.id)")

                    default:
                        return
                    }

                    self.resetActiveRequestSubscriptions()
                    self.isProcessingQueue = false

                    if !self.pendingSummaries.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            Task { @MainActor in
                                self.processQueue()
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)

        // Start generation after subscription is attached. generateBasicSummary sends pending synchronously.
        summaryService.generateBasicSummary(for: pendingSummary.transcript, type: pendingSummary.serviceType)
    }
    
    private func savePendingSummaries() {
        do {
            let data = try JSONEncoder().encode(pendingSummaries)
            userDefaults.set(data, forKey: pendingSummariesKey)
        } catch {
            print("[SummaryRetryService] Failed to save pending summaries: \(error)")
        }
    }
    
    private func loadPendingSummaries() {
        guard let data = userDefaults.data(forKey: pendingSummariesKey) else { return }
        
        do {
            pendingSummaries = try JSONDecoder().decode([PendingSummary].self, from: data)
            print("[SummaryRetryService] Loaded \(pendingSummaries.count) pending summaries")
        } catch {
            print("[SummaryRetryService] Failed to load pending summaries: \(error)")
        }
    }
    
    // Clean up old pending summaries (older than 7 days)
    func cleanupOldSummaries() {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let originalCount = pendingSummaries.count
        
        pendingSummaries.removeAll { $0.createdAt < sevenDaysAgo }
        
        if pendingSummaries.count != originalCount {
            savePendingSummaries()
            print("[SummaryRetryService] Cleaned up \(originalCount - pendingSummaries.count) old pending summaries")
        }
    }
}
