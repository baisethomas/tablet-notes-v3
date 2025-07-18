import Foundation
import SwiftUI

// MARK: - Bible Data Models
struct Bible: Identifiable, Codable {
    let id: String
    let name: String
    let abbreviation: String
    let description: String
    let language: BibleLanguage
    
    struct BibleLanguage: Codable {
        let id: String
        let name: String
        let nameLocal: String
        let script: String
        let scriptDirection: String
    }
}

struct BibleBook: Identifiable, Codable {
    let id: String
    let bibleId: String
    let abbreviation: String
    let name: String
    let nameLong: String
}

struct BiblePassage: Codable {
    let id: String
    let bibleId: String
    let orgId: String
    let content: String
    let reference: String
    let verseCount: Int
    let copyright: String?
}

struct BibleVerse: Codable {
    let id: String
    let bibleId: String
    let reference: String
    let content: String
    let copyright: String?
}

// MARK: - Bible API Response Models
struct BibleResponse<T: Codable>: Codable {
    let data: T
}

struct BibleListResponse: Codable {
    let data: [Bible]
}

struct BibleBooksResponse: Codable {
    let data: [BibleBook]
}

// MARK: - Bible API Service
@MainActor
class BibleAPIService: ObservableObject {
    @Published var availableBibles: [Bible] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let baseURL = BibleAPIConfig.netlifyBaseURL
    
    init() {
        loadAvailableBibles()
    }
    
    // Load available Bible translations
    private func loadAvailableBibles() {
        // For now, create mock data based on our BibleTranslation types
        // This matches the translations we have configured
        self.availableBibles = BibleTranslation.allTranslations.map { translation in
            Bible(
                id: translation.id,
                name: translation.name,
                abbreviation: translation.abbreviation,
                description: translation.description,
                language: Bible.BibleLanguage(
                    id: "eng",
                    name: "English",
                    nameLocal: "English",
                    script: "Latn",
                    scriptDirection: "LTR"
                )
            )
        }
    }
    
    // Fetch books for a specific Bible version
    func fetchBooks(bibleId: String) async throws -> [BibleBook] {
        // Mock implementation - return standard Bible books
        return BibleBooks.allBooks.map { book in
            BibleBook(
                id: "\(bibleId)-\(book.id)",
                bibleId: bibleId,
                abbreviation: book.abbreviation,
                name: book.name,
                nameLong: book.nameLong
            )
        }
    }
    
    // Fetch a passage of Scripture
    func fetchPassage(reference: String, bibleId: String) async throws -> BiblePassage {
        // Mock implementation for now
        return BiblePassage(
            id: "\(bibleId)-\(reference)",
            bibleId: bibleId,
            orgId: "",
            content: "Mock passage content for \(reference). This would contain the actual Bible text in a real implementation.",
            reference: reference,
            verseCount: 1,
            copyright: "Mock Bible API"
        )
    }
    
    // Fetch a specific verse
    func fetchVerse(reference: String, bibleId: String) async throws -> BibleVerse {
        // Mock implementation for now
        return BibleVerse(
            id: "\(bibleId)-\(reference)",
            bibleId: bibleId,
            reference: reference,
            content: "Mock verse content for \(reference). This would contain the actual Bible verse in a real implementation.",
            copyright: "Mock Bible API"
        )
    }
}

// MARK: - Bible Books Data
struct BibleBooks {
    struct BookInfo {
        let id: String
        let abbreviation: String
        let name: String
        let nameLong: String
    }
    
    static let allBooks: [BookInfo] = [
        // Old Testament
        BookInfo(id: "GEN", abbreviation: "Gen", name: "Genesis", nameLong: "Genesis"),
        BookInfo(id: "EXO", abbreviation: "Exo", name: "Exodus", nameLong: "Exodus"),
        BookInfo(id: "LEV", abbreviation: "Lev", name: "Leviticus", nameLong: "Leviticus"),
        BookInfo(id: "NUM", abbreviation: "Num", name: "Numbers", nameLong: "Numbers"),
        BookInfo(id: "DEU", abbreviation: "Deu", name: "Deuteronomy", nameLong: "Deuteronomy"),
        BookInfo(id: "JOS", abbreviation: "Jos", name: "Joshua", nameLong: "Joshua"),
        BookInfo(id: "JDG", abbreviation: "Jdg", name: "Judges", nameLong: "Judges"),
        BookInfo(id: "RUT", abbreviation: "Rut", name: "Ruth", nameLong: "Ruth"),
        BookInfo(id: "1SA", abbreviation: "1Sa", name: "1 Samuel", nameLong: "1 Samuel"),
        BookInfo(id: "2SA", abbreviation: "2Sa", name: "2 Samuel", nameLong: "2 Samuel"),
        BookInfo(id: "1KI", abbreviation: "1Ki", name: "1 Kings", nameLong: "1 Kings"),
        BookInfo(id: "2KI", abbreviation: "2Ki", name: "2 Kings", nameLong: "2 Kings"),
        BookInfo(id: "1CH", abbreviation: "1Ch", name: "1 Chronicles", nameLong: "1 Chronicles"),
        BookInfo(id: "2CH", abbreviation: "2Ch", name: "2 Chronicles", nameLong: "2 Chronicles"),
        BookInfo(id: "EZR", abbreviation: "Ezr", name: "Ezra", nameLong: "Ezra"),
        BookInfo(id: "NEH", abbreviation: "Neh", name: "Nehemiah", nameLong: "Nehemiah"),
        BookInfo(id: "EST", abbreviation: "Est", name: "Esther", nameLong: "Esther"),
        BookInfo(id: "JOB", abbreviation: "Job", name: "Job", nameLong: "Job"),
        BookInfo(id: "PSA", abbreviation: "Psa", name: "Psalms", nameLong: "Psalms"),
        BookInfo(id: "PRO", abbreviation: "Pro", name: "Proverbs", nameLong: "Proverbs"),
        BookInfo(id: "ECC", abbreviation: "Ecc", name: "Ecclesiastes", nameLong: "Ecclesiastes"),
        BookInfo(id: "SNG", abbreviation: "Sng", name: "Song of Songs", nameLong: "Song of Songs"),
        BookInfo(id: "ISA", abbreviation: "Isa", name: "Isaiah", nameLong: "Isaiah"),
        BookInfo(id: "JER", abbreviation: "Jer", name: "Jeremiah", nameLong: "Jeremiah"),
        BookInfo(id: "LAM", abbreviation: "Lam", name: "Lamentations", nameLong: "Lamentations"),
        BookInfo(id: "EZK", abbreviation: "Ezk", name: "Ezekiel", nameLong: "Ezekiel"),
        BookInfo(id: "DAN", abbreviation: "Dan", name: "Daniel", nameLong: "Daniel"),
        BookInfo(id: "HOS", abbreviation: "Hos", name: "Hosea", nameLong: "Hosea"),
        BookInfo(id: "JOL", abbreviation: "Jol", name: "Joel", nameLong: "Joel"),
        BookInfo(id: "AMO", abbreviation: "Amo", name: "Amos", nameLong: "Amos"),
        BookInfo(id: "OBA", abbreviation: "Oba", name: "Obadiah", nameLong: "Obadiah"),
        BookInfo(id: "JON", abbreviation: "Jon", name: "Jonah", nameLong: "Jonah"),
        BookInfo(id: "MIC", abbreviation: "Mic", name: "Micah", nameLong: "Micah"),
        BookInfo(id: "NAM", abbreviation: "Nam", name: "Nahum", nameLong: "Nahum"),
        BookInfo(id: "HAB", abbreviation: "Hab", name: "Habakkuk", nameLong: "Habakkuk"),
        BookInfo(id: "ZEP", abbreviation: "Zep", name: "Zephaniah", nameLong: "Zephaniah"),
        BookInfo(id: "HAG", abbreviation: "Hag", name: "Haggai", nameLong: "Haggai"),
        BookInfo(id: "ZEC", abbreviation: "Zec", name: "Zechariah", nameLong: "Zechariah"),
        BookInfo(id: "MAL", abbreviation: "Mal", name: "Malachi", nameLong: "Malachi"),
        
        // New Testament
        BookInfo(id: "MAT", abbreviation: "Mat", name: "Matthew", nameLong: "Matthew"),
        BookInfo(id: "MRK", abbreviation: "Mrk", name: "Mark", nameLong: "Mark"),
        BookInfo(id: "LUK", abbreviation: "Luk", name: "Luke", nameLong: "Luke"),
        BookInfo(id: "JHN", abbreviation: "Jhn", name: "John", nameLong: "John"),
        BookInfo(id: "ACT", abbreviation: "Act", name: "Acts", nameLong: "Acts"),
        BookInfo(id: "ROM", abbreviation: "Rom", name: "Romans", nameLong: "Romans"),
        BookInfo(id: "1CO", abbreviation: "1Co", name: "1 Corinthians", nameLong: "1 Corinthians"),
        BookInfo(id: "2CO", abbreviation: "2Co", name: "2 Corinthians", nameLong: "2 Corinthians"),
        BookInfo(id: "GAL", abbreviation: "Gal", name: "Galatians", nameLong: "Galatians"),
        BookInfo(id: "EPH", abbreviation: "Eph", name: "Ephesians", nameLong: "Ephesians"),
        BookInfo(id: "PHP", abbreviation: "Php", name: "Philippians", nameLong: "Philippians"),
        BookInfo(id: "COL", abbreviation: "Col", name: "Colossians", nameLong: "Colossians"),
        BookInfo(id: "1TH", abbreviation: "1Th", name: "1 Thessalonians", nameLong: "1 Thessalonians"),
        BookInfo(id: "2TH", abbreviation: "2Th", name: "2 Thessalonians", nameLong: "2 Thessalonians"),
        BookInfo(id: "1TI", abbreviation: "1Ti", name: "1 Timothy", nameLong: "1 Timothy"),
        BookInfo(id: "2TI", abbreviation: "2Ti", name: "2 Timothy", nameLong: "2 Timothy"),
        BookInfo(id: "TIT", abbreviation: "Tit", name: "Titus", nameLong: "Titus"),
        BookInfo(id: "PHM", abbreviation: "Phm", name: "Philemon", nameLong: "Philemon"),
        BookInfo(id: "HEB", abbreviation: "Heb", name: "Hebrews", nameLong: "Hebrews"),
        BookInfo(id: "JAS", abbreviation: "Jas", name: "James", nameLong: "James"),
        BookInfo(id: "1PE", abbreviation: "1Pe", name: "1 Peter", nameLong: "1 Peter"),
        BookInfo(id: "2PE", abbreviation: "2Pe", name: "2 Peter", nameLong: "2 Peter"),
        BookInfo(id: "1JN", abbreviation: "1Jn", name: "1 John", nameLong: "1 John"),
        BookInfo(id: "2JN", abbreviation: "2Jn", name: "2 John", nameLong: "2 John"),
        BookInfo(id: "3JN", abbreviation: "3Jn", name: "3 John", nameLong: "3 John"),
        BookInfo(id: "JUD", abbreviation: "Jud", name: "Jude", nameLong: "Jude"),
        BookInfo(id: "REV", abbreviation: "Rev", name: "Revelation", nameLong: "Revelation")
    ]
}