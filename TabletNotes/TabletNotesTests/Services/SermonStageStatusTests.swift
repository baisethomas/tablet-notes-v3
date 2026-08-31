import Foundation
import Testing
@testable import TabletNotes

// TAB-85 part 2. The pipeline could only stop one way — `complete` — so a
// recording that could never be transcribed, and one that contained no speech,
// both sat at `pending`: a spinner the user could not clear, and a sermon the
// coordinator re-dispatched on every sweep.

@Suite("Sermon stage status")
struct SermonStageStatusTests {

    @Test("the terminal states are the ones nothing further will happen to")
    func terminalSet() {
        let terminal = SermonStageStatus.allCases.filter(\.isTerminal).map(\.rawValue).sorted()
        #expect(terminal == ["complete", "failed_permanent", "no_speech", "too_short"])
    }

    @Test("a stopped stage is never dispatched again")
    func terminalIsNotDispatchable() {
        // This is the churn the issue is about: the coordinator asked the server
        // to process these sermons on every single sweep, forever.
        for status in SermonStageStatus.allCases where status.isTerminal {
            #expect(status.isDispatchable == false, "\(status.rawValue) must not be re-dispatched")
        }
    }

    @Test("only pending and failed are dispatchable")
    func dispatchableSet() {
        // Must match the #Predicate in dispatchPendingDurableJobs, which cannot
        // call into Swift and so spells these out as string literals.
        let dispatchable = SermonStageStatus.allCases.filter(\.isDispatchable).map(\.rawValue).sorted()
        #expect(dispatchable == ["failed", "pending"])
    }

    @Test("the raw values match what the server writes")
    func rawValuesMatchServer() {
        // Mirrored in tablet-notes-api/netlify/functions/utils/sermonStatus.js.
        // A typo on either side is a state the other one silently ignores.
        #expect(SermonStageStatus.noSpeech.rawValue == "no_speech")
        #expect(SermonStageStatus.failedPermanent.rawValue == "failed_permanent")
        #expect(SermonStageStatus.tooShort.rawValue == "too_short")
        #expect(SermonStageStatus.complete.rawValue == "complete")
    }

    @Test("a status this build predates is unknown, not mistaken for pending")
    func unknownStatusDegrades() {
        // The server can write a new state before every device can render it.
        // Reading it as `pending` would restart the churn this issue ends.
        #expect(SermonStageStatus.known("something_new_and_unreleased") == nil)
        #expect(SermonStageStatus.known("too_short") == .tooShort)
        #expect(SermonStageStatus.known("no_speech") == .noSpeech)
    }
}

@Suite("Sermon list status label")
@MainActor
struct SermonStatusTextTests {

    @Test("a recording the pipeline gave up on is not listed as still working")
    func permanentFailureIsNotPending() {
        // What the server writes when a transcription job dies: the transcript
        // stage stops, the summary stage never starts. Before TAB-85 this fell
        // through to the summary-pending branch and the row showed an orange
        // "Processing..." forever, for work that had been abandoned.
        let (text, _) = sermonStatusText(
            transcriptionStatus: "failed_permanent",
            summaryStatus: "pending"
        )
        #expect(text == "Couldn't process")
    }

    @Test("a stopped recording is not listed as Ready either")
    func permanentFailureIsNotReady() {
        // Once both stages are terminal, every earlier branch missed and the
        // row claimed a green "Ready" for a sermon with no transcript at all.
        let (text, _) = sermonStatusText(
            transcriptionStatus: "failed_permanent",
            summaryStatus: "failed_permanent"
        )
        #expect(text == "Couldn't process")
    }

    @Test("a no-speech recording says so rather than claiming a result")
    func noSpeechIsLabelled() {
        let (text, _) = sermonStatusText(transcriptionStatus: "no_speech", summaryStatus: "no_speech")
        #expect(text == "No speech detected")
    }

    @Test("a summary that gave up is surfaced even when the transcript is fine")
    func permanentSummaryFailure() {
        let (text, _) = sermonStatusText(transcriptionStatus: "complete", summaryStatus: "failed_permanent")
        #expect(text == "Couldn't process")
    }

