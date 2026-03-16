import Foundation

protocol SermonSyncRemoteGatewayProtocol {
    func fetchRemoteSermons(for userId: UUID) async throws -> [RemoteSermonData]
    func createRemoteSermon(data: SermonSyncData) async throws -> String
    func updateRemoteSermon(remoteId: String, data: SermonSyncData) async throws
    func downloadAudioFile(from url: URL, remotePath: String?) async throws -> URL
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

    func createRemoteSermon(data: SermonSyncData) async throws -> String {
        print("[SyncService] Creating remote sermon: \(data.title)")

        let token = try await getAuthToken()
        let audioFileName = data.audioFileURL.lastPathComponent
        let fileSize = try FileManager.default.attributesOfItem(atPath: data.audioFileURL.path)[.size] as? Int ?? 0

        let upload = try await supabaseService.getSignedUploadURL(
            for: audioFileName,
            contentType: "audio/m4a",
            fileSize: fileSize
        )

        try await supabaseService.uploadAudioFile(at: data.audioFileURL, to: upload.uploadUrl)

        let audioFileURL = try supabaseService.client.storage
            .from("sermon-audio")
            .getPublicURL(path: upload.path)

        var payload: [String: Any] = [
            "localId": data.id.uuidString,
            "title": data.title,
            "audioFilePath": upload.path,
            "audioFileUrl": audioFileURL.absoluteString,
            "audioFileName": audioFileName,
            "audioFileSizeBytes": fileSize,
            "duration": 0,
            "date": ISO8601DateFormatter().string(from: data.date),
            "serviceType": data.serviceType,
            "speaker": data.speaker as Any,
            "transcriptionStatus": data.transcriptionStatus,
            "summaryStatus": data.summaryStatus,
            "isArchived": data.isArchived
        ]

        if !data.notes.isEmpty {
            payload["notes"] = data.notes.map { note in
                [
                    "id": note.id.uuidString,
                    "text": note.text,
                    "timestamp": note.timestamp
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
            print("[SyncService] ⚠️ Sermon already exists in cloud, treating as success...")
            return ""
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

        print("[SyncService] ✅ Sermon created with ID: \(sermonId)")
        return sermonId
    }

    func updateRemoteSermon(remoteId: String, data: SermonSyncData) async throws {
        print("[SyncService] Updating remote sermon: \(data.title) (remoteId: \(remoteId))")

        let token = try await getAuthToken()

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

        if !data.notes.isEmpty {
            payload["notes"] = data.notes.map { note in
                [
                    "id": note.id.uuidString,
                    "text": note.text,
                    "timestamp": note.timestamp
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
