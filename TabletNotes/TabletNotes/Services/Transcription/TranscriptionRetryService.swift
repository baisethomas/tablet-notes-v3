import Foundation
import SwiftData
import Network

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
        
        // If sermon has failed transcription status and no pending retry, add it to queue
        if sermon.transcriptionStatus == "failed" && !hasPendingTranscription && isNetworkAvailable {
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
            print("[TranscriptionRetryService] Processing pending transcription: \(nextTranscription.sermonTitle)")
            
            transcriptionService.transcribeAudioFileWithResult(url: nextTranscription.audioFileURL) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let (text, segments)):
                        print("[TranscriptionRetryService] Successfully processed pending transcription")
                        
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
                            
                            // Save to SwiftData
                            context.insert(sermon)
                            try? context.save()
                            
                            // Notify UI that transcription completed
                            NotificationCenter.default.post(
                                name: TranscriptionRetryService.transcriptionCompletedNotification,
                                object: sermon.id
                            )
                        }
                        
                        self?.removePendingTranscription(withId: nextTranscription.id)
                        
                    case .failure(let error):
                        print("[TranscriptionRetryService] Failed to process pending transcription: \(error.localizedDescription)")
                        
                        if nextTranscription.retryCount < maxRetries {
                            // Update retry count and move to end of queue
                            self?.removePendingTranscription(withId: nextTranscription.id)
                            let updatedTranscription = nextTranscription.withIncrementedRetryCount()
                            self?.pendingTranscriptions.append(updatedTranscription)
                            self?.savePendingTranscriptions()
                        } else {
                            // Max retries reached, remove from queue
                            print("[TranscriptionRetryService] Max retries reached for transcription, removing from queue")
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
            print("[TranscriptionRetryService] Failed to save pending transcriptions: \(error)")
        }
    }
    
    private func loadPendingTranscriptions() {
        guard let data = userDefaults.data(forKey: pendingTranscriptionsKey) else { return }
        
        do {
            pendingTranscriptions = try JSONDecoder().decode([PendingTranscription].self, from: data)
            print("[TranscriptionRetryService] Loaded \(pendingTranscriptions.count) pending transcriptions")
        } catch {
            print("[TranscriptionRetryService] Failed to load pending transcriptions: \(error)")
        }
    }
    
    // Clean up old pending transcriptions (older than 7 days)
    func cleanupOldTranscriptions() {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let originalCount = pendingTranscriptions.count
        
        pendingTranscriptions.removeAll { $0.createdAt < sevenDaysAgo }
        
        if pendingTranscriptions.count != originalCount {
            savePendingTranscriptions()
            print("[TranscriptionRetryService] Cleaned up \(originalCount - pendingTranscriptions.count) old pending transcriptions")
        }
    }
}