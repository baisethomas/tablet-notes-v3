import SwiftUI

struct ScriptureSearchFAB: View {
    let onScriptureSelected: (ScriptureReference, String) -> Void
    
    @State private var showingBibleSheet = false
    @State private var showingSearchSheet = false
    @StateObject private var bibleService = BibleAPIService()
    
    var body: some View {
        VStack(spacing: 12) {
            // Quick Search Button
            Button(action: {
                showingSearchSheet = true
            }) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: "book.closed")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(showingBibleSheet ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: showingBibleSheet)
        }
        .sheet(isPresented: $showingSearchSheet) {
            ScriptureSearchView { reference, content in
                onScriptureSelected(reference, content)
                showingSearchSheet = false
            }
        }
    }
}

// MARK: - Scripture Search View
struct ScriptureSearchView: View {
    let onSelection: (ScriptureReference, String) -> Void
    
    @State private var searchText = ""
    @State private var searchResults: [ScriptureReference] = []
    @State private var isSearching = false
    @State private var selectedReference: ScriptureReference?
    @State private var scriptureContent = ""
    @State private var showingDetail = false
    @StateObject private var bibleService = BibleAPIService()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search scripture (e.g., John 3:16)", text: $searchText)
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Quick Access Buttons
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(popularScriptures, id: \.self) { scripture in
                                Button(action: {
                                    searchText = scripture
                                    performSearch()
                                }) {
                                    Text(scripture)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(16)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Divider()
                    .padding(.top, 16)
                
                // Search Results
                if isSearching {
                    VStack {
                        ProgressView()
                            .padding()
                        Text("Searching...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No results found")
                            .font(.headline)
                        Text("Try searching for a book name, chapter, or verse reference")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if !searchResults.isEmpty {
                    List(searchResults, id: \.id) { reference in
                        ScriptureSuggestionRow(reference: reference) {
                            selectScripture(reference)
                        }
                    }
                } else {
                    // Empty state
                    VStack(spacing: 24) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 64))
                            .foregroundColor(.accentColor.opacity(0.6))
                        
                        VStack(spacing: 8) {
                            Text("Search Scripture")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Enter a book name, chapter, or verse reference to find and insert scripture into your notes")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        VStack(spacing: 12) {
                            Text("Examples:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• John 3:16")
                                Text("• Romans 8:28")
                                Text("• Psalm 23")
                                Text("• Matthew 5:3-12")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .navigationTitle("Add Scripture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingDetail) {
            if let reference = selectedReference {
                ScriptureDetailView(reference: reference)
            }
        }
    }
    
    private var popularScriptures: [String] {
        ["John 3:16", "Romans 8:28", "Philippians 4:13", "Psalm 23:1", "Matthew 28:19-20", "1 Corinthians 13:4-7"]
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSearching = true
        searchResults = []
        
        // Parse the search text into potential scripture references
        let scriptureAnalysis = ScriptureAnalysisService()
        let references = scriptureAnalysis.analyzeScriptureReferences(in: searchText)
        
        // Simulate search delay and return parsed references
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isSearching = false
            self.searchResults = references
        }
    }
    
    private func selectScripture(_ reference: ScriptureReference) {
        selectedReference = reference
        
        // Fetch the actual scripture content
        Task {
            do {
                let verse = try await bibleService.fetchVerse(reference: reference.displayText, bibleId: ApiBibleConfig.preferredBibleTranslationId)
                let content = verse.content
                
                await MainActor.run {
                    onSelection(reference, content)
                }
            } catch {
                print("Failed to fetch scripture: \(error)")
                // Fallback to placeholder content if fetch fails
                let placeholderContent = "Scripture content for \(reference.displayText) is currently unavailable."
                
                await MainActor.run {
                    onSelection(reference, placeholderContent)
                }
            }
        }
    }
}

// MARK: - Scripture Suggestion Row
struct ScriptureSuggestionRow: View {
    let reference: ScriptureReference
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(reference.displayText)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("Tap to preview and add to your notes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ScriptureSearchFAB { reference, content in
        print("Selected: \(reference.displayText)")
    }
}