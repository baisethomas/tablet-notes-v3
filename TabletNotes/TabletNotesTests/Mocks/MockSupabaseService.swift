import Foundation
import Supabase
@testable import TabletNotes

enum MockSupabaseError: LocalizedError, Equatable {
    case authenticationRequired
    case networkError
    case signedURLFailed
    case uploadFailed
    case downloadURLFailed
    case updateFailed
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Authentication required"
        case .networkError:
            return "Network error"
        case .signedURLFailed:
            return "Failed to generate signed URL"
        case .uploadFailed:
            return "File upload failed"
        case .downloadURLFailed:
            return "Failed to generate download URL"
        case .updateFailed:
            return "Profile update failed"
        case .fileNotFound:
            return "File not found"
        }
    }
}

final class MockSupabaseService: SupabaseServiceProtocol {
    private enum Constants {
        static let baseURL = "https://mock-supabase.local"
        static let defaultPathPrefix = "mock-user"
    }

    private var pendingError: MockSupabaseError?
    private var uploadPathsByURL: [URL: String] = [:]
    private var storedFiles: [String: Data] = [:]
    private var storedUsers: [UUID: TabletNotes.User] = [:]
    private var remoteSermons: [RemoteSermonData] = []

    var client: SupabaseClient {
        fatalError("MockSupabaseService.client is not implemented for tests")
    }

    func setShouldFailNextCall(_ error: MockSupabaseError) {
        pendingError = error
    }

    func clearMockData() {
        pendingError = nil
        uploadPathsByURL.removeAll()
        storedFiles.removeAll()
        storedUsers.removeAll()
        remoteSermons.removeAll()
    }

    func seedFile(data: Data, at path: String) {
        storedFiles[path] = data
    }

    func storedFile(at path: String) -> Data? {
        storedFiles[path]
    }

    func seedUser(_ user: TabletNotes.User) {
        storedUsers[user.id] = user
    }

    func storedUser(id: UUID) -> TabletNotes.User? {
        storedUsers[id]
    }

    func seedRemoteSermons(_ sermons: [RemoteSermonData]) {
        remoteSermons = sermons
    }

    func getSignedUploadURL(for fileName: String, contentType: String, fileSize: Int) async throws -> (uploadUrl: URL, path: String) {
        _ = contentType
        _ = fileSize
        try throwIfNeeded(for: [.authenticationRequired, .networkError, .signedURLFailed])

        let path = "\(Constants.defaultPathPrefix)/\(fileName)"
        let uploadURL = URL(string: "\(Constants.baseURL)/upload/\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)")!
        uploadPathsByURL[uploadURL] = path
        return (uploadURL, path)
    }

    func getSignedUploadURL(for fileURL: URL) async throws -> (uploadUrl: URL, path: String) {
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let contentType = fileURL.pathExtension.lowercased() == "m4a" ? "audio/m4a" : "application/octet-stream"
        return try await getSignedUploadURL(for: fileURL.lastPathComponent, contentType: contentType, fileSize: fileSize)
    }

    func uploadFile(data: Data, to uploadUrl: URL) async throws {
        try throwIfNeeded(for: [.authenticationRequired, .networkError, .uploadFailed])

        guard let path = uploadPathsByURL[uploadUrl] ?? storagePath(from: uploadUrl) else {
            throw MockSupabaseError.uploadFailed
        }

        storedFiles[path] = data
    }

    func uploadAudioFile(at localUrl: URL, to signedUploadUrl: URL) async throws {
        let data = try Data(contentsOf: localUrl)
        try await uploadFile(data: data, to: signedUploadUrl)
    }

    func getSignedDownloadURL(for path: String) async throws -> URL {
        try throwIfNeeded(for: [.authenticationRequired, .networkError, .downloadURLFailed])

        guard storedFiles[path] != nil else {
            throw MockSupabaseError.fileNotFound
        }

        return URL(string: "\(Constants.baseURL)/download/\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)")!
    }

    func downloadAudioFile(filename: String, localURL: URL, remotePath: String? = nil) async throws -> URL {
        try throwIfNeeded(for: [.authenticationRequired, .networkError, .downloadURLFailed])

        let path = remotePath ?? "\(Constants.defaultPathPrefix)/\(filename)"
        guard let data = storedFiles[path] else {
            throw MockSupabaseError.fileNotFound
        }

        try FileManager.default.createDirectory(
            at: localURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: localURL)
        return localURL
    }

    func fetchRemoteSermons(for userId: UUID) async throws -> [RemoteSermonData] {
        try throwIfNeeded(for: [.authenticationRequired, .networkError])
        return remoteSermons.filter { $0.userId == userId }
    }

    func updateUserProfile(_ user: TabletNotes.User) async throws {
        try throwIfNeeded(for: [.authenticationRequired, .networkError, .updateFailed])
        storedUsers[user.id] = user
    }

    private func throwIfNeeded(for supportedErrors: [MockSupabaseError]) throws {
        guard let pendingError else { return }
        self.pendingError = nil

        if supportedErrors.contains(pendingError) {
            throw pendingError
        }

        throw MockSupabaseError.networkError
    }

    private func storagePath(from uploadUrl: URL) -> String? {
        let pathComponents = uploadUrl.pathComponents
        guard let markerIndex = pathComponents.firstIndex(of: "upload"), markerIndex + 1 < pathComponents.count else {
            return nil
        }

        return pathComponents[(markerIndex + 1)...].joined(separator: "/")
    }
}
