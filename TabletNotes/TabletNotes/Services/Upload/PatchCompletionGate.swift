import Foundation

/// Coordinates URLSession PATCH completion vs. the awaiting coroutine.
///
/// Handles races Ternary/Codex flagged:
/// 1. Delegate completion before the waiter is registered → stash in `early`.
/// 2. Timeout must resume the stored continuation (not rely on cancelling an
///    unresumed CheckedContinuation inside a task group).
/// 3. Only one of `finish` or the timeout task may resume a waiter — enforced
///    via per-wait generation tokens and atomic `removeValue`.
@MainActor
final class PatchCompletionGate {
    private struct Waiter {
        let generation: UInt64
        let continuation: CheckedContinuation<HTTPURLResponse, Error>
        let timeoutTask: Task<Void, Never>
    }

    private var waiters: [Int: Waiter] = [:]
    private var earlyResults: [Int: Result<HTTPURLResponse, Error>] = [:]
    private var timedOutIds: Set<Int> = []
    private var nextGeneration: UInt64 = 0

    func wait(
        taskId: Int,
        timeoutNanoseconds: UInt64,
        timedOutError: Error,
        beforeWaiting: (() -> Void)? = nil
    ) async throws -> HTTPURLResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HTTPURLResponse, Error>) in
                timedOutIds.remove(taskId)

                if waiters[taskId] != nil {
                    cont.resume(throwing: UploadManagerError.duplicatePatchWait)
                    return
                }

                if let early = earlyResults.removeValue(forKey: taskId) {
                    switch early {
                    case .success(let response):
                        cont.resume(returning: response)
                    case .failure(let error):
                        cont.resume(throwing: error)
                    }
                    return
                }

                let generation = nextGeneration
                nextGeneration &+= 1
                let timeoutTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    guard !Task.isCancelled else { return }
                    guard self.waiters[taskId]?.generation == generation else { return }
                    if let waiter = self.waiters.removeValue(forKey: taskId),
                       waiter.generation == generation {
                        self.timedOutIds.insert(taskId)
                        waiter.continuation.resume(throwing: timedOutError)
                    }
                }
                waiters[taskId] = Waiter(
                    generation: generation,
                    continuation: cont,
                    timeoutTask: timeoutTask
                )
                beforeWaiting?()
            }
        } onCancel: {
            Task { @MainActor in
                self.cancelWaiter(taskId: taskId)
            }
        }
    }

    private func cancelWaiter(taskId: Int) {
        if let waiter = waiters.removeValue(forKey: taskId) {
            waiter.timeoutTask.cancel()
            waiter.continuation.resume(throwing: CancellationError())
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
