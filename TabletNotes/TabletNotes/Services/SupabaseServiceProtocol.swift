import Foundation
import Supabase

protocol SupabaseServiceProtocol {
    var client: SupabaseClient { get }
    
    func getSignedUploadURL(for fileName: String, contentType: String, fileSize: Int) async throws -> (uploadUrl: URL, path: String)
    func getSignedUploadURL(for fileURL: URL) async throws -> (uploadUrl: URL, path: String)
    func uploadFile(data: Data, to uploadUrl: URL) async throws
    func uploadAudioFile(at localUrl: URL, to signedUploadUrl: URL) async throws
    func getSignedDownloadURL(for path: String) async throws -> URL
    func downloadAudioFile(filename: String, localURL: URL, remotePath: String?) async throws -> URL
    func fetchRemoteSermons(for userId: UUID) async throws -> [RemoteSermonData]
    func updateUserProfile(_ user: User) async throws
}
