import SwiftUI
import SwiftData
import Foundation
import Combine
import UIKit

// MARK: - Empty State Component
struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 64))
                    .foregroundColor(.adaptiveSecondaryText)
                    .opacity(0.6)
                
                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.adaptivePrimaryText)
                    
                    Text(subtitle)
                        .font(.body)
                        .foregroundColor(.adaptiveSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text(actionTitle)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.adaptiveAccent)
                    .cornerRadius(25)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.adaptiveBackground)
    }
}

// MARK: - Sermon Row Component
struct SermonRowView: View {
    let sermon: Sermon
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            VStack(alignment: .leading, spacing: 12) {
                // Title and date row
                HStack(alignment: .top) {
                    Text(sermon.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.adaptivePrimaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(sermon.date, style: .date)
                            .font(.caption)
                            .foregroundColor(.adaptiveSecondaryText)
                        
                        // Chevron moved to top right
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.adaptiveSecondaryText)
                    }
                }
                
                // Service type badge
                HStack {
                    Image(systemName: serviceTypeIcon)
                        .font(.caption)
                        .foregroundColor(.adaptiveAccent)
                    
                    Text(sermon.serviceType)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.adaptiveAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.adaptiveAccent.opacity(0.1))
                        .cornerRadius(8)
                    
                    Spacer()
                }
                
                // Summary key points or notes preview
                if let summary = sermon.summary, !summary.text.isEmpty, summary.status == "complete" {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb")
                                .font(.caption2)
                                .foregroundColor(.adaptiveAccent)
                            Text("Key Points")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.adaptiveAccent)
                        }
                        
                        Text(extractKeyPoints(from: summary.text))
                            .font(.subheadline)
                            .foregroundColor(.adaptiveSecondaryText)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                    }
                } else if !sermon.notes.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundColor(.adaptiveSecondaryText)
                        
                        Text("\(sermon.notes.count) note\(sermon.notes.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundColor(.adaptiveSecondaryText)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            // Status badges at bottom right
            HStack {
                Spacer()
                
                HStack(spacing: 8) {
                    StatusBadge(
                        title: "Transcript",
                        status: sermon.transcriptionStatus,
                        icon: "text.bubble"
                    )
                    
                    StatusBadge(
                        title: "Summary",
                        status: sermon.summaryStatus,
                        icon: "doc.text"
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color.sermonCardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.adaptiveBorder, lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0) {
            // Handle press state for visual feedback
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }
    
    private var serviceTypeIcon: String {
        switch sermon.serviceType.lowercased() {
        case "sermon", "service":
            return "church.fill"
        case "bible study":
            return "book.closed"
        case "prayer":
            return "hands.sparkles"
        case "worship":
            return "music.note"
        default:
            return "mic"
        }
    }
    
    private func extractKeyPoints(from summary: String) -> String {
        // Remove all markdown formatting first
        let cleanedSummary = removeMarkdownFormatting(from: summary)
        
        // Extract bullet points or key sentences
        let lines = cleanedSummary.components(separatedBy: .newlines)
        var keyPoints: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines
            if trimmed.isEmpty { continue }
            
            // Look for bullet points or numbered items
            if trimmed.hasPrefix("•") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || 
               trimmed.hasPrefix("1.") || trimmed.hasPrefix("2.") || trimmed.hasPrefix("3.") {
                var point = trimmed
                // Remove bullet/number prefix
                if trimmed.hasPrefix("•") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") {
                    point = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if trimmed.contains(".") {
                    let components = trimmed.components(separatedBy: ".")
                    if components.count > 1 {
                        point = components.dropFirst().joined(separator: ".").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                
                if !point.isEmpty && point.count > 10 {
                    keyPoints.append(point)
                }
            } else if trimmed.count > 20 && trimmed.count < 200 {
                // Include substantial lines that might be key points
                keyPoints.append(trimmed)
            }
        }
        
        // If no structured bullet points found, extract key sentences
        if keyPoints.isEmpty {
            let sentences = cleanedSummary.components(separatedBy: ". ")
            keyPoints = sentences
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 20 && $0.count < 200 }
                .prefix(4)
                .map { $0 }
        }
        
        // Return first 4 key points, formatted with bullets
        return keyPoints.prefix(4).map { "• \($0)" }.joined(separator: "\n")
    }
    
    private func removeMarkdownFormatting(from text: String) -> String {
        var cleaned = text
        
        // Remove common markdown patterns
        cleaned = cleaned.replacingOccurrences(of: "**", with: "") // Bold
        cleaned = cleaned.replacingOccurrences(of: "*", with: "") // Italic (but preserve bullet points)
        cleaned = cleaned.replacingOccurrences(of: "__", with: "") // Bold alternative
        cleaned = cleaned.replacingOccurrences(of: "_", with: "") // Italic alternative
        cleaned = cleaned.replacingOccurrences(of: "~~", with: "") // Strikethrough
        cleaned = cleaned.replacingOccurrences(of: "`", with: "") // Code
        cleaned = cleaned.replacingOccurrences(of: "###", with: "") // Headers
        cleaned = cleaned.replacingOccurrences(of: "##", with: "") // Headers
        cleaned = cleaned.replacingOccurrences(of: "#", with: "") // Headers
        
        // Remove links [text](url)
        let linkPattern = "\\[([^\\]]+)\\]\\([^\\)]+\\)"
        cleaned = cleaned.replacingOccurrences(of: linkPattern, with: "$1", options: .regularExpression)
        
        // Clean up extra whitespace
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
}

// MARK: - Status Badge Component
struct StatusBadge: View {
    let title: String
    let status: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(statusColor)
            
            if status == "processing" {
                ProgressView()
                    .scaleEffect(0.6)
                    .progressViewStyle(CircularProgressViewStyle(tint: statusColor))
            } else {
                Image(systemName: statusIcon)
                    .font(.caption2)
                    .foregroundColor(statusColor)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.1))
        .cornerRadius(6)
    }
    
    private var statusColor: Color {
        switch status {
        case "complete":
            return .green
        case "processing":
            return .orange
        case "failed":
            return .red
        default:
            return .gray
        }
    }
    
    private var statusIcon: String {
        switch status {
        case "complete":
            return "checkmark.circle.fill"
        case "failed":
            return "exclamationmark.triangle.fill"
        default:
            return "circle"
        }
    }
}

// MARK: - Section Header Component
struct SectionHeaderView: View {
    let title: String
    let count: Int
    
    var body: some View {
        HStack {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("(\(count))")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct SermonListView: View {
    @ObservedObject var sermonService: SermonService
    var onSermonSelected: (Sermon) -> Void
    var onSettings: (() -> Void)? = nil
    var onStartRecording: (() -> Void)? = nil
    
    @State private var isLoading = true
    @State private var showingDeleteAlert = false
    @State private var sermonToDelete: Sermon?
    @State private var sortOrder: SortOrder = .newestFirst
    @State private var showingSortOptions = false
    @State private var showingSearch = false
    
    enum SortOrder: String, CaseIterable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case titleAZ = "Title A-Z"
        case titleZA = "Title Z-A"
    }
    
    private var sortedSermons: [Sermon] {
        // Use filtered sermons from SermonService if search is active, otherwise use all sermons
        let sermonsToSort = sermonService.searchText.isEmpty ? sermonService.sermons : sermonService.filteredSermons
        
        switch sortOrder {
        case .newestFirst:
            return sermonsToSort.sorted(by: { $0.date > $1.date })
        case .oldestFirst:
            return sermonsToSort.sorted(by: { $0.date < $1.date })
        case .titleAZ:
            return sermonsToSort.sorted(by: { $0.title < $1.title })
        case .titleZA:
            return sermonsToSort.sorted(by: { $0.title > $1.title })
        }
    }
    
    private var groupedSermons: [(String, [Sermon])] {
        let grouped = Dictionary(grouping: sortedSermons) { sermon in
            DateFormatter.localizedString(from: sermon.date, dateStyle: .medium, timeStyle: .none)
        }
        
        return grouped.sorted { first, second in
            switch sortOrder {
            case .newestFirst:
                return first.value.first?.date ?? Date() > second.value.first?.date ?? Date()
            case .oldestFirst:
                return first.value.first?.date ?? Date() < second.value.first?.date ?? Date()
            case .titleAZ, .titleZA:
                return first.key < second.key
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom header with left-aligned title and filter button
                HStack {
                    HStack(spacing: 8) {
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                        
                        Text("Sermons")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    

                    
                    // Search button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingSearch.toggle()
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    
                    // Sync status indicator
                    Button(action: {
                        // Show sync status or trigger manual sync
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }) {
                        Image(systemName: "checkmark.icloud")
                            .font(.title3)
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.adaptiveBackground)
                
                // Search bar (when visible)
                if showingSearch {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            
                            TextField("Search sermons, speakers, content...", text: $sermonService.searchText)
                                .textFieldStyle(PlainTextFieldStyle())
                            
                            if !sermonService.searchText.isEmpty {
                                Button("Clear") {
                                    sermonService.clearSearch()
                                }
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.adaptiveSecondaryBackground)
                        .cornerRadius(10)
                        
                        // Search results summary
                        if !sermonService.searchText.isEmpty {
                            HStack {
                                Text("\(sermonService.filteredSermons.count) result(s) found")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .background(Color.adaptiveBackground)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                if isLoading {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .progressViewStyle(CircularProgressViewStyle(tint: .adaptiveAccent))
                        
                        Text("Loading sermons...")
                            .font(.headline)
                            .foregroundColor(.adaptiveSecondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        // Simulate loading delay for smooth UX
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isLoading = false
                            }
                        }
                    }
                } else if sermonService.sermons.isEmpty {
                    // Empty state when no sermons exist
                    EmptyStateView(
                        title: "No Sermons Yet",
                        subtitle: "Start recording your first sermon to see it here. Your recordings will be automatically transcribed and summarized.",
                        systemImage: "mic.circle",
                        actionTitle: "Start Recording",
                        action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            onStartRecording?()
                        }
                    )
                } else if !sermonService.searchText.isEmpty && sermonService.filteredSermons.isEmpty {
                    // Empty state when search returns no results
                    EmptyStateView(
                        title: "No Results Found",
                        subtitle: "Try adjusting your search terms or clearing the search to see all sermons.",
                        systemImage: "magnifyingglass",
                        actionTitle: "Clear Search",
                        action: {
                            sermonService.clearSearch()
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    )
                } else {
                    // Sermons list using List for proper swipe actions
                    VStack(spacing: 0) {
                        // Sort indicator with sort button
                        HStack {
                            Text("Sorted by: \(sortOrder.rawValue)")
                                .font(.caption)
                                .foregroundColor(.adaptiveSecondaryText)
                            Spacer()
                            let displayCount = sermonService.searchText.isEmpty ? sermonService.sermons.count : sermonService.filteredSermons.count
                            Text("\(displayCount) sermon\(displayCount == 1 ? "" : "s")\(sermonService.searchText.isEmpty ? "" : " found")")
                                .font(.caption)
                                .foregroundColor(.adaptiveSecondaryText)
                            
                            // Sort button
                            Button(action: {
                                showingSortOptions = true
                            }) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.caption)
                                    .foregroundColor(.adaptiveAccent)
                                    .padding(.leading, 8)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.adaptiveBackground)
                        
                                                 // Native List for proper swipe actions
                List {
                             ForEach(Array(groupedSermons.enumerated()), id: \.element.0) { index, element in
                                 let (dateString, sermons) = element
                                 
                        Section(header:
                                     HStack {
                                         Text(dateString)
                                .font(.headline)
                                             .fontWeight(.semibold)
                                             .foregroundColor(.adaptivePrimaryText)
                                         
                                         Spacer()
                                         
                                         Text("\(sermons.count)")
                                             .font(.caption)
                                             .foregroundColor(.adaptiveSecondaryText)
                                             .padding(.horizontal, 8)
                                             .padding(.vertical, 8)
                                             .background(Color.adaptiveInputBackground)
                                             .cornerRadius(8)
                                     }
                                     .padding(.vertical, 2)
                                 ) {
                                    ForEach(sermons) { sermon in
                                        SermonRowView(sermon: sermon) {
                                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                            impactFeedback.impactOccurred()
                                            onSermonSelected(sermon)
                                        }
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                        .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            // Delete action (right swipe)
                                    Button(role: .destructive) {
                                                sermonToDelete = sermon
                                                showingDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                            // Archive/Unarchive action (left swipe)
                                            Button {
                                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                                impactFeedback.impactOccurred()
                                                sermonService.toggleSermonArchiveStatus(sermon)
                                            } label: {
                                                Label(
                                                    sermon.isArchived ? "Unarchive" : "Archive",
                                                    systemImage: sermon.isArchived ? "tray.and.arrow.up" : "tray.and.arrow.down"
                                                )
                                            }
                                            .tint(sermon.isArchived ? .green : .orange)
                                        }
                                        .contextMenu {
                                            Button(action: {
                                                onSermonSelected(sermon)
                                            }) {
                                                Label("View Details", systemImage: "eye")
                                            }
                                            
                                            Button(action: {
                                                sermonService.toggleSermonArchiveStatus(sermon)
                                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                                impactFeedback.impactOccurred()
                                            }) {
                                                Label(
                                                    sermon.isArchived ? "Unarchive" : "Archive",
                                                    systemImage: sermon.isArchived ? "tray.and.arrow.up" : "tray.and.arrow.down"
                                                )
                                            }
                                            
                                            // Regenerate Summary option (only show if summary failed or is processing)
                                            if let summary = sermon.summary, (summary.status == "failed" || summary.status == "processing") {
                                                Button(action: {
                                                    regenerateSummary(for: sermon)
                                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                                    impactFeedback.impactOccurred()
                                                }) {
                                                    Label("Regenerate Summary", systemImage: "arrow.clockwise")
                                                }
                                            }
                                            
                                            Button(action: {
                                                // Share functionality
                                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                                impactFeedback.impactOccurred()
                                            }) {
                                                Label("Share", systemImage: "square.and.arrow.up")
                                            }
                                            
                                            Divider()
                                            
                                            Button(role: .destructive, action: {
                                                sermonToDelete = sermon
                                                showingDeleteAlert = true
                                            }) {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                    
                                                                         // Add divider after each section (except the last one)
                                     if index < groupedSermons.count - 1 {
                                         Rectangle()
                                             .fill(Color(.systemGray4))
                                             .frame(height: 0.5)
                                             .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                                             .listRowBackground(Color.clear)
                                             .listRowSeparator(.hidden)
                                     }
                                }
                            }
                                                 }
                         .listStyle(PlainListStyle())
                         .scrollContentBackground(.hidden)
                         .background(Color.adaptiveBackground)
                         .listSectionSeparator(.hidden)
                        .refreshable {
                            // Add haptic feedback for refresh
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            
                            // Simulate refresh delay
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            sermonService.fetchSermons()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .alert("Delete Sermon", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let sermon = sermonToDelete {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            sermonService.deleteSermon(sermon)
                        }
                        
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    }
                }
            } message: {
                Text("Are you sure you want to delete this sermon? This action cannot be undone.")
            }
            .actionSheet(isPresented: $showingSortOptions) {
                ActionSheet(
                    title: Text("Sort Sermons"),
                    message: Text("Choose how to organize your sermons"),
                    buttons: SortOrder.allCases.map { order in
                        ActionSheet.Button.default(
                            Text(order.rawValue + (sortOrder == order ? " ✓" : "")),
                            action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    sortOrder = order
                                }
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }
                        )
                    } + [ActionSheet.Button.cancel()]
                )
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - Helper Methods
    private func regenerateSummary(for sermon: Sermon) {
        guard let transcript = sermon.transcript, !transcript.text.isEmpty else {
            print("Cannot regenerate summary: No transcript available")
            return
        }
        
        // Create a new SummaryService instance for the retry
        let summaryService = SummaryService()
        
        // Update sermon summary status to processing
        if let existingSummary = sermon.summary {
            existingSummary.status = "processing"
        } else {
            let newSummary = Summary(text: "", type: sermon.serviceType, status: "processing")
            sermon.summary = newSummary
        }
        
        // Save the updated status
        sermonService.saveSermon(
            title: sermon.title,
            audioFileURL: sermon.audioFileURL,
            date: sermon.date,
            serviceType: sermon.serviceType,
            speaker: sermon.speaker,
            transcript: sermon.transcript,
            notes: sermon.notes,
            summary: sermon.summary,
            transcriptionStatus: sermon.transcriptionStatus,
            summaryStatus: "processing",
            isArchived: sermon.isArchived,
            id: sermon.id
        )
        
        // Regenerate the summary
        summaryService.generateSummary(for: transcript.text, type: sermon.serviceType)
        
        // Listen for the result
        summaryService.statusPublisher
            .sink { status in
                if status == "complete" || status == "failed" {
                    // Update the sermon with the new summary
                    summaryService.summaryPublisher
                        .sink { summaryText in
                            if let summaryText = summaryText, let existingSummary = sermon.summary {
                                existingSummary.text = summaryText
                                existingSummary.status = status
                                
                                sermonService.saveSermon(
                                    title: sermon.title,
                                    audioFileURL: sermon.audioFileURL,
                                    date: sermon.date,
                                    serviceType: sermon.serviceType,
                                    speaker: sermon.speaker,
                                    transcript: sermon.transcript,
                                    notes: sermon.notes,
                                    summary: existingSummary,
                                    transcriptionStatus: sermon.transcriptionStatus,
                                    summaryStatus: status,
                                    isArchived: sermon.isArchived,
                                    id: sermon.id
                                )
                            }
                        }
                        .store(in: &cancellables)
                }
            }
            .store(in: &cancellables)
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}

#Preview {
    SermonListView(sermonService: SermonService(modelContext: try! ModelContext(ModelContainer(for: Sermon.self))), onSermonSelected: { _ in }, onStartRecording: { })
}
