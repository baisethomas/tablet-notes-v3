import Foundation
import SwiftData
import Network
import Combine

struct PendingTranscription: Codable, Identifiable {
    let id: UUID
    let audioFileURL: URL
    let sermonTitle: String
    let sermonDate: Date
    let serviceType: String
    let createdAt: Date
    let retryCount: Int
    
    init(audioFileURL: URL, sermonTitle: String, sermonDate: Date, serviceType: String) {
        self.id = UUID()
        self.audioFileURL = audioFileURL
        self.sermonTitle = sermonTitle
        self.sermonDate = sermonDate
        self.serviceType = serviceType
        self.createdAt = Date()
        self.retryCount = 0
    }
    
    private init(id: UUID, audioFileURL: URL, sermonTitle: String, sermonDate: Date, serviceType: String, createdAt: Date, retryCount: Int) {
        self.id = id
        self.audioFileURL = audioFileURL
        self.sermonTitle = sermonTitle
        self.sermonDate = sermonDate
        self.serviceType = serviceType
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
    
    func withIncrementedRetryCount() -> PendingTranscription {
        return PendingTranscription(
            id: self.id,
            audioFileURL: self.audioFileURL,
            sermonTitle: self.sermonTitle,
            sermonDate: self.sermonDate,
            serviceType: self.serviceType,
            createdAt: self.createdAt,
            retryCount: self.retryCount + 1
        )
    }
}

class TranscriptionRetryService: ObservableObject {
    static let shared = TranscriptionRetryService()
    
    @Published var pendingTranscriptions: [PendingTranscription] = []
    @Published var isProcessingQueue = false
    
    // Notification for when transcription completes
    static let transcriptionCompletedNotification = Notification.Name("TranscriptionCompleted")
    
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    private var isNetworkAvailable = false
    
    private let userDefaults = UserDefaults.standard
    private let pendingTranscriptionsKey = "PendingTranscriptions"
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadPendingTranscriptions()
        startNetworkMonitoring()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasAvailable = self?.isNetworkAvailable ?? false
                self?.isNetworkAvailable = path.status == .satisfied
                
