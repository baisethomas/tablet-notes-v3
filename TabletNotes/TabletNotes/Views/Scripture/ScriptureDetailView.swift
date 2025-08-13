import SwiftUI

struct ScriptureDetailView: View {
    let reference: ScriptureReference
    @StateObject private var bibleService = BibleAPIService()
    @State private var scriptureContent: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedBibleVersion = ApiBibleConfig.defaultBibleId
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Reference Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "book.closed.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                            
                            Text(reference.displayText)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        
                        if !getEnglishBibles().isEmpty {
                            Menu {
                                ForEach(getEnglishBibles()) { bible in
                                    Button(action: {
                                        selectedBibleVersion = bible.id
                                        loadScripture()
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
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(getCurrentBibleName())
                                        .font(.caption)
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
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    Divider()
                    
                    // Scripture Content
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                            
                            Text("Loading scripture...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if let errorMessage = errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            
                            Text("Unable to Load Scripture")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Try Again") {
                                loadScripture()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(scriptureContent)
                                .font(.body)
                                .lineSpacing(6)
                                .textSelection(.enabled)
                                .padding()
                                .background(Color(.systemGray6).opacity(0.5))
                                .cornerRadius(12)
                            
                            // Action Buttons
                            HStack(spacing: 12) {
                                Button(action: shareScripture) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("Share")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                
                                Button(action: copyToClipboard) {
                                    HStack {
                                        Image(systemName: "doc.on.doc")
                                        Text("Copy")
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(8)
                                }
                                
                                Spacer()
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Scripture")
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
            loadScripture()
        }
    }
    
    // MARK: - Private Methods
    
    private func loadScripture() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let content: String
                if reference.isRange {
                    let passage = try await bibleService.fetchPassage(
                        reference: reference.displayText,
                        bibleId: selectedBibleVersion
                    )
                    content = cleanScriptureContent(passage.content)
                } else {
                    let verse = try await bibleService.fetchVerse(
                        reference: reference.displayText,
                        bibleId: selectedBibleVersion
                    )
                    content = cleanScriptureContent(verse.content)
                }
                
                await MainActor.run {
                    scriptureContent = content
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Unable to load scripture: \(error.localizedDescription)"
                    isLoading = false
                    
                    // For development, show a placeholder
                    scriptureContent = "This scripture is currently unavailable. Please check your internet connection or try again later."
                }
            }
        }
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
    
    private func getCurrentBibleName() -> String {
        if let bible = getEnglishBibles().first(where: { $0.id == selectedBibleVersion }) {
            return bible.abbreviation
        }
        return "KJV"
    }
    
    private func getEnglishBibles() -> [Bible] {
        // NetlifyBibleAPIService provides available Bibles
        return bibleService.availableBibles
    }
    
    private func shareScripture() {
        let shareText = "\(reference.displayText)\n\n\(scriptureContent)"
        let activityController = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityController, animated: true)
        }
    }
    
    private func copyToClipboard() {
        let clipboardText = "\(reference.displayText)\n\n\(scriptureContent)"
        UIPasteboard.general.string = clipboardText
        
        // Could add a toast notification here
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

// MARK: - Scripture Reference Button Component
struct ScriptureReferenceButton: View {
    let reference: ScriptureReference
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: {
            showingDetail = true
        }) {
            Text(reference.displayText)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
        }
        .sheet(isPresented: $showingDetail) {
            ScriptureDetailView(reference: reference)
        }
    }
}

#Preview {
    ScriptureDetailView(reference: ScriptureReference(
        book: "John",
        chapter: 3,
        verseStart: 16,
        verseEnd: nil,
        raw: "John 3:16"
    ))
}