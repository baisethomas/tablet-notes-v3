import Foundation

/// Coordinates URLSession PATCH completion vs. the awaiting coroutine.
///
/// Handles two races Ternary/Codex flagged:
/// 1. Delegate completion before the waiter is registered → stash in `early`.
/// 2. Timeout must resume the stored continuation (not rely on cancelling an
///    unresumed CheckedContinuation inside a task group).
@MainActor
final class PatchCompletionGate {
    private struct Waiter {
        let continuation: CheckedContinuation<HTTPURLResponse, Error>
        let timeoutTask: Task<Void, Never>
    }

    private var waiters: [Int: Waiter] = [:]
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

            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard !Task.isCancelled else { return }
                if let waiter = self.waiters.removeValue(forKey: taskId) {
                    self.timedOutIds.insert(taskId)
                    waiter.continuation.resume(throwing: timedOutError)
                }
            }
            waiters[taskId] = Waiter(continuation: cont, timeoutTask: timeoutTask)
            beforeWaiting?()
        }
    }

    func finish(taskId: Int, result: Result<HTTPURLResponse, Error>) {
        if timedOutIds.remove(taskId) != nil {
            return
        }
        if let waiter = waiters.removeValue(forKey: taskId) {
            waiter.timeoutTask.cancel()
            switch result {
            case .success(let response):
                waiter.continuation.resume(returning: response)
            case .failure(let error):
                waiter.continuation.resume(throwing: error)
            }
            return
        }
        earlyResults[taskId] = result
    }
}
