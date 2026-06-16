import Foundation
import Supabase

/// Server-verified subscription state returned by `verify-purchase`. The tier
/// is derived by the backend from an Apple-verified transaction, so it is
/// authoritative — the client adopts these values rather than its own claims.
struct SubscriptionVerificationData: Decodable {
    let subscriptionTier: String
    let subscriptionStatus: String
    let subscriptionProductId: String?
    let subscriptionPurchaseDate: String?
    let subscriptionExpiry: String?
    let subscriptionRenewalDate: String?
}

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
    /// Sends a StoreKit signed transaction to the backend for Apple verification
    /// and returns the persisted, server-derived entitlement.
    func verifyPurchase(signedTransaction: String) async throws -> SubscriptionVerificationData
}
