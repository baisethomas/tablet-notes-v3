import Foundation
@testable import TabletNotes

/// An `InterruptedRecordingRecoveryStore` backed by a throwaway `UserDefaults`
/// suite, so a test never shares the recovery manifest with anything else.
///
/// The manifest used to live on one process-global key in `.standard`. Four
/// suites read and cleared it, and Swift Testing runs tests in parallel — so a
/// suite calling `clear()` in its setup could wipe a manifest another suite had
/// just written. That made `SermonService`'s sign-out guard see an interrupted
/// recording (or fail to) at random. Per-test suites remove the sharing rather
/// than trying to order the sharers, which `.serialized` alone cannot do across
/// separate suites.
/// A class rather than a struct so `deinit` can remove the backing suite.
/// Swift Testing builds a fresh instance of a suite type for every test, so
/// holding one of these as a stored property gives each test its own store and
/// cleans it up automatically — no per-test `defer` bookkeeping to forget.
final class IsolatedRecoveryStore {
    /// The suite itself, exposed for the *other* process-global key these
    /// tests share: `SermonService.localDataOwnerUserId`.
    let defaults: UserDefaults
    let store: InterruptedRecordingRecoveryStore
    private let suiteName: String

    init() {
        let suiteName = "tabletnotes.tests.recovery.\(UUID().uuidString)"
        // A freshly-named suite is always empty, so there is nothing to clear.
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create an isolated UserDefaults suite for testing")
        }
        self.suiteName = suiteName
        self.defaults = defaults
        self.store = InterruptedRecordingRecoveryStore(userDefaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
