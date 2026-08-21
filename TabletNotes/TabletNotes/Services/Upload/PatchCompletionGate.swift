import Foundation

/// Coordinates URLSession PATCH completion vs. the awaiting coroutine.
///
/// Handles two races Ternary/Codex flagged:
/// 1. Delegate completion before the waiter is registered → stash in `early`.
/// 2. Timeout must resume the stored continuation (not rely on cancelling an
///    unresumed CheckedContinuation inside a task group).
@MainActor
final class PatchCompletionGate {
    private var continuations: [Int: CheckedContinuation<HTTPURLResponse, Error>] = [:]
    private var earlyResults: [Int: Result<HTTPURLResponse, Error>] = [:]
    private var timedOutIds: Set<Int> = []

    func wait(
        taskId: Int,
        timeoutNanoseconds: UInt64,
        timedOutError: Error,
        beforeWaiting: (() -> Void)? = nil
    ) async throws -> HTTPURLResponse {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HTTPURLResponse, Error>) in
            if let early = earlyResults.removeValue(forKey: taskId) {
                switch early {
                case .success(let response):
                    cont.resume(returning: response)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
                return
            }

            continuations[taskId] = cont
            beforeWaiting?()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                if let waiting = self.continuations.removeValue(forKey: taskId) {
                    self.timedOutIds.insert(taskId)
                    waiting.resume(throwing: timedOutError)
                }
            }
        }
    }

    func finish(taskId: Int, result: Result<HTTPURLResponse, Error>) {
        if timedOutIds.remove(taskId) != nil {
            return
        }
        if let cont = continuations.removeValue(forKey: taskId) {
            switch result {
            case .success(let response):
                cont.resume(returning: response)
            case .failure(let error):
                cont.resume(throwing: error)
            }
            return
        }
        earlyResults[taskId] = result
    }
}
