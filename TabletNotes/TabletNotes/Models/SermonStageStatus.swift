import Foundation

/// The states one processing stage (transcription or summary) can be in.
///
/// These strings are written by the **server** — `sermons.transcription_status`
/// and `sermons.summary_status` — and mirrored in
/// `tablet-notes-api/netlify/functions/utils/sermonStatus.js`. The two lists
/// must agree; this type exists so the vocabulary is stated once on this side
/// rather than spelled out as string literals at each comparison.
///
/// Before TAB-85 there were four, and only one of them meant *stopped*:
/// `complete`. A recording that could never be transcribed and one that
/// contained no speech both sat at `pending` — a spinner the user could not
/// clear, and a sermon the client re-dispatched on every sweep.
enum SermonStageStatus: String, CaseIterable, Sendable {
    /// Queued, or waiting on an earlier stage.
    case pending
    /// Work is in flight.
    case processing
    /// Finished, with a real result.
    case complete
    /// Failed, and worth trying again.
    case failed
    /// Transcription succeeded; the recording contained no speech.
    case noSpeech = "no_speech"
    /// The pipeline used up its attempts and stopped trying.
    case failedPermanent = "failed_permanent"

    /// The stage has stopped and nothing further will happen on its own.
    ///
    /// Server-owned: a client may not write itself out of one of these, so the
    /// UI can render them as settled rather than as a stage still in motion.
    var isTerminal: Bool {
        switch self {
        case .complete, .noSpeech, .failedPermanent: return true
        case .pending, .processing, .failed: return false
        }
    }

    /// Whether the coordinator should ask the server to process this stage.
    ///
    /// Kept in step with the `#Predicate` in
    /// `SermonProcessingCoordinator.dispatchPendingDurableJobs`, which must use
    /// string literals because SwiftData cannot call into Swift from a
    /// predicate. That predicate is an allowlist, so a status this build has
    /// never heard of is excluded by construction.
    var isDispatchable: Bool {
        switch self {
        case .pending, .failed: return true
        case .processing, .complete, .noSpeech, .failedPermanent: return false
        }
    }

    /// A status string as stored, tolerating one this build predates.
    ///
    /// The server can start writing a new state before every device has the
    /// build that renders it, so an unknown value must degrade rather than
    /// crash or be silently treated as `pending` (which would restart the very
    /// churn TAB-85 ends).
    static func known(_ raw: String) -> SermonStageStatus? {
        SermonStageStatus(rawValue: raw)
    }
}
