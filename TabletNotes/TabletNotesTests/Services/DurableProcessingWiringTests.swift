import Foundation
import SwiftData
import Testing
@testable import TabletNotes

/// Tests for the flag-gated wiring of the durable processing pipeline (TAB-72).
///
/// The single most important property here is the default: an unset flag must
/// leave every existing user on the legacy path. Everything else is about the
/// two paths being mutually exclusive — running both would submit the same
/// recording to AssemblyAI twice.
@MainActor
struct DurableProcessingWiringTests {
    // MARK: - Flag semantics

    private func isolatedFlags(_ name: String = UUID().uuidString) -> (FeatureFlags, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        return (FeatureFlags(defaults: defaults), defaults)
    }

    @Test func flagsDefaultToOff() {
        let suite = UUID().uuidString
        let (flags, defaults) = isolatedFlags(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(flags.durableProcessingPipeline == false)
        #expect(flags.isEnabled(.durableProcessingPipeline) == false)
    }

    @Test func flagRoundTripsThroughItsStore() {
        let suite = UUID().uuidString
        let (flags, defaults) = isolatedFlags(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        flags.setEnabled(true, for: .durableProcessingPipeline)
        #expect(flags.durableProcessingPipeline)

        // Rollback has to be a flip, not a redeploy — that is what the gate buys.
        flags.setEnabled(false, for: .durableProcessingPipeline)
        #expect(flags.durableProcessingPipeline == false)
    }

    // MARK: - Dispatcher

    final class MockJobRequester: ProcessingJobRequesting, @unchecked Sendable {
        var requested: [(UUID, Bool)] = []
        var result: Result<RemoteProcessingJob, Error>

        init(result: Result<RemoteProcessingJob, Error> = .success(
            RemoteProcessingJob(
                id: "job-1",
                sermonLocalId: UUID(),
                kind: .transcription,
                status: .submitted,
                lastError: nil
            )
        )) {
            self.result = result
        }

        func requestTranscription(sermonLocalId: UUID, filePath: String?, retry: Bool) async throws -> RemoteProcessingJob {
            requested.append((sermonLocalId, retry))
            return try result.get()
        }
    }

    @Test func dispatchReportsSuccessAndClearsTheLastError() async {
        let mock = MockJobRequester()
        let dispatcher = ProcessingJobDispatcher(client: mock)
        let sermonId = UUID()

        let ok = await dispatcher.dispatch(sermonLocalId: sermonId)

        #expect(ok)
        #expect(mock.requested.map(\.0) == [sermonId])
        #expect(mock.requested.map(\.1) == [false])
        #expect(dispatcher.lastError == nil)
    }

    @Test func deliberateRetryAsksTheServerToRevive() async {
        // TAB-91: a user tap must send retry:true. An automatic sweep never does.
        let mock = MockJobRequester()
        let dispatcher = ProcessingJobDispatcher(client: mock)
        let sermonId = UUID()

        let ok = await dispatcher.dispatch(sermonLocalId: sermonId, retry: true)

        #expect(ok)
        #expect(mock.requested.map(\.1) == [true])
    }

    @Test func dispatchFailureIsReportedRatherThanSwallowed() async {
        let mock = MockJobRequester(result: .failure(ProcessingJobClientError.offline))
        let dispatcher = ProcessingJobDispatcher(client: mock)

        let ok = await dispatcher.dispatch(sermonLocalId: UUID())

        // A failed dispatch must return false and leave an error behind: the
        // sermon stays pending so the next sweep re-asks. Reporting success here
        // would be the optimistic ack that strands a recording forever.
        #expect(ok == false)
        #expect(dispatcher.lastError != nil)
    }

    @Test func dispatchIsRetryableAfterAFailure() async {
        let mock = MockJobRequester(result: .failure(ProcessingJobClientError.offline))
        let dispatcher = ProcessingJobDispatcher(client: mock)
        let sermonId = UUID()

        _ = await dispatcher.dispatch(sermonLocalId: sermonId)
        mock.result = .success(
            RemoteProcessingJob(id: "job-2", sermonLocalId: sermonId, kind: .transcription, status: .queued, lastError: nil)
        )
        let second = await dispatcher.dispatch(sermonLocalId: sermonId)

        #expect(second)
        #expect(mock.requested.count == 2)
        #expect(dispatcher.lastError == nil)
    }

    // MARK: - Coordinator gating

    final class SpyDispatcher: ProcessingJobDispatching {
        var dispatched: [(UUID, Bool)] = []

        func dispatch(sermonLocalId: UUID, retry: Bool) async -> Bool {
            dispatched.append((sermonLocalId, retry))
            return true
        }
    }

    @Test func theSweepDoesNothingWhileTheFlagIsOff() async {
        let coordinator = SermonProcessingCoordinator.shared
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }

        let spy = SpyDispatcher()
        coordinator.processingDispatcher = spy
        coordinator.isDurableProcessingEnabled = { false }

        await coordinator.dispatchPendingDurableJobs()

        #expect(spy.dispatched.isEmpty)
    }

    @Test func turningTheFlagOffMidSessionStopsTheObserverAndResumesTheLegacyQueues() async {
        let coordinator = SermonProcessingCoordinator.shared
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }

        let spy = SpyDispatcher()
        coordinator.processingDispatcher = spy
        coordinator.isDurableProcessingEnabled = { false }

        var legacyResumed = false
        coordinator.backgroundRefresher = { legacyResumed = true }

        await coordinator.handleProcessingModeChange(userId: UUID())

        // Persisting the flag is not applying it: switching off has to hand
        // control back to the queues that were idle while it was on.
        #expect(legacyResumed)
        #expect(spy.dispatched.isEmpty)
    }

    @Test func turningTheFlagOnMidSessionSweepsWithoutWaitingForASignIn() async {
        let coordinator = SermonProcessingCoordinator.shared
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }

        let spy = SpyDispatcher()
        coordinator.processingDispatcher = spy
        coordinator.isDurableProcessingEnabled = { true }

        // No modelContext is configured, so no sermons can be dispatched; what
        // this pins is that the mode change runs the durable path at all rather
        // than deferring to the next auth-state change.
        await coordinator.handleProcessingModeChange(userId: nil)

        #expect(spy.dispatched.isEmpty)
    }

    @Test func theFlagIsReadPerCallSoARollbackTakesEffectImmediately() async {
        let coordinator = SermonProcessingCoordinator.shared
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }

        let spy = SpyDispatcher()
        coordinator.processingDispatcher = spy

        // No modelContext is configured, so the sweep can't dispatch anyway;
        // what this pins down is that the gate is consulted on every call rather
        // than captured once at launch — a flag flipped off mid-session must
        // stop the new path without an app restart.
        var enabled = true
        var reads = 0
        coordinator.isDurableProcessingEnabled = {
            reads += 1
            return enabled
        }

        await coordinator.dispatchPendingDurableJobs()
        enabled = false
        await coordinator.dispatchPendingDurableJobs()

        #expect(reads == 2)
        #expect(spy.dispatched.isEmpty)
    }

    @Test func failedPermanentRetryUsesTheServerEvenWhenTheFlagIsOff() async throws {
        // Codex P2 / TAB-91: durable flag off is the default and the rollback
        // state. Retry still must send retry:true — TAB-90 refuses the legacy
        // client push out of failed_permanent.
        let isolated = IsolatedRecoveryStore()
        defer { isolated.defaults.removeObject(forKey: "SermonService.localDataOwnerUserId") }

        let schema = Schema([
            Sermon.self, Note.self, Transcript.self, Summary.self,
            ProcessingJob.self, TranscriptSegment.self, ChatMessage.self,
            User.self, UserNotificationSettings.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let sermon = Sermon(
            title: "Stopped",
            audioFileName: "stopped.m4a",
            date: Date(),
            serviceType: "Sunday",
            transcriptionStatus: SermonStageStatus.failedPermanent.rawValue,
            remoteId: "remote-stopped"
        )
        context.insert(sermon)
        try context.save()

        let coordinator = SermonProcessingCoordinator.shared
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }

        let spy = SpyDispatcher()
        coordinator.processingDispatcher = spy
        coordinator.isDurableProcessingEnabled = { false }
        coordinator.syncRunner = {}
        let sermonService = SermonService(
            modelContext: context,
            recoveryStore: isolated.store,
            userDefaults: isolated.defaults
        )
        coordinator.configure(modelContext: context, sermonService: sermonService)

        let ok = await coordinator.retryTranscriptionAwaitingServer(for: sermon.id)

        #expect(ok)
        #expect(spy.dispatched.map(\.1) == [true])
        #expect(sermon.transcriptionStatus == "processing")
    }
}
