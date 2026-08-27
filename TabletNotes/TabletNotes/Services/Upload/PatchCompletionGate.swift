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

    private static let maxEarlyResults = 64

    private var waiters: [Int: Waiter] = [:]
    private var earlyResults: [Int: Result<HTTPURLResponse, Error>] = [:]
    /// FIFO order for bounded eviction of unconsumed early completions.
    private var earlyResultOrder: [Int] = []
    private var timedOutIds: Set<Int> = []
    private var cancelledIds: Set<Int> = []
    private var nextGeneration: UInt64 = 0

    /// Test seam — count of stashed early completions.
    internal var earlyResultsCountForTesting: Int { earlyResults.count }

    func wait(
        taskId: Int,
        timeoutNanoseconds: UInt64,
        timedOutError: Error,
        beforeWaiting: (() -> Void)? = nil
    ) async throws -> HTTPURLResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HTTPURLResponse, Error>) in
                timedOutIds.remove(taskId)
                cancelledIds.remove(taskId)

                if waiters[taskId] != nil {
                    cont.resume(throwing: UploadManagerError.duplicatePatchWait)
                    return
                }

                if let early = earlyResults.removeValue(forKey: taskId) {
                    earlyResultOrder.removeAll { $0 == taskId }
                    // Still run the callback — callers use it to resume URLSession
                    // tasks / signal adoption, and early completion must not skip it.
                    beforeWaiting?()
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

    func cancelWait(taskId: Int) {
        cancelWaiter(taskId: taskId)
    }

    private func cancelWaiter(taskId: Int) {
        cancelledIds.insert(taskId)
        if let waiter = waiters.removeValue(forKey: taskId) {
            waiter.timeoutTask.cancel()
            waiter.continuation.resume(throwing: CancellationError())
        }
    }

    func finish(taskId: Int, result: Result<HTTPURLResponse, Error>) {
        if timedOutIds.remove(taskId) != nil {
            return
        }
        if cancelledIds.remove(taskId) != nil {
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
        stashEarlyResult(taskId: taskId, result: result)
    }

    private func stashEarlyResult(taskId: Int, result: Result<HTTPURLResponse, Error>) {
        if earlyResults[taskId] != nil {
            earlyResults[taskId] = result
            return
        }
        while earlyResultOrder.count >= Self.maxEarlyResults, let oldest = earlyResultOrder.first {
            earlyResultOrder.removeFirst()
            earlyResults.removeValue(forKey: oldest)
        }
        earlyResultOrder.append(taskId)
        earlyResults[taskId] = result
    }
}