                // If network just became available and we have pending transcriptions, process them
                if !wasAvailable && path.status == .satisfied && !(self?.pendingTranscriptions.isEmpty ?? true) {
                    self?.processQueue()
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    func addPendingTranscription(_ transcription: PendingTranscription) {
        pendingTranscriptions.append(transcription)
        savePendingTranscriptions()
        
        // Try to process immediately if network is available
        if isNetworkAvailable {
            processQueue()
        }
    }
    
    func removePendingTranscription(withId id: UUID) {
        pendingTranscriptions.removeAll { $0.id == id }
        savePendingTranscriptions()
    }
    
    func retryTranscriptionIfNeeded(for sermon: Sermon) {
        // Check if there's a pending transcription for this sermon's audio file
        let hasPendingTranscription = pendingTranscriptions.contains { pending in
            pending.audioFileURL == sermon.audioFileURL
        }
        
        // If sermon has failed or pending transcription status and no pending retry, add it to queue
        if (sermon.transcriptionStatus == "failed" || sermon.transcriptionStatus == "pending") && !hasPendingTranscription && isNetworkAvailable {
            let pendingTranscription = PendingTranscription(
                audioFileURL: sermon.audioFileURL,
                sermonTitle: sermon.title,
                sermonDate: sermon.date,
                serviceType: sermon.serviceType
            )
            addPendingTranscription(pendingTranscription)
        }
    }
    
    func processQueue() {
        guard !isProcessingQueue && !pendingTranscriptions.isEmpty && isNetworkAvailable else { return }
        
        isProcessingQueue = true
        
        let transcriptionService = TranscriptionService()
        let maxRetries = 3
        
        // Process one at a time to avoid overwhelming the service
        if let nextTranscription = pendingTranscriptions.first {
            transcriptionService.transcribeAudioFileWithResult(url: nextTranscription.audioFileURL) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let (text, segments)):
                        // Create the sermon with transcription
                        if let context = self?.modelContext {
                            let sermon = Sermon(
                                title: nextTranscription.sermonTitle,
                                audioFileURL: nextTranscription.audioFileURL,
                                date: nextTranscription.sermonDate,
                                serviceType: nextTranscription.serviceType,
                                speaker: "", // Default empty speaker
                                transcriptionStatus: "complete"
                            )
                            
                            // Set transcription status and create transcript
                            sermon.transcriptionStatus = "complete"
                            
                            let transcript = Transcript(
                                text: text
                            )
                            
                            // Add transcript segments
                            for segment in segments {
                                let transcriptSegment = TranscriptSegment(
                                    text: segment.text,
                                    startTime: segment.startTime,
                                    endTime: segment.endTime
                                )
                                transcript.segments.append(transcriptSegment)
                            }
                            
                            sermon.transcript = transcript

                            // CRITICAL: Mark sermon for sync so transcript gets pushed to backend
                            sermon.needsSync = true
                            sermon.updatedAt = Date()
                            sermon.syncStatus = "pending"

                            // Save to SwiftData
                            context.insert(sermon)
                            try? context.save()

                            // Notify UI that transcription completed
                            NotificationCenter.default.post(
                                name: TranscriptionRetryService.transcriptionCompletedNotification,
                                object: sermon.id
                            )

                            // Generate summary after successful transcription
                            self?.generateSummaryForSermon(sermon)
                        }
                        
                        self?.removePendingTranscription(withId: nextTranscription.id)
                        
                    case .failure(let error):
                        if nextTranscription.retryCount < maxRetries {
                            // Update retry count and move to end of queue
                            self?.removePendingTranscription(withId: nextTranscription.id)
                            let updatedTranscription = nextTranscription.withIncrementedRetryCount()
                            self?.pendingTranscriptions.append(updatedTranscription)
                            self?.savePendingTranscriptions()
                        } else {
                            // Max retries reached, remove from queue
                            self?.removePendingTranscription(withId: nextTranscription.id)
                        }
                    }
                    
                    self?.isProcessingQueue = false
                    
                    // Continue processing if there are more items
                    if !(self?.pendingTranscriptions.isEmpty ?? true) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self?.processQueue()
                        }
                    }
                }
            }
        }
    }
    
    private func savePendingTranscriptions() {
        do {
            let data = try JSONEncoder().encode(pendingTranscriptions)
            userDefaults.set(data, forKey: pendingTranscriptionsKey)
        } catch {
            // Handle error silently
        }
    }
    
    private func loadPendingTranscriptions() {
        guard let data = userDefaults.data(forKey: pendingTranscriptionsKey) else { return }
        
        do {
            pendingTranscriptions = try JSONDecoder().decode([PendingTranscription].self, from: data)
        } catch {
            // Handle error silently
        }
    }
    
    // Clean up old pending transcriptions (older than 7 days)
    func cleanupOldTranscriptions() {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let originalCount = pendingTranscriptions.count
        
        pendingTranscriptions.removeAll { $0.createdAt < sevenDaysAgo }
        
        if pendingTranscriptions.count != originalCount {
            savePendingTranscriptions()
        }
    }
    
    private func generateSummaryForSermon(_ sermon: Sermon) {
        guard let transcript = sermon.transcript, !transcript.text.isEmpty else {
            return
        }
        
        // Set summary status to processing
        sermon.summaryStatus = "processing"
        
        // Save status update
        if let context = modelContext {
            try? context.save()
        }
        
        // Create summary service and generate summary
        let summaryService = SummaryService()
        summaryService.generateSummary(for: transcript.text, type: sermon.serviceType)
        
        // Subscribe to summary completion
        summaryService.statusPublisher
            .combineLatest(summaryService.titlePublisher, summaryService.summaryPublisher)
            .sink { (status, titleText, summaryText) in
                DispatchQueue.main.async {
                    switch status {
                    case "complete":
                        if let summaryText = summaryText {
                            // Create Summary object with AI-generated title
                            let summaryTitle = titleText ?? "Sermon Summary"
                            let summary = Summary(
                                title: summaryTitle,
                                text: summaryText,
                                type: "devotional", // Default type
                                status: "complete"
                            )
                            sermon.summary = summary
                            sermon.summaryStatus = "complete"

                            // CRITICAL: Mark sermon for sync so summary gets pushed to backend
                            sermon.needsSync = true
                            sermon.updatedAt = Date()
                            sermon.syncStatus = "pending"
                        } else {
                            sermon.summaryStatus = "failed"
                        }

                    case "failed":
                        sermon.summaryStatus = "failed"

                    default:
                        break
                    }

                    // Save changes
                    if let context = self.modelContext {
                        try? context.save()
                    }
                }
            }
            .store(in: &cancellables)
    }
}