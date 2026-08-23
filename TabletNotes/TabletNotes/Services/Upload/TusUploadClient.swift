import Foundation

/// Pure TUS request helpers for Supabase Storage (TAB-73 Part B).
///
/// No URLSession here — unit-testable without a network. Supabase requires a
/// fixed 6MB chunk size; the last chunk may be smaller.
enum TusUploadClient {
    static let tusVersion = "1.0.0"
    static let chunkSize: Int64 = 6 * 1024 * 1024
    static let bucketName = "sermon-audio"

    /// Success only when the server echoes an offset that covers the whole file.
    /// A nil URLSession error is not enough — 401/403/409/5xx also complete with
    /// error == nil (adversarial review B2).
    static func isUploadComplete(offset: Int64, fileLength: Int64) -> Bool {
        fileLength >= 0 && offset == fileLength
    }

    /// Offsets used for seek/range construction must be in `0...fileLength`.
    static func isValidOffset(_ offset: Int64, fileLength: Int64) -> Bool {
        fileLength >= 0 && offset >= 0 && offset <= fileLength
    }

    /// Next half-open byte range to PATCH, or nil when already complete / invalid.
    static func nextChunkRange(offset: Int64, fileLength: Int64, chunkSize: Int64 = chunkSize) -> Range<Int64>? {
        guard isValidOffset(offset, fileLength: fileLength),
              offset < fileLength,
              chunkSize > 0 else { return nil }
        let end = min(offset + chunkSize, fileLength)
        return offset..<end
    }

    /// TUS `Upload-Metadata`: comma-separated `key base64(value)` pairs.
    static func encodeUploadMetadata(
        bucketName: String = bucketName,
        objectName: String,
        contentType: String,
        cacheControl: String = "3600"
    ) -> String {
        let pairs: [(String, String)] = [
            ("bucketName", bucketName),
            ("objectName", objectName),
            ("contentType", contentType),
            ("cacheControl", cacheControl)
        ]
        return pairs.map { key, value in
            let encoded = Data(value.utf8).base64EncodedString()
            return "\(key) \(encoded)"
        }.joined(separator: ",")
    }

    static func resumableEndpoint(projectURL: URL) -> URL {
        projectURL.appendingPathComponent("storage/v1/upload/resumable")
    }

    static func makeCreateRequest(
        endpoint: URL,
        fileLength: Int64,
        objectPath: String,
        contentType: String,
        accessToken: String,
        anonKey: String,
        upsert: Bool
    ) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        applyCommonHeaders(&request, accessToken: accessToken, anonKey: anonKey)
        request.setValue(String(fileLength), forHTTPHeaderField: "Upload-Length")
        request.setValue(
            encodeUploadMetadata(objectName: objectPath, contentType: contentType),
            forHTTPHeaderField: "Upload-Metadata"
        )
        if upsert {
            request.setValue("true", forHTTPHeaderField: "x-upsert")
        }
        return request
    }

    static func makeHeadRequest(
        uploadURL: URL,
        accessToken: String,
        anonKey: String
    ) -> URLRequest {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "HEAD"
        applyCommonHeaders(&request, accessToken: accessToken, anonKey: anonKey)
        return request
    }

    static func makePatchRequest(
        uploadURL: URL,
        offset: Int64,
        contentLength: Int64,
        accessToken: String,
        anonKey: String
    ) -> URLRequest {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PATCH"
        applyCommonHeaders(&request, accessToken: accessToken, anonKey: anonKey)
        request.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(contentLength), forHTTPHeaderField: "Content-Length")
        return request
    }

    static func parseUploadOffset(from response: HTTPURLResponse) -> Int64? {
        guard let raw = response.value(forHTTPHeaderField: "Upload-Offset")
                ?? response.value(forHTTPHeaderField: "upload-offset") else {
            return nil
        }
        return Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Absolute Location, or relative resolved against `endpoint`.
    static func parseLocation(from response: HTTPURLResponse, endpoint: URL) -> URL? {
        guard let raw = response.value(forHTTPHeaderField: "Location")
                ?? response.value(forHTTPHeaderField: "location"),
              !raw.isEmpty else {
            return nil
        }
        let resolved: URL?
        if let absolute = URL(string: raw), absolute.scheme != nil {
            resolved = absolute
        } else {
            resolved = URL(string: raw, relativeTo: endpoint)?.absoluteURL
        }
        guard let location = resolved,
              isTrustedUploadLocation(location, endpoint: endpoint) else {
            return nil
        }
        return location
    }

    /// Reject attacker-controlled absolute Locations before attaching bearer tokens.
    static func isTrustedUploadLocation(_ location: URL, endpoint: URL) -> Bool {
        guard location.scheme?.lowercased() == "https",
              let locationHost = location.host?.lowercased(),
              let endpointHost = endpoint.host?.lowercased(),
              locationHost == endpointHost else {
            return false
        }
        let locationPort = location.port ?? 443
        let endpointPort = endpoint.port ?? 443
        guard locationPort == endpointPort else { return false }
        let path = location.path
        if path == "/storage/v1/upload/resumable" {
            return true
        }
        let prefix = "/storage/v1/upload/resumable/"
        guard path.hasPrefix(prefix) else { return false }
        let remainder = path.dropFirst(prefix.count)
        guard !remainder.isEmpty, !remainder.contains("/") else { return false }
        return remainder.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0) }
    }

    /// HEAD 404/410 → discard resume and restart. Offset outside `0...fileLength` → same.
    static func shouldRestartResume(httpStatus: Int, offset: Int64?, fileLength: Int64) -> Bool {
        if httpStatus == 404 || httpStatus == 410 { return true }
        if let offset, !isValidOffset(offset, fileLength: fileLength) { return true }
        return false
    }

    private static func applyCommonHeaders(
        _ request: inout URLRequest,
        accessToken: String,
        anonKey: String
    ) {
        request.setValue(tusVersion, forHTTPHeaderField: "Tus-Resumable")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
    }
}
