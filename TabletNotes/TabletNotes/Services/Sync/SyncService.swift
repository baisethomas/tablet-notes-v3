import Foundation
import Combine
import SwiftData
import Supabase

class SyncService: ObservableObject, SyncServiceProtocol {

    // MARK: - Properties

    private let modelContext: ModelContext
    private let supabaseService: SupabaseServiceProtocol
    private let authService: AuthenticationManager

    @Published private var syncStatus: String = "idle"
    @Published private var syncError: Error?
    
    var syncStatusPublisher: AnyPublisher<String, Never> {
        $syncStatus.eraseToAnyPublisher()
    }
    
    var errorPublisher: AnyPublisher<Error?, Never> {
        $syncError.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext, supabaseService: SupabaseServiceProtocol, authService: AuthenticationManager) {
        self.modelContext = modelContext
        self.supabaseService = supabaseService
        self.authService = authService
    }
    
    // MARK: - Public Methods
    
    func syncAllData() async {
        await performFullSync()
    }
    
    func deleteAllCloudData() async {
        await performCloudDataDeletion()
    }
    
    // MARK: - Sync Operations
    
    @MainActor
    private func performFullSync() async {
        print("[SyncService] 🔄 Starting full sync...")

        // Check if user can sync
        guard let currentUser = authService.currentUser else {
            print("[SyncService] ❌ No current user - cannot sync")
            syncError = SyncError.subscriptionRequired
            return
        }

        print("[SyncService] Current user: \(currentUser.email), canSync: \(currentUser.canSync)")

        guard currentUser.canSync else {
            print("[SyncService] ❌ User cannot sync (requires Premium subscription)")
            syncError = SyncError.subscriptionRequired
            return
        }

        syncStatus = "syncing"
        syncError = nil

        do {
            // 1. Push local changes to cloud
            print("[SyncService] 📤 Pushing local changes...")
            try await pushLocalChanges()

            // 2. Pull cloud changes to local
            print("[SyncService] 📥 Pulling cloud changes...")
            try await pullCloudChanges()

            syncStatus = "synced"
            print("[SyncService] ✅ Sync completed successfully")
        } catch {
            syncStatus = "error"
            syncError = error
            print("[SyncService] ❌ Sync failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func pushLocalChanges() async throws {
        // Get all local sermons that need syncing
        // Only sync sermons that are explicitly marked needsSync=true
        // (Don't sync old sermons that just have remoteId=nil)
        let descriptor = FetchDescriptor<Sermon>(
            predicate: #Predicate<Sermon> { sermon in
                sermon.needsSync == true
            }
        )

        let sermonsToSync = try modelContext.fetch(descriptor)
        print("[SyncService] Found \(sermonsToSync.count) sermons marked for sync")

        for sermon in sermonsToSync {
            print("[SyncService] Syncing sermon: \(sermon.title)")
            try await syncSermonToCloud(sermon)
        }
    }
    
    private func pullCloudChanges() async throws {
        guard let currentUser = await authService.currentUser else { return }

        // Fetch all remote sermons for current user
        let remoteSermons = try await fetchRemoteSermons(for: currentUser.id)
        print("[SyncService] Found \(remoteSermons.count) remote sermons to pull")

        for remoteSermon in remoteSermons {
            print("[SyncService] Syncing remote sermon: \(remoteSermon.title)")
            try await syncSermonFromCloud(remoteSermon)
        }
    }
    
    private func syncSermonToCloud(_ sermon: Sermon) async throws {
        let sermonData = SermonSyncData(
            id: sermon.id,
            title: sermon.title,
            audioFileURL: sermon.audioFileURL,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: sermon.speaker,
            transcriptionStatus: sermon.transcriptionStatus,
            summaryStatus: sermon.summaryStatus,
            isArchived: sermon.isArchived,
            userId: sermon.userId,
            updatedAt: sermon.updatedAt ?? Date()
        )

        // Upload to Supabase
        if let remoteId = sermon.remoteId {
            // Update existing record - pass full sermon to include notes/transcript/summary
            try await updateRemoteSermon(sermon: sermon, remoteId: remoteId, data: sermonData)
        } else {
            // Create new record - pass full sermon to include notes/transcript/summary
            let newRemoteId = try await createRemoteSermon(sermon: sermon, data: sermonData)
            sermon.remoteId = newRemoteId
        }

        // Update local sync metadata
        sermon.lastSyncedAt = Date()
        sermon.needsSync = false
        sermon.syncStatus = "synced"

        // Related data is now included in create/update payloads
        // No need to call syncRelatedData separately

        try modelContext.save()
    }
    
    private func syncSermonFromCloud(_ remoteSermon: RemoteSermonData) async throws {
        print("[SyncService] 📥 Syncing sermon from cloud: \(remoteSermon.title)")

        // Find existing local sermon by remoteId
        let remoteId = remoteSermon.id
        let descriptor = FetchDescriptor<Sermon>(
            predicate: #Predicate<Sermon> { sermon in
                sermon.remoteId == remoteId
            }
        )

        let existingSermons = try modelContext.fetch(descriptor)

        if let existingSermon = existingSermons.first {
            print("[SyncService] Found existing local sermon with remoteId: \(remoteId)")

            // Download audio file if it doesn't exist locally
            if !existingSermon.audioFileExists {
                print("[SyncService] Audio file missing locally, attempting download...")
                do {
                    let localAudioURL = try await downloadAudioFile(from: remoteSermon.audioFileURL, remotePath: remoteSermon.audioFilePath)
                    existingSermon.audioFileName = localAudioURL.lastPathComponent
                    print("[SyncService] ✅ Audio file downloaded successfully")
                } catch {
                    print("[SyncService] ⚠️ Audio download failed, but continuing with sermon sync: \(error.localizedDescription)")
                    // Continue with sync even if audio download fails
                    // The sermon metadata will still be synced
                }
            }

            // Update existing sermon if remote is newer
            if remoteSermon.updatedAt > (existingSermon.updatedAt ?? Date.distantPast) {
                print("[SyncService] Remote sermon is newer, updating local copy")
                updateLocalSermon(existingSermon, with: remoteSermon)
            } else {
                print("[SyncService] Local sermon is up to date")
            }

            try modelContext.save()
        } else {
            print("[SyncService] No existing local sermon found, creating new one")
            // Create new local sermon
            try await createLocalSermon(from: remoteSermon)
        }
    }
    
