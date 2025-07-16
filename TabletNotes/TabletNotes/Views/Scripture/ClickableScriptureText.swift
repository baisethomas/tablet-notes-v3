import SwiftUI

struct ClickableScriptureText: View {
    let text: String
    let font: Font
    let lineSpacing: CGFloat
    @StateObject private var scriptureAnalyzer = ScriptureAnalysisService()
    @State private var detectedReferences: [ScriptureReference] = []
    
    init(text: String, font: Font = .body, lineSpacing: CGFloat = 4) {
        self.text = text
        self.font = font
        self.lineSpacing = lineSpacing
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main text with highlighted references
            textWithClickableReferences
            
            // Scripture reference chips
            if !detectedReferences.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scripture References")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading, spacing: 8) {
                        ForEach(detectedReferences) { reference in
                            ScriptureReferenceButton(reference: reference)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .onAppear {
            analyzeReferences()
        }
        .onChange(of: text) { _, _ in
            analyzeReferences()
        }
    }
    
    private var textWithClickableReferences: some View {
        Text(createAttributedText())
            .font(font)
            .lineSpacing(lineSpacing)
            .textSelection(.enabled)
    }
    
    private func createAttributedText() -> AttributedString {
        var attributedString = AttributedString(text)
        
        // Apply base styling
        attributedString.font = UIFont.systemFont(ofSize: 16)
        attributedString.foregroundColor = UIColor.label
        
        // Highlight scripture references
        for reference in detectedReferences {
            if let range = attributedString.range(of: reference.raw) {
                attributedString[range].foregroundColor = UIColor.systemBlue
                attributedString[range].font = UIFont.systemFont(ofSize: 16, weight: .medium)
                attributedString[range].underlineStyle = .single
                attributedString[range].underlineColor = UIColor.systemBlue.withAlphaComponent(0.5)
            }
        }
        
        return attributedString
    }
    
    private func analyzeReferences() {
        detectedReferences = scriptureAnalyzer.analyzeScriptureReferences(in: text)
    }
}

// MARK: - Enhanced Summary Text View
struct SummaryTextView: View {
    let summaryText: String
    let serviceType: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.accentColor)
                Text("AI Summary")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text(serviceType)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
            
            ClickableScriptureText(
                text: summaryText,
                font: .body,
                lineSpacing: 6
            )
        }
        .padding()
        // Removed background, cornerRadius, and shadow for a flat look
    }
}

#Preview {
    VStack {
        SummaryTextView(
            summaryText: "In this sermon, we explored the profound truth of John 3:16, which speaks of God's love for the world. The passage reminds us that salvation comes through faith, as mentioned in Ephesians 2:8-9. We also looked at Romans 8:28 and how God works all things together for good.",
            serviceType: "Sunday Service"
        )
        .padding()
        
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}