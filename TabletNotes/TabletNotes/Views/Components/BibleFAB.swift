import SwiftUI

struct AddScriptureSheet: View {
    let onSelection: (ScriptureReference, String) -> Void

    @StateObject private var bibleService = BibleAPIService()
    @State private var searchText = ""
    @State private var searchResults: [ScriptureReference] = []
    @State private var loadingReferenceID: String?
    @State private var errorMessage: String?
    @State private var showingBibleBrowser = false
    @Environment(\.dismiss) private var dismiss

    private let popularScriptures = [
        "John 3:16",
        "Romans 8:28",
        "Philippians 4:13",
        "Psalm 23:1",
        "Matthew 28:19-20",
        "1 Corinthians 13:4-7"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    searchField
                    quickReferences
                    searchResultsSection
                    browseButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color.SV.surface.ignoresSafeArea())
            .navigationTitle("Add Scripture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.SV.primary)
                }
            }
        }
        .sheet(isPresented: $showingBibleBrowser) {
            BibleBrowserView { reference, content in
                onSelection(reference, content)
                showingBibleBrowser = false
                dismiss()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "book.closed")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.SV.primary)
                .frame(width: 48, height: 48)
                .background(Color.SV.primary.opacity(0.08), in: Circle())

            Text("Find a verse")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(Color.SV.onSurface)

            Text("Type a reference, choose a common passage, or browse the Bible.")
                .font(.system(size: 14))
                .foregroundStyle(Color.SV.onSurface.opacity(0.58))
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.SV.onSurface.opacity(0.42))

            TextField("John 3:16", text: $searchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(performSearch)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                    errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear scripture search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.SV.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.SV.primary.opacity(0.10), lineWidth: 1)
        )
        .onChange(of: searchText) { _, newValue in
            errorMessage = nil
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResults = []
            }
        }
    }

    private var quickReferences: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMMON PASSAGES")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(Color.SV.onSurface.opacity(0.38))

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(popularScriptures, id: \.self) { scripture in
                        Button {
                            searchText = scripture
                            performSearch()
                        } label: {
                            Text(scripture)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.SV.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.SV.primary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color.SV.error)
                .padding(.vertical, 4)
        }

        if !searchResults.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("RESULTS")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.6)
                    .foregroundStyle(Color.SV.onSurface.opacity(0.38))

                VStack(spacing: 8) {
                    ForEach(searchResults) { reference in
                        ScriptureInsertRow(
                            reference: reference,
                            isLoading: loadingReferenceID == reference.id
                        ) {
                            insert(reference)
                        }
                    }
                }
            }
        } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Enter a full reference like John 3:16 or Matthew 5:3-12.")
                .font(.system(size: 13))
                .foregroundStyle(Color.SV.onSurface.opacity(0.45))
        }
    }

    private var browseButton: some View {
        Button {
            showingBibleBrowser = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 16, weight: .medium))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse Bible")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Choose translation, book, chapter, and verse.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.52))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.32))
            }
            .foregroundStyle(Color.SV.onSurface)
            .padding(16)
            .background(Color.SV.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func performSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let scriptureAnalysis = ScriptureAnalysisService()
        let references = scriptureAnalysis.analyzeScriptureReferences(in: trimmed)
        searchResults = references
        errorMessage = references.isEmpty ? "No scripture reference found." : nil
    }

    private func insert(_ reference: ScriptureReference) {
        loadingReferenceID = reference.id
        errorMessage = nil

        Task {
            do {
                let content: String
                if reference.isRange {
                    let passage = try await bibleService.fetchPassage(
                        reference: reference.displayText,
                        bibleId: ApiBibleConfig.preferredBibleTranslationId
                    )
                    content = cleanScriptureContent(passage.content)
                } else {
                    let verse = try await bibleService.fetchVerse(
                        reference: reference.displayText,
                        bibleId: ApiBibleConfig.preferredBibleTranslationId
                    )
                    content = cleanScriptureContent(verse.content)
                }

                await MainActor.run {
                    onSelection(reference, content)
                    loadingReferenceID = nil
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    loadingReferenceID = nil
                    errorMessage = "Unable to load \(reference.displayText): \(error.localizedDescription)"
                }
            }
        }
    }

    private func cleanScriptureContent(_ content: String) -> String {
        let cleanedContent = content
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(
                of: "(\\d+)([A-Za-z])",
                with: "$1 $2",
                options: .regularExpression
            )

        return cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ScriptureInsertRow: View {
    let reference: ScriptureReference
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reference.displayText)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.SV.onSurface)

                    Text("Tap to insert into notes")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.48))
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.SV.primary))
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.SV.primary)
                }
            }
            .padding(14)
            .background(Color.SV.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

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