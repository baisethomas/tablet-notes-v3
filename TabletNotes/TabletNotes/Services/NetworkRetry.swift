import Foundation

/// Retry utility with exponential backoff for network requests
/// Follows best practices from swift-networking skill
enum NetworkRetry {
    /// Executes an async operation with retry logic and exponential backoff
    /// - Parameters:
    ///   - maxAttempts: Maximum number of retry attempts (default: 3)
    ///   - baseDelay: Base delay in seconds for exponential backoff (default: 1.0)
    ///   - maxDelay: Maximum delay in seconds between retries (default: 60.0)
    ///   - operation: The async operation to retry
    /// - Returns: Result of the operation
    /// - Throws: The last error encountered if all retries fail
    static func withExponentialBackoff<T>(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?

        while attempt < maxAttempts {
            // Check if network is available before attempting
            if !NetworkMonitor.shared.isConnected {
                print("[NetworkRetry] Network unavailable, waiting...")
                try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                continue
            }

            do {
                let result = try await operation()
                if attempt > 0 {
                    print("[NetworkRetry] ✅ Succeeded on attempt \(attempt + 1)")
                }
                return result
            } catch {
                lastError = error
                attempt += 1

                // Check if error is retryable
                guard isRetryableError(error) else {
                    print("[NetworkRetry] Non-retryable error: \(error)")
                    throw error
                }

                if attempt < maxAttempts {
                    // Calculate exponential backoff delay with jitter
                    let exponentialDelay = min(baseDelay * pow(2.0, Double(attempt - 1)), maxDelay)
                    let jitter = Double.random(in: 0...0.1) * exponentialDelay
                    let delay = exponentialDelay + jitter

                    print("[NetworkRetry] Attempt \(attempt) failed: \(error). Retrying in \(String(format: "%.2f", delay))s...")

                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    print("[NetworkRetry] All \(maxAttempts) attempts failed")
                }
            }
        }

        throw lastError ?? NetworkError.maxRetriesExceeded
    }

    /// Determines if an error is retryable (network-related)
    private static func isRetryableError(_ error: Error) -> Bool {
        let nsError = error as NSError

        // URLError codes that are retryable
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorCallIsActive,
                 NSURLErrorDataNotAllowed:
                return true
            default:
                return false
            }
        }

        // POSIX errors that are retryable
        if nsError.domain == NSPOSIXErrorDomain {
            switch nsError.code {
            case 50,  // Network down
                 54,  // Connection reset
                 60,  // Timeout
                 65:  // Host unreachable
                return true
            default:
                return false
            }
        }

        return false
    }
}

enum NetworkError: Error {
    case maxRetriesExceeded
    case networkUnavailable
}