    @Test("failed_permanent is still a settled list state after Retry exists")
    func permanentFailureListLabelUnchanged() {
        // TAB-91 re-enables the detail Retry button; the list must still say
        // the pipeline stopped, not "Processing..." or "Failed".
        let (text, _) = sermonStatusText(
            transcriptionStatus: "failed_permanent",
            summaryStatus: "pending"
        )
        #expect(text == "Couldn't process")
    }

    @Test("a short transcript is Ready, not stuck Processing")
    func tooShortSummaryIsSettled() {
        // TAB-92: transcription complete, summary refused because the
        // transcript is below the 50-character floor. Before too_short this
        // sat at summary pending and the row said "Processing..." forever.
        let (text, color) = sermonStatusText(
            transcriptionStatus: "complete",
            summaryStatus: "too_short"
        )
        #expect(text == "Ready")
        #expect(color == .green)
    }

    @Test("the ordinary states are unchanged")
    func existingLabelsUnchanged() {
        #expect(sermonStatusText(transcriptionStatus: "complete", summaryStatus: "complete").0 == "Ready")
        #expect(sermonStatusText(transcriptionStatus: "failed", summaryStatus: "pending").0 == "Failed")
        #expect(sermonStatusText(transcriptionStatus: "processing", summaryStatus: "pending").0 == "Processing...")
        #expect(sermonStatusText(transcriptionStatus: "pending", summaryStatus: "pending").0 == "Transcribing...")
        #expect(sermonStatusText(transcriptionStatus: "complete", summaryStatus: "pending").0 == "Processing...")
    }
}

// TAB-54: unprocessed/failed recordings must be visibly annotated in the
// sermon list, and ordinary rows must not be.
@Suite("Sermon row status badge")
@MainActor
struct SermonRowStatusBadgeTests {

    @Test("a fully processed sermon gets no badge")
    func readyRowsAreUnannotated() {
        #expect(sermonRowStatusBadge(transcriptionStatus: "complete", summaryStatus: "complete") == nil)
    }

    @Test("in-flight and failed recordings are labeled")
    func nonTerminalAndFailedRowsGetBadges() {
        #expect(sermonRowStatusBadge(transcriptionStatus: "pending", summaryStatus: "pending")?.0 == "Transcribing...")
        #expect(sermonRowStatusBadge(transcriptionStatus: "processing", summaryStatus: "pending")?.0 == "Processing...")
        #expect(sermonRowStatusBadge(transcriptionStatus: "complete", summaryStatus: "pending")?.0 == "Processing...")
        #expect(sermonRowStatusBadge(transcriptionStatus: "failed", summaryStatus: "pending")?.0 == "Failed")
        #expect(sermonRowStatusBadge(transcriptionStatus: "failed_permanent", summaryStatus: "pending")?.0 == "Couldn't process")
        #expect(sermonRowStatusBadge(transcriptionStatus: "no_speech", summaryStatus: "no_speech")?.0 == "No speech detected")
    }

    @Test("too_short is Ready by the pinned TAB-92 decision, so no badge")
    func tooShortStaysUnannotated() {
        #expect(sermonRowStatusBadge(transcriptionStatus: "complete", summaryStatus: "too_short") == nil)
    }
}

// TAB-54: two recordings created moments apart must not share a fallback
// title — identical titles read as duplicate rows.
@Suite("Sermon fallback title")
struct SermonFallbackTitleTests {

    @Test("recordings one second apart get distinct titles")
    func sameMinuteRecordingsDoNotCollide() {
        let base = Date(timeIntervalSince1970: 1_756_500_000)
        let oneSecondLater = base.addingTimeInterval(1)
        #expect(Sermon.fallbackTitle(for: base) != Sermon.fallbackTitle(for: oneSecondLater))
    }

    @Test("the title keeps the recognizable prefix and carries real content")
    func titleShapeIsStable() {
        // Hermetic across locales: no assumptions about how the current
        // locale composes a combined date+time string — only the stable
        // prefix and that the date/time portion actually varies with the
        // date (a day apart must differ even if seconds happen to match).
        let date = Date(timeIntervalSince1970: 1_756_500_000)
        let title = Sermon.fallbackTitle(for: date)
        #expect(title.hasPrefix("Sermon on "))
        #expect(title.count > "Sermon on ".count)
        #expect(title != Sermon.fallbackTitle(for: date.addingTimeInterval(86_400)))
    }
}
