import Foundation
import Supabase

protocol SupabaseServiceProtocol {
    var client: SupabaseClient { get }
    
    func getSignedUploadURL(for fileName: String) async throws -> (uploadUrl: URL, path: String)
    func uploadFile(data: Data, to uploadUrl: URL) async throws
    func getSignedDownloadURL(for path: String) async throws -> URL
    func updateUserProfile(_ user: User) async throws
}