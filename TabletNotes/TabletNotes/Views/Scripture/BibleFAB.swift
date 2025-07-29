import SwiftUI

// MARK: - Bible Floating Action Button
// A FAB that allows users to quickly search and insert Bible verses

struct BibleFAB: View {
    let onScriptureSelected: (ScriptureReference, String) -> Void
    @State private var showingBibleSearch = false
    
    var body: some View {
        Button(action: {
            showingBibleSearch = true
        }) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 56, height: 56)
                
                Image(systemName: "book.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showingBibleSearch) {
            BibleSearchView { reference, content in
                onScriptureSelected(reference, content)
                showingBibleSearch = false
            }
        }
    }
}

// MARK: - Bible Search View
// A full-screen view for searching and selecting Bible verses

struct BibleSearchView: View {
    let onScriptureSelected: (ScriptureReference, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bibleService = DirectBibleAPIService()
    
    @State private var searchText = ""
    @State private var selectedBibleVersion = ApiBibleConfig.defaultBibleId
    @State private var searchResults: [BibleVerse] = []
    @State private var isSearching = false
    @State private var quickReferences: [QuickReference] = QuickReference.popular
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Section
                VStack(spacing: 16) {
                    // Bible Version Selector
                    if !bibleService.availableBibles.isEmpty {
                        Menu {
                            ForEach(bibleService.availableBibles) { bible in
                                Button(action: {
                                    selectedBibleVersion = bible.id
                                    performSearch()
                                }) {
                                    HStack {
                                        Text(bible.abbreviation)
                                        Text(bible.name)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Version:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(getCurrentBibleName())
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.accentColor)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search verses or enter reference (e.g., John 3:16)", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .onSubmit {
                                performSearch()
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                searchResults = []
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .padding()
                
                Divider()
                
                // Content Section
                if isSearching {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Searching...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && searchText.isEmpty {
                    // Quick References
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            Text("Quick References")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .padding(.top)
                            
                            ForEach(quickReferences, id: \.reference) { quickRef in
                                QuickReferenceRow(quickReference: quickRef) {
                                    selectReference(quickRef.reference)
                                }
                            }
                        }
                        .padding()
                    }
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    // No Results
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        
                        Text("No verses found")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Try adjusting your search terms or check the Bible version.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    // Search Results
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(searchResults, id: \.id) { verse in
                                VerseResultRow(verse: verse) {
                                    selectVerse(verse)
                                }
                            }
                        }
                        .padding()
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Bible Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func getCurrentBibleName() -> String {
        if let bible = bibleService.availableBibles.first(where: { $0.id == selectedBibleVersion }) {
            return bible.abbreviation
        }
        return "KJV"
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        // Check if the search text looks like a reference (e.g., "John 3:16")
        if isReference(searchText) {
            // Direct reference lookup
            fetchReference(searchText)
        } else {
            // Text search
            searchVerses(searchText)
        }
    }
    
    private func isReference(_ text: String) -> Bool {
        let referencePattern = #"^\d*\s*[A-Za-z]+\s+\d+:\d+(-\d+)?$"#
        return text.range(of: referencePattern, options: .regularExpression) != nil
    }
    
    private func fetchReference(_ reference: String) {
        Task {
            do {
                let verse = try await bibleService.fetchVerse(reference: reference, bibleId: selectedBibleVersion)
                await MainActor.run {
                    searchResults = [verse]
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }
    
    private func searchVerses(_ query: String) {
        Task {
            do {
                let verses = try await bibleService.searchVerses(query: query, bibleId: selectedBibleVersion, limit: 20)
                await MainActor.run {
                    searchResults = verses
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }
    
    private func selectReference(_ reference: String) {
        searchText = reference
        performSearch()
    }
    
    private func selectVerse(_ verse: BibleVerse) {
        let scriptureRef = ScriptureReference.parse(verse.reference) ?? ScriptureReference(
            book: "Unknown",
            chapter: 1,
            verseStart: 1,
            verseEnd: nil,
            raw: verse.reference
        )
        
        let content = cleanScriptureContent(verse.content)
        onScriptureSelected(scriptureRef, content)
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
        
        // Fix verse number spacing
        cleanedContent = cleanedContent.replacingOccurrences(
            of: "(\\d+)([A-Za-z])",
            with: "$1 $2",
            options: .regularExpression
        )
        
        return cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Supporting Views

struct QuickReferenceRow: View {
    let quickReference: QuickReference
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quickReference.reference)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(quickReference.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct VerseResultRow: View {
    let verse: BibleVerse
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verse.reference)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                
                Text(cleanContent(verse.content))
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6).opacity(0.3))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func cleanContent(_ content: String) -> String {
        return content
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Quick Reference Model

struct QuickReference {
    let reference: String
    let description: String
    
    static let popular = [
        QuickReference(reference: "John 3:16", description: "For God so loved the world"),
        QuickReference(reference: "Romans 8:28", description: "All things work together for good"),
        QuickReference(reference: "Philippians 4:13", description: "I can do all things through Christ"),
        QuickReference(reference: "Psalm 23:1", description: "The Lord is my shepherd"),
        QuickReference(reference: "Jeremiah 29:11", description: "Plans to prosper you"),
        QuickReference(reference: "Matthew 28:19", description: "The Great Commission"),
        QuickReference(reference: "1 Corinthians 13:4", description: "Love is patient and kind"),
        QuickReference(reference: "Isaiah 40:31", description: "Those who wait on the Lord"),
        QuickReference(reference: "Proverbs 3:5-6", description: "Trust in the Lord with all your heart"),
        QuickReference(reference: "Romans 12:2", description: "Be transformed by renewing your mind")
    ]
}

#Preview {
    BibleFAB { reference, content in
        print("Selected: \(reference.displayText) - \(content)")
    }
}