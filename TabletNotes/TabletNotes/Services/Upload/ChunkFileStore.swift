import Foundation

/// Off-main-actor disk I/O for TUS chunk bodies (TAB-73 review).
///
/// `UploadManager` is `@MainActor`, and a chunk can be ~6 MB: reading it into
/// memory and writing it atomically on the main thread stalls the UI for the
/// duration of the I/O — hundreds of milliseconds on a slow device. This
/// actor runs on the global concurrent executor, so callers `await` the I/O
/// without ever blocking the main thread. It holds no state; the actor exists
/// purely to move execution off the main actor.
actor ChunkFileStore {
    static let shared = ChunkFileStore()

    /// Copies `range` of `file` into a fresh uniquely-named chunk file inside
    /// `directory` and returns its URL.
    func writeChunk(from file: URL, range: Range<Int64>, into directory: URL) throws -> URL {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(range.lowerBound))
        let count = Int(range.upperBound - range.lowerBound)
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw UploadManagerError.fileMissing
        }
        let chunkURL = directory.appendingPathComponent("tus-chunk-\(UUID().uuidString)")
        try data.write(to: chunkURL, options: .atomic)
        return chunkURL
    }

    /// Best-effort removal; missing files are fine (cleanup is idempotent and
    /// the orphan sweep catches stragglers).
    func remove(paths: [String]) {
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Deletes every `prefix`-named file in `directories` except the
    /// protected paths (chunks a live background task may still read).
    func sweep(directories: [URL], protectedPaths: Set<String>, prefix: String) {
        for dir in directories {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ) else { continue }
            for url in entries where url.lastPathComponent.hasPrefix(prefix) {
                guard !protectedPaths.contains(url.path) else { continue }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
