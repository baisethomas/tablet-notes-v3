import Foundation

protocol SermonSyncRemoteGatewayProtocol {
    func fetchRemoteSermons(for userId: UUID) async throws -> [RemoteSermonData]
    func createRemoteSermon(data: SermonSyncData) async throws -> RemoteSermonCreateResult
    func updateRemoteSermon(remoteId: String, data: SermonSyncData) async throws
    func downloadAudioFile(from url: URL, remotePath: String?) async throws -> URL
    func deleteRemoteSermon(remoteId: String) async throws
    func deleteAllRemoteData(for userId: UUID) async throws
}

final class SermonSyncRemoteGateway: SermonSyncRemoteGatewayProtocol {
    private let supabaseService: SupabaseServiceProtocol
    private let apiBaseURL = "https://comfy-daffodil-7ecc55.netlify.app"

    init(supabaseService: SupabaseServiceProtocol) {
        self.supabaseService = supabaseService
    }

    func fetchRemoteSermons(for userId: UUID) async throws -> [RemoteSermonData] {
        try await supabaseService.fetchRemoteSermons(for: userId)
    }

    /// Builds the create-sermon request body. Extracted so a test can execute
    /// it (TAB-95): the payload must carry the snapshot's `updatedAt` — the
    /// server honors it (`create-sermon.js` falls back to server time only
    /// when absent), and without it the row is stamped at POST-completion,
    /// *after* the whole audio upload, so the next pull sees a "newer" row
    /// carrying the pre-completion statuses and walks local state backwards.
    static func createSermonPayload(
        data: SermonSyncData,
        audioFilePath: String,
        audioFileUrl: String,
        audioFileName: String,
        fileSize: Int
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "localId": data.id.uuidString,
            "title": data.title,
            "audioFilePath": audioFilePath,
            "audioFileUrl": audioFileUrl,
            "audioFileName": audioFileName,
            "audioFileSizeBytes": fileSize,
            "duration": 0,
            "date": ISO8601DateFormatter().string(from: data.date),
            "serviceType": data.serviceType,
            "speaker": data.speaker as Any,
            "transcriptionStatus": data.transcriptionStatus,
            "summaryStatus": data.summaryStatus,
            "isArchived": data.isArchived,
            "updatedAt": ISO8601DateFormatter().string(from: data.updatedAt)
        ]

        if let notes = data.notes, !notes.isEmpty {
            payload["notes"] = notes.map { note in
                [
                    "id": note.id.uuidString,
                    "text": note.text,
                    // The backend notes.timestamp column is an integer;
                    // fractional seconds fail the whole note insert (TAB-56).
                    "timestamp": Int(note.timestamp.rounded())
                ]
            }
        }

        if let transcript = data.transcript {
            payload["transcript"] = [
                "id": transcript.id.uuidString,
                "text": transcript.text,
                "segments": NSNull(),
                "status": "complete"
            ]
        }

        if let summary = data.summary {
            payload["summary"] = [
                "id": summary.id.uuidString,
                "title": summary.title,
                "text": summary.text,
                "type": summary.type,
                "status": summary.status
            ]
        }

        return payload
    }

    func createRemoteSermon(data: SermonSyncData) async throws -> RemoteSermonCreateResult {
        print("[SyncService] Creating remote sermon: \(data.title)")

        let token = try await getAuthToken()
        let audioFileName = data.audioFileURL.lastPathComponent
        let fileSize = try FileManager.default.attributesOfItem(atPath: data.audioFileURL.path)[.size] as? Int ?? 0

        // Passing the sermon's local id gives this upload a stable object path,
        // so a retry replaces its own partial rather than orphaning a ~100MB
        // object nothing reaps (TAB-73).
        let upload = try await supabaseService.getSignedUploadURL(
            for: audioFileName,
            contentType: "audio/m4a",
            fileSize: fileSize,
            sermonLocalId: data.id
        )

        try await supabaseService.uploadAudioFile(at: data.audioFileURL, to: upload.uploadUrl, upsert: upload.upsert)

        let audioFileURL = try supabaseService.client.storage
            .from("sermon-audio")
            .getPublicURL(path: upload.path)

        let payload = Self.createSermonPayload(
            data: data,
            audioFilePath: upload.path,
            audioFileUrl: audioFileURL.absoluteString,
            audioFileName: audioFileName,
            fileSize: fileSize
        )

        let url = URL(string: "\(apiBaseURL)/.netlify/functions/create-sermon")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = jsonData

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.networkError
        }

        if httpResponse.statusCode == 409 {
            print("[SyncService] ⚠️ Sermon already exists in cloud")
            throw SyncError.remoteAlreadyExists
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let responseString = String(data: responseData, encoding: .utf8) {
                print("[SyncService] ❌ API error response: \(responseString)")
            }
            throw SyncError.networkError
        }

        let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        guard let data = json?["data"] as? [String: Any],
              let sermonId = data["id"] as? String else {
            throw SyncError.dataCorruption
        }

        let syncedScopes = parseSyncedScopes(data["syncedScopes"])
        if syncedScopes != .all {
            print("[SyncService] ⚠️ Sermon created with partial child inserts: \(sermonId)")
        } else {
            print("[SyncService] ✅ Sermon created with ID: \(sermonId)")
        }

        return RemoteSermonCreateResult(remoteId: sermonId, syncedScopes: syncedScopes)
    }

    /// Older backend deployments omit syncedScopes — treat as fully synced,
    /// which matches the previous clear-everything behavior.
    private func parseSyncedScopes(_ value: Any?) -> SermonSyncScopes {
        guard let dict = value as? [String: Any] else { return .all }
        return SermonSyncScopes(
            metadata: dict["metadata"] as? Bool ?? true,
            notes: dict["notes"] as? Bool ?? true,
            transcript: dict["transcript"] as? Bool ?? true,
            summary: dict["summary"] as? Bool ?? true
        )
    }

    func updateRemoteSermon(remoteId: String, data: SermonSyncData) async throws {
        print("[SyncService] Updating remote sermon: \(data.title) (remoteId: \(remoteId))")

        let token = try await getAuthToken()

        var payload: [String: Any] = [
            "remoteId": remoteId,
            "updatedAt": ISO8601DateFormatter().string(from: data.updatedAt)
        ]

        if data.scopes.metadata {
            payload["title"] = data.title
            payload["date"] = ISO8601DateFormatter().string(from: data.date)
            payload["serviceType"] = data.serviceType
            payload["speaker"] = data.speaker as Any
            payload["audioFileName"] = data.audioFileURL.lastPathComponent
            payload["transcriptionStatus"] = data.transcriptionStatus
            payload["summaryStatus"] = data.summaryStatus
            payload["isArchived"] = data.isArchived
        }

        if let notes = data.notes {
            payload["notes"] = notes.map { note in
                [
                    "id": note.id.uuidString,
                    "text": note.text,
                    // The backend notes.timestamp column is an integer;
                    // fractional seconds fail the whole note insert (TAB-56).
                    "timestamp": Int(note.timestamp.rounded())
                ]
            }
        }

        if let transcript = data.transcript {
            payload["transcript"] = [
                "id": transcript.id.uuidString,
                "text": transcript.text,
                "segments": NSNull(),
                "status": "complete"
            ]
        }

        if let summary = data.summary {
            payload["summary"] = [
                "id": summary.id.uuidString,
                "title": summary.title,
                "text": summary.text,
                "type": summary.type,
                "status": summary.status
            ]
        }

        let url = URL(string: "\(apiBaseURL)/.netlify/functions/update-sermon")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.networkError
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let responseString = String(data: responseData, encoding: .utf8) {
                print("[SyncService] ❌ Update error response: \(responseString)")
            }
            throw SyncError.networkError
        }
    }

    func downloadAudioFile(from url: URL, remotePath: String? = nil) async throws -> URL {
        let fileName = url.lastPathComponent
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioRecordingsPath = documentsPath.appendingPathComponent("AudioRecordings")
        let localURL = audioRecordingsPath.appendingPathComponent(fileName)

        return try await supabaseService.downloadAudioFile(
            filename: fileName,
            localURL: localURL,
            remotePath: remotePath
        )
    }

    func deleteRemoteSermon(remoteId: String) async throws {
        print("[SyncService] Deleting remote sermon: \(remoteId)")

        let token = try await getAuthToken()

        var components = URLComponents(string: "\(apiBaseURL)/.netlify/functions/delete-sermon")!
        components.queryItems = [URLQueryItem(name: "sermonId", value: remoteId)]

        guard let url = components.url else {
            throw SyncError.networkError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.networkError
        }

        // Already gone remotely — safe to proceed with the local delete.
        if httpResponse.statusCode == 404 {
            print("[SyncService] ⚠️ Remote sermon \(remoteId) not found, treating as deleted")
            return
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let responseString = String(data: responseData, encoding: .utf8) {
                print("[SyncService] ❌ Delete error response: \(responseString)")
            }
            throw SyncError.networkError
        }

        print("[SyncService] ✅ Remote sermon deleted: \(remoteId)")
    }

    func deleteAllRemoteData(for userId: UUID) async throws {
        _ = userId
    }

    private func getAuthToken() async throws -> String {
        do {
            let session = try await supabaseService.client.auth.session
            return session.accessToken
        } catch {
            print("[SyncService] Session expired, attempting refresh...")
            do {
                let refreshedSession = try await supabaseService.client.auth.refreshSession()
                print("[SyncService] Token refreshed successfully")
                return refreshedSession.accessToken
            } catch {
                print("[SyncService] Token refresh failed: \(error.localizedDescription)")
                throw SyncError.authenticationFailed
            }
        }
    }
}