    private func syncRelatedData(for sermon: Sermon) async throws {
        // Sync notes
        for note in sermon.notes {
            try await syncNoteToCloud(note, sermonId: sermon.remoteId!)
        }
        
        // Sync transcript
        if let transcript = sermon.transcript {
            try await syncTranscriptToCloud(transcript, sermonId: sermon.remoteId!)
        }
        
        // Sync summary
        if let summary = sermon.summary {
            try await syncSummaryToCloud(summary, sermonId: sermon.remoteId!)
        }
    }
    
    private func performCloudDataDeletion() async {
        guard let currentUser = await authService.currentUser else { return }
        
        do {
            try await deleteAllRemoteData(for: currentUser.id)
            
            // Reset local sync metadata
            let descriptor = FetchDescriptor<Sermon>()
            let allSermons = try modelContext.fetch(descriptor)
            
            for sermon in allSermons {
                sermon.remoteId = nil
                sermon.lastSyncedAt = nil
                sermon.syncStatus = "localOnly"
                sermon.needsSync = false
            }
            
            try modelContext.save()
        } catch {
            syncError = error
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateLocalSermon(_ sermon: Sermon, with remoteData: RemoteSermonData) {
        print("[SyncService] 🔄 Updating local sermon: \(remoteData.title)")

        // Update basic fields
        sermon.title = remoteData.title
        sermon.serviceType = remoteData.serviceType
        sermon.speaker = remoteData.speaker
        sermon.isArchived = remoteData.isArchived
        sermon.transcriptionStatus = remoteData.transcriptionStatus
        sermon.summaryStatus = remoteData.summaryStatus
        sermon.updatedAt = remoteData.updatedAt
        sermon.lastSyncedAt = Date()
        sermon.syncStatus = "synced"

        // Update notes - prefer remote data, but preserve local if remote is unexpectedly empty
        if let remoteNotes = remoteData.notes, !remoteNotes.isEmpty {
            print("[SyncService] Updating \(remoteNotes.count) notes from remote")

            // Clear existing notes and add remote ones
            // Using last-writer-wins strategy: remote data replaces local
            sermon.notes.removeAll()

            for noteData in remoteNotes {
                let note = Note(
                    id: noteData.localId,
                    text: noteData.text,
                    timestamp: noteData.timestamp,
                    remoteId: noteData.id
                )
                sermon.notes.append(note)
            }
            print("[SyncService] ✅ Notes updated from remote")
        } else if sermon.notes.isEmpty && remoteData.notes?.isEmpty == true {
            print("[SyncService] ℹ️ Both local and remote notes are empty")
        } else if !sermon.notes.isEmpty && (remoteData.notes == nil || remoteData.notes?.isEmpty == true) {
            print("[SyncService] ⚠️ Preserving \(sermon.notes.count) local notes (remote returned no notes)")
        }

        // Update transcript - prefer remote data, but preserve local if remote is unexpectedly empty
        if let transcriptData = remoteData.transcript {
            print("[SyncService] Updating transcript from remote (length: \(transcriptData.text.count) chars)")

            if let existingTranscript = sermon.transcript {
                // Update existing transcript
                existingTranscript.text = transcriptData.text
                existingTranscript.segments = [] // TODO: deserialize segments from JSON if needed
                existingTranscript.remoteId = transcriptData.id
                print("[SyncService] ✅ Existing transcript updated from remote")
            } else {
                // Create new transcript
                let transcript = Transcript(
                    id: transcriptData.localId,
                    text: transcriptData.text,
                    segments: [],
                    remoteId: transcriptData.id
                )
                sermon.transcript = transcript
                print("[SyncService] ✅ New transcript created from remote")
            }
        } else if sermon.transcript != nil {
            let localLength = sermon.transcript?.text.count ?? 0
            print("[SyncService] ⚠️ Preserving local transcript (\(localLength) chars) - remote returned no transcript")
        } else {
            print("[SyncService] ℹ️ No transcript on local or remote")
        }

        // Update summary - prefer remote data, but preserve local if remote is unexpectedly empty
        if let summaryData = remoteData.summary {
            print("[SyncService] Updating summary from remote (length: \(summaryData.text.count) chars)")

            if let existingSummary = sermon.summary {
                // Update existing summary
                existingSummary.title = summaryData.title
                existingSummary.text = summaryData.text
                existingSummary.type = summaryData.type
                existingSummary.status = summaryData.status
                existingSummary.remoteId = summaryData.id
                print("[SyncService] ✅ Existing summary updated from remote")
            } else {
                // Create new summary
                let summary = Summary(
                    id: summaryData.localId,
                    title: summaryData.title,
                    text: summaryData.text,
                    type: summaryData.type,
                    status: summaryData.status,
                    remoteId: summaryData.id
                )
                sermon.summary = summary
                print("[SyncService] ✅ New summary created from remote")
            }
        } else if sermon.summary != nil {
            let localLength = sermon.summary?.text.count ?? 0
            print("[SyncService] ⚠️ Preserving local summary (\(localLength) chars) - remote returned no summary")
        } else {
            print("[SyncService] ℹ️ No summary on local or remote")
        }
    }
    
    private func createLocalSermon(from remoteData: RemoteSermonData) async throws {
        print("[SyncService] 📥 Creating local sermon from remote data: \(remoteData.title)")
        print("[SyncService] Remote audio URL: \(remoteData.audioFileURL)")
        if let path = remoteData.audioFilePath {
            print("[SyncService] Remote audio path: \(path)")
        }

        // Download audio file if needed
        do {
            let localAudioURL = try await downloadAudioFile(from: remoteData.audioFileURL, remotePath: remoteData.audioFilePath)
            print("[SyncService] ✅ Audio file downloaded to: \(localAudioURL.path)")

            let sermon = Sermon(
                id: remoteData.localId,
                title: remoteData.title,
                audioFileURL: localAudioURL,
                date: remoteData.date,
                serviceType: remoteData.serviceType,
                speaker: remoteData.speaker,
                syncStatus: "synced",
                transcriptionStatus: remoteData.transcriptionStatus,
                summaryStatus: remoteData.summaryStatus,
                isArchived: remoteData.isArchived,
                userId: remoteData.userId,
                lastSyncedAt: Date(),
                remoteId: remoteData.id,
                updatedAt: remoteData.updatedAt
            )

            // Create related records
            if let remoteNotes = remoteData.notes {
                print("[SyncService] Creating \(remoteNotes.count) notes")
                for noteData in remoteNotes {
                    let note = Note(
                        id: noteData.localId,
                        text: noteData.text,
                        timestamp: noteData.timestamp,
                        remoteId: noteData.id
                    )
                    sermon.notes.append(note)
                }
            }

            if let transcriptData = remoteData.transcript {
                print("[SyncService] Creating transcript")
                let transcript = Transcript(
                    id: transcriptData.localId,
                    text: transcriptData.text,
                    segments: [],
                    remoteId: transcriptData.id
                )
                sermon.transcript = transcript
            }

            if let summaryData = remoteData.summary {
                print("[SyncService] Creating summary: \(summaryData.title)")
                let summary = Summary(
                    id: summaryData.localId,
                    title: summaryData.title,
                    text: summaryData.text,
                    type: summaryData.type,
                    status: summaryData.status,
                    remoteId: summaryData.id
                )
                sermon.summary = summary
            }

            modelContext.insert(sermon)
            try modelContext.save()
            print("[SyncService] ✅ Local sermon created and saved: \(sermon.title)")
        } catch {
            print("[SyncService] ❌ Failed to create local sermon: \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - Supabase Operations

extension SyncService {
    
    private func fetchRemoteSermons(for userId: UUID) async throws -> [RemoteSermonData] {
        // Use SupabaseService to make authenticated request to Netlify endpoint
        guard let supabaseService = self.supabaseService as? SupabaseService else {
            throw SyncError.networkError
        }
        let sermons = try await supabaseService.fetchRemoteSermons(for: userId)
        return sermons
    }
    
    private func createRemoteSermon(sermon: Sermon, data: SermonSyncData) async throws -> String {
        print("[SyncService] Creating remote sermon: \(data.title)")

        guard let supabaseService = self.supabaseService as? SupabaseService else {
            print("[SyncService] ❌ SupabaseService not available")
            throw SyncError.networkError
        }

        // Get auth token
        print("[SyncService] Getting auth session...")
        let session = try await supabaseService.client.auth.session
        let token = session.accessToken
        print("[SyncService] ✅ Got auth token")

        // Upload audio file to Supabase Storage first
        let audioFileName = data.audioFileURL.lastPathComponent
        print("[SyncService] Uploading audio file: \(audioFileName)")

        // Get file size
        let fileSize = try FileManager.default.attributesOfItem(atPath: data.audioFileURL.path)[.size] as? Int ?? 0
        print("[SyncService] File size: \(fileSize) bytes")

        let audioFileURL: URL
        let storagePath: String
        do {
            // Get signed upload URL
            print("[SyncService] Getting signed upload URL...")

            let (uploadURL, path) = try await supabaseService.getSignedUploadURL(
                for: audioFileName,
                contentType: "audio/m4a",
                fileSize: fileSize
            )
            storagePath = path
            print("[SyncService] ✅ Got upload URL: \(uploadURL)")
            print("[SyncService] ✅ Storage path: \(storagePath)")

            // Upload the file
            print("[SyncService] Uploading file to storage...")
            try await supabaseService.uploadAudioFile(at: data.audioFileURL, to: uploadURL)
            print("[SyncService] ✅ Audio file uploaded successfully")

            // Get public URL using the actual storage path
            print("[SyncService] Getting public URL for path: \(storagePath)")
            audioFileURL = try supabaseService.client.storage
                .from("sermon-audio")
                .getPublicURL(path: storagePath)
            print("[SyncService] ✅ Public URL: \(audioFileURL)")
        } catch {
            print("[SyncService] ❌ Failed to upload audio: \(error.localizedDescription)")
            throw error
        }

        // Prepare request payload (using camelCase as expected by API)
        var payload: [String: Any] = [
            "localId": data.id.uuidString,
            "title": data.title,
            "audioFilePath": storagePath, // Full storage path (e.g., "userId/filename.m4a")
            "audioFileUrl": audioFileURL.absoluteString,
            "audioFileName": audioFileName,
            "audioFileSizeBytes": fileSize,
            "duration": 0, // Default duration - iOS doesn't track this yet
            "date": ISO8601DateFormatter().string(from: data.date),
            "serviceType": data.serviceType,
            "speaker": data.speaker as Any,
            "transcriptionStatus": data.transcriptionStatus,
            "summaryStatus": data.summaryStatus,
            "isArchived": data.isArchived
        ]

        // Add notes if present
        if !sermon.notes.isEmpty {
            print("[SyncService] Including \(sermon.notes.count) notes in payload")
            let notesArray = sermon.notes.map { note in
                return [
                    "id": note.id.uuidString,
                    "text": note.text,
                    "timestamp": note.timestamp
                ]
            }
            payload["notes"] = notesArray
        }

        // Add transcript if present
        if let transcript = sermon.transcript {
            print("[SyncService] Including transcript in payload (length: \(transcript.text.count) chars)")
            payload["transcript"] = [
                "id": transcript.id.uuidString,
                "text": transcript.text,
                "segments": NSNull(), // TODO: serialize segments if needed
                "status": "complete"
            ]
        }

        // Add summary if present
        if let summary = sermon.summary {
            print("[SyncService] Including summary in payload: \(summary.title)")
            payload["summary"] = [
                "id": summary.id.uuidString,
                "title": summary.title,
                "text": summary.text,
                "type": summary.type,
                "status": summary.status
            ]
        }

        // Call Netlify function
        print("[SyncService] Calling create-sermon API...")
        print("[SyncService] Payload: \(payload)")

        let url = URL(string: "https://comfy-daffodil-7ecc55.netlify.app/.netlify/functions/create-sermon")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        // Log the actual JSON being sent
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print("[SyncService] JSON payload: \(jsonString)")
        }

        request.httpBody = jsonData

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("[SyncService] ❌ No HTTP response")
                throw SyncError.networkError
            }

            print("[SyncService] API response status: \(httpResponse.statusCode)")

            // Handle 409 Conflict (sermon already exists) - treat as success
            if httpResponse.statusCode == 409 {
                print("[SyncService] ⚠️ Sermon already exists in cloud, treating as success...")
                // Query the database to get the existing sermon's remote ID
                // For now, return empty string and let pullCloudChanges handle it
                return ""
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if let responseString = String(data: responseData, encoding: .utf8) {
                    print("[SyncService] ❌ API error response: \(responseString)")
                }
                throw SyncError.networkError
            }

            let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]

            // API returns: { "success": true, "data": { "id": "...", ... } }
            guard let data = json?["data"] as? [String: Any],
                  let sermonId = data["id"] as? String else {
                print("[SyncService] ❌ No sermon ID in response")
                if let jsonString = String(data: responseData, encoding: .utf8) {
                    print("[SyncService] Response JSON: \(jsonString)")
                }
                throw SyncError.dataCorruption
            }

            print("[SyncService] ✅ Sermon created with ID: \(sermonId)")
            return sermonId
        } catch {
            print("[SyncService] ❌ create-sermon API call failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func updateRemoteSermon(sermon: Sermon, remoteId: String, data: SermonSyncData) async throws {
        print("[SyncService] Updating remote sermon: \(data.title) (remoteId: \(remoteId))")

        guard let supabaseService = self.supabaseService as? SupabaseService else {
            throw SyncError.networkError
        }

        // Get auth token
        let session = try await supabaseService.client.auth.session
        let token = session.accessToken

        // Prepare request payload with basic sermon data
        var payload: [String: Any] = [
            "remoteId": remoteId,
            "title": data.title,
            "serviceType": data.serviceType,
            "speaker": data.speaker as Any,
            "transcriptionStatus": data.transcriptionStatus,
            "summaryStatus": data.summaryStatus,
            "isArchived": data.isArchived,
            "updatedAt": ISO8601DateFormatter().string(from: data.updatedAt)
        ]

        // Add notes if present
        if !sermon.notes.isEmpty {
            print("[SyncService] Including \(sermon.notes.count) notes in update payload")
            let notesArray = sermon.notes.map { note in
                return [
                    "id": note.id.uuidString,
                    "text": note.text,
                    "timestamp": note.timestamp
                ]
            }
            payload["notes"] = notesArray
        }

        // Add transcript if present
        if let transcript = sermon.transcript {
            print("[SyncService] Including transcript in update payload (length: \(transcript.text.count) chars)")
            payload["transcript"] = [
                "id": transcript.id.uuidString,
                "text": transcript.text,
                "segments": NSNull(),
                "status": "complete"
            ]
        }

        // Add summary if present
        if let summary = sermon.summary {
            print("[SyncService] Including summary in update payload: \(summary.title)")
            payload["summary"] = [
                "id": summary.id.uuidString,
                "title": summary.title,
                "text": summary.text,
                "type": summary.type,
                "status": summary.status
            ]
        }

        // Call Netlify function
        print("[SyncService] Calling update-sermon API...")
        let url = URL(string: "https://comfy-daffodil-7ecc55.netlify.app/.netlify/functions/update-sermon")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        // Log the actual JSON being sent
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print("[SyncService] Update JSON payload: \(jsonString)")
        }

        request.httpBody = jsonData

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[SyncService] ❌ No HTTP response from update-sermon")
            throw SyncError.networkError
        }

        print("[SyncService] Update-sermon response status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            if let responseString = String(data: responseData, encoding: .utf8) {
                print("[SyncService] ❌ Update error response: \(responseString)")
            }
            throw SyncError.networkError
        }

        print("[SyncService] ✅ Remote sermon updated successfully")
    }
    
    private func deleteAllRemoteData(for userId: UUID) async throws {
        // This would call your Netlify function to delete all user data
    }
    
    private func downloadAudioFile(from url: URL, remotePath: String? = nil) async throws -> URL {
        print("[SyncService] 📥 Downloading audio file from: \(url)")
        if let remotePath = remotePath {
            print("[SyncService] Using storage path: \(remotePath)")
        }

        guard let supabaseService = self.supabaseService as? SupabaseService else {
            print("[SyncService] ❌ SupabaseService not available")
            throw SyncError.networkError
        }

        // Extract filename from URL
        let fileName = url.lastPathComponent
        print("[SyncService] Extracted filename: \(fileName)")

        // Prepare local destination path in AudioRecordings directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioRecordingsPath = documentsPath.appendingPathComponent("AudioRecordings")
        let localURL = audioRecordingsPath.appendingPathComponent(fileName)

        print("[SyncService] Target local path: \(localURL.path)")

        do {
            // Use SupabaseService's downloadAudioFile which handles authentication and tries multiple buckets
            let downloadedURL = try await supabaseService.downloadAudioFile(
                filename: fileName,
                localURL: localURL,
                remotePath: remotePath // Use provided path if available
            )

            print("[SyncService] ✅ Audio file downloaded successfully to: \(downloadedURL.path)")
            return downloadedURL
        } catch {
            print("[SyncService] ❌ Audio download failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func syncNoteToCloud(_ note: Note, sermonId: String) async throws {
        // Sync note to cloud
    }
    
    private func syncTranscriptToCloud(_ transcript: Transcript, sermonId: String) async throws {
        // Sync transcript to cloud
    }
    
    private func syncSummaryToCloud(_ summary: Summary, sermonId: String) async throws {
        // Sync summary to cloud
    }
}

// MARK: - Data Models

struct SermonSyncData {
    let id: UUID
    let title: String
    let audioFileURL: URL
    let date: Date
    let serviceType: String
    let speaker: String?
    let transcriptionStatus: String
    let summaryStatus: String
    let isArchived: Bool
    let userId: UUID?
    let updatedAt: Date
}

struct RemoteSermonData: Codable {
    let id: String // Remote ID
    let localId: UUID
    let title: String
    let audioFileURL: URL
    let audioFilePath: String? // Storage path (e.g., "userId/filename.m4a")
    let date: Date
    let serviceType: String
    let speaker: String?
    let transcriptionStatus: String
    let summaryStatus: String
    let isArchived: Bool
    let userId: UUID
    let updatedAt: Date
    let notes: [RemoteNoteData]?
    let transcript: RemoteTranscriptData?
    let summary: RemoteSummaryData?
}

struct RemoteNoteData: Codable {
    let id: String
    let localId: UUID
    let text: String
    let timestamp: TimeInterval
    
    // Custom decoder to handle missing timestamp (defaults to 0 for manual notes)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.localId = try container.decode(UUID.self, forKey: .localId)
        self.text = try container.decode(String.self, forKey: .text)
        self.timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .timestamp) ?? 0
    }
    
    enum CodingKeys: String, CodingKey {
        case id, localId, text, timestamp
    }
}

struct RemoteTranscriptData: Codable {
    let id: String
    let localId: UUID
    let text: String
    let segments: String? // JSON string
    let status: String
}

struct RemoteSummaryData: Codable {
    let id: String
    let localId: UUID
    let title: String
    let text: String
    let type: String
    let status: String
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case subscriptionRequired
    case networkError
    case dataCorruption
    case conflictResolution
    
    var errorDescription: String? {
        switch self {
        case .subscriptionRequired:
            return "Sync requires a paid subscription"
        case .networkError:
            return "Network connection error during sync"
        case .dataCorruption:
            return "Data corruption detected during sync"
        case .conflictResolution:
            return "Unable to resolve sync conflicts"
        }
    }
}