import SwiftUI

struct BibleBrowserView: View {
    @StateObject private var bibleService = BibleAPIService()
    @State private var selectedBibleId = BibleAPIConfig.defaultBibleId
    @State private var selectedBook: BibleBook?
    @State private var selectedChapter: Int = 1
    @State private var selectedVerseStart: Int = 1
    @State private var selectedVerseEnd: Int?
    @State private var isLoadingBooks = true
    @State private var isLoadingContent = false
    @State private var availableBooks: [BibleBook] = []
    @State private var scriptureContent: String = ""
    @State private var showingVerseRangePicker = false
    @State private var errorMessage: String?
    
    @Environment(\.dismiss) private var dismiss
    
    let onSelectScripture: (ScriptureReference, String) -> Void
    
    init(onSelectScripture: @escaping (ScriptureReference, String) -> Void) {
        self.onSelectScripture = onSelectScripture
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Bible Version Selector
                if !bibleService.availableBibles.isEmpty {
                    Picker("Bible Version", selection: $selectedBibleId) {
                        ForEach(bibleService.availableBibles.prefix(5)) { bible in
                            Text("\(bible.abbreviation) - \(bible.name)")
                                .tag(bible.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding()
                    .onChange(of: selectedBibleId) { _, _ in
                        loadBooks()
                    }
                }
                
                if isLoadingBooks {
                    VStack {
                        ProgressView("Loading Bible books...")
                        Spacer()
                    }
                } else if let errorMessage = errorMessage {
                    VStack {
                        Text("Error: \(errorMessage)")
                            .foregroundColor(.red)
                        Button("Retry") {
                            loadBooks()
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Book Selector
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Select Book")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                LazyVGrid(columns: [
                                    GridItem(.adaptive(minimum: 100), spacing: 8)
                                ], spacing: 8) {
                                    ForEach(availableBooks) { book in
                                        Button(action: {
                                            selectedBook = book
                                            selectedChapter = 1
                                            selectedVerseStart = 1
                                            selectedVerseEnd = nil
                                            loadScripture()
                                        }) {
                                            Text(book.abbreviation)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(selectedBook?.id == book.id ? .white : .accentColor)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(
                                                    selectedBook?.id == book.id ? 
                                                    Color.accentColor : Color.accentColor.opacity(0.1)
                                                )
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            
                            if selectedBook != nil {
                                Divider()
                                
                                // Chapter and Verse Selectors
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("Select Chapter & Verse")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    
                                    HStack(spacing: 20) {
                                        // Chapter Picker
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Chapter")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.secondary)
                                            
                                            Picker("Chapter", selection: $selectedChapter) {
                                                ForEach(1...50, id: \.self) { chapter in
                                                    Text("\(chapter)").tag(chapter)
                                                }
                                            }
                                            .pickerStyle(.wheel)
                                            .frame(height: 100)
                                            .clipped()
                                            .onChange(of: selectedChapter) { _, _ in
                                                selectedVerseStart = 1
                                                selectedVerseEnd = nil
                                                loadScripture()
                                            }
                                        }
                                        
                                        // Verse Start Picker
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Start Verse")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.secondary)
                                            
                                            Picker("Start Verse", selection: $selectedVerseStart) {
                                                ForEach(1...50, id: \.self) { verse in
                                                    Text("\(verse)").tag(verse)
                                                }
                                            }
                                            .pickerStyle(.wheel)
                                            .frame(height: 100)
                                            .clipped()
                                            .onChange(of: selectedVerseStart) { _, _ in
                                                selectedVerseEnd = nil
                                                loadScripture()
                                            }
                                        }
                                        
                                        // Verse End Picker (Optional)
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("End Verse (Optional)")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.secondary)
                                            
                                            Picker("End Verse", selection: Binding(
                                                get: { selectedVerseEnd ?? selectedVerseStart },
                                                set: { newValue in
                                                    selectedVerseEnd = newValue > selectedVerseStart ? newValue : nil
                                                    loadScripture()
                                                }
                                            )) {
                                                ForEach(selectedVerseStart...min(selectedVerseStart + 20, 50), id: \.self) { verse in
                                                    Text(verse == selectedVerseStart ? "Single" : "\(verse)")
                                                        .tag(verse)
                                                }
                                            }
                                            .pickerStyle(.wheel)
                                            .frame(height: 100)
                                            .clipped()
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                
                                Divider()
                                
                                // Scripture Preview
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Preview")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        
                                        Spacer()
                                        
                                        if let book = selectedBook {
                                            Text(createReferenceText(book: book))
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    
                                    if isLoadingContent {
                                        HStack {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                            Text("Loading scripture...")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding()
                                    } else if !scriptureContent.isEmpty {
                                        ScrollView {
                                            Text(scriptureContent)
                                                .font(.body)
                                                .lineSpacing(4)
                                                .textSelection(.enabled)
                                                .padding()
                                                .background(Color(.systemGray6).opacity(0.5))
                                                .cornerRadius(8)
                                        }
                                        .frame(maxHeight: 200)
                                    }
                                }
                                .padding(.horizontal)
                                
                                // Add to Notes Button
                                if selectedBook != nil && !scriptureContent.isEmpty {
                                    Button(action: addToNotes) {
                                        HStack {
                                            Image(systemName: "plus.circle.fill")
                                            Text("Add to Notes")
                                        }
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.accentColor)
                                        .cornerRadius(12)
                                    }
                                    .padding(.horizontal)
                                    .padding(.bottom)
                                }
                            }
                            
                            Spacer(minLength: 50)
                        }
                    }
                }
            }
            .navigationTitle("Bible Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadBooks()
        }
    }
    
    // MARK: - Private Methods
    
    private func loadBooks() {
        isLoadingBooks = true
        errorMessage = nil
        
        Task {
            do {
                let books = try await bibleService.fetchBooks(bibleId: selectedBibleId)
                await MainActor.run {
                    availableBooks = books
                    isLoadingBooks = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoadingBooks = false
                }
            }
        }
    }
    
    private func loadScripture() {
        guard let book = selectedBook else { return }
        
        isLoadingContent = true
        
        let reference = ScriptureReference(
            book: book.name,
            chapter: selectedChapter,
            verseStart: selectedVerseStart,
            verseEnd: selectedVerseEnd,
            raw: createReferenceText(book: book)
        )
        
        Task {
            do {
                let content: String
                if reference.isRange {
                    let passage = try await bibleService.fetchPassage(reference: reference, bibleId: selectedBibleId)
                    content = cleanScriptureContent(passage.content)
                } else {
                    let verse = try await bibleService.fetchVerse(reference: reference, bibleId: selectedBibleId)
                    content = cleanScriptureContent(verse.content)
                }
                
                await MainActor.run {
                    scriptureContent = content
                    isLoadingContent = false
                }
            } catch {
                await MainActor.run {
                    scriptureContent = "Failed to load scripture: \(error.localizedDescription)"
                    isLoadingContent = false
                }
            }
        }
    }
    
    private func createReferenceText(book: BibleBook) -> String {
        if let verseEnd = selectedVerseEnd, verseEnd > selectedVerseStart {
            return "\(book.name) \(selectedChapter):\(selectedVerseStart)-\(verseEnd)"
        } else {
            return "\(book.name) \(selectedChapter):\(selectedVerseStart)"
        }
    }
    
    private func addToNotes() {
        guard let book = selectedBook else { return }
        
        let reference = ScriptureReference(
            book: book.name,
            chapter: selectedChapter,
            verseStart: selectedVerseStart,
            verseEnd: selectedVerseEnd,
            raw: createReferenceText(book: book)
        )
        
        onSelectScripture(reference, scriptureContent)
        dismiss()
    }
    
    private func cleanScriptureContent(_ content: String) -> String {
        // Remove HTML tags and clean up the content
        var cleanedContent = content
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        
        // Fix verse number spacing - add space after verse numbers
        // This regex matches verse numbers (digits) that are immediately followed by a letter
        cleanedContent = cleanedContent.replacingOccurrences(
            of: "(\\d+)([A-Za-z])", 
            with: "$1 $2", 
            options: .regularExpression
        )
        
        return cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Bible FAB Component
struct BibleFAB: View {
    @State private var showingBibleBrowser = false
    let onAddScripture: (ScriptureReference, String) -> Void
    
    var body: some View {
        Button(action: {
            showingBibleBrowser = true
        }) {
            ZStack {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .sheet(isPresented: $showingBibleBrowser) {
            BibleBrowserView { reference, content in
                onAddScripture(reference, content)
            }
        }
    }
}

#Preview {
    BibleBrowserView { reference, content in
        print("Selected: \(reference.displayText)")
        print("Content: \(content)")
    }
}