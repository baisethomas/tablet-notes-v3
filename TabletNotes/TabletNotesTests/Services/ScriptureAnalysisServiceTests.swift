import Foundation
import Testing
@testable import TabletNotes

// TAB-121: transcripts carry spoken references, not `Book chapter:verse`.
// The analyzer used to miss those, and it dropped a written reference that
// followed another word ("in Romans 8:28") because the book pattern swallowed
// the preceding word.
struct ScriptureAnalysisServiceTests {
    private let analyzer = ScriptureAnalysisService()

    private func display(_ text: String) -> [String] {
        analyzer.analyzeScriptureReferences(in: text).map(\.displayText)
    }

    private func readingOrder(_ text: String) -> [String] {
        let refs = analyzer.analyzeScriptureReferences(in: text)
        return refs.sorted { lhs, rhs in
            position(of: lhs.raw, in: text) < position(of: rhs.raw, in: text)
        }.map(\.displayText)
    }

    private func position(of raw: String, in text: String) -> Int {
        guard let range = text.range(of: raw) else { return Int.max }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    // MARK: - Spoken lines from TAB-121

    @Test func spokenJoshuaFourteenVerseTwelve() {
        let line = "in Joshua 14, verse 12"
        #expect(readingOrder(line) == ["Joshua 14:12"])
        #expect(analyzer.analyzeScriptureReferences(in: line).first?.raw.contains("Joshua") == true)
    }

    @Test func spokenPsalmsEighteenVerseThirtyTwo() {
        #expect(readingOrder("Psalms 18, verse 32") == ["Psalms 18:32"])
    }

    @Test func spokenPsalmsThirtySevenVerseTwentyThree() {
        #expect(readingOrder("Psalms 37, verse 23") == ["Psalms 37:23"])
    }

    @Test func spokenJohnFiveVerseFour() {
        #expect(readingOrder("John 5, verse 4") == ["John 5:4"])
    }

    @Test func spokenMarksGospelEleventhChapterVerseTwentyThree() {
        let line = "Jesus says in Mark's gospel, the 11th chapter, verse 23"
        #expect(readingOrder(line) == ["Mark 11:23"])
    }

    @Test func spokenJamesOneAndLetsStartAtVerseTwo() {
        let line = "James 1, and let's start at verse 2"
        #expect(readingOrder(line) == ["James 1:2"])
    }

    @Test func sixSpokenLinesYieldReferencesInReadingOrder() {
        let text = """
        in Joshua 14, verse 12
        Psalms 18, verse 32
        Psalms 37, verse 23
        John 5, verse 4
        Jesus says in Mark's gospel, the 11th chapter, verse 23
        James 1, and let's start at verse 2
        """
        #expect(readingOrder(text) == [
            "Joshua 14:12",
            "Psalms 18:32",
            "Psalms 37:23",
            "John 5:4",
            "Mark 11:23",
            "James 1:2"
        ])
    }

    // MARK: - Written after a word (the known book-pattern bug)

    @Test func writtenReferenceAfterAWordIsKept() {
        let line = "in Romans 8:28"
        #expect(readingOrder(line) == ["Romans 8:28"])
        #expect(analyzer.analyzeScriptureReferences(in: line).first?.raw == "Romans 8:28"
            || analyzer.analyzeScriptureReferences(in: line).first?.raw == "in Romans 8:28")
    }

    // MARK: - False positives

    @Test func chapterWithoutABookNameIsNotAReference() {
        #expect(display("chapter 3 of this book") == [])
        #expect(display("the 11th chapter, verse 23") == [])
        #expect(display("verse 12") == [])
    }

    // MARK: - Existing written-form regressions

    @Test func standardWrittenFormStillMatches() {
        #expect(readingOrder("Romans 8:28") == ["Romans 8:28"])
        #expect(readingOrder("John 3:16") == ["John 3:16"])
    }

    @Test func abbreviatedWrittenFormStillMatches() {
        #expect(readingOrder("1 Cor 13:4-7") == ["1 Corinthians 13:4-7"])
        #expect(readingOrder("Jn 3:16") == ["John 3:16"])
    }

    @Test func writtenRangeAndMultipleOnOneLineKeepReadingOrder() {
        #expect(readingOrder("John 3:16-18 and Romans 8:28") == ["John 3:16-18", "Romans 8:28"])
    }

    @Test func rawIsTheMatchedTextSoThePlannerCanLocateIt() {
        let line = "in Joshua 14, verse 12 we stand"
        let ref = try #require(analyzer.analyzeScriptureReferences(in: line).first)
        #expect(line.contains(ref.raw))
        #expect(ref.book == "Joshua")
        #expect(ref.chapter == 14)
        #expect(ref.verseStart == 12)
    }
}
