import SwiftUI
import Combine
import SwiftData
import Foundation
// Import models
// If your project supports module imports, try:
// import TabletNotes.Models
// import TabletNotes.Services
// Otherwise, ensure all these files are in the same target.
// Import HeaderView if needed

struct SummaryView: View {
    let serviceType: String
    let transcript: Transcript?
    let audioFileURL: URL?
    let sermonService: SermonService
    let noteService: NoteService
    var onNext: (() -> Void)?
    @StateObject private var summaryService = SummaryService()
    @State private var summary: String? = nil
    @State private var status: String = "idle"
    @State private var cancellables = Set<AnyCancellable>()
    @State private var refreshCount: Int = 0
    @State private var userTier: String = "free" // Default to free tier
    @State private var showingRefreshLimit = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView(title: "Summary", showLogo: true, showSearch: false, showSyncStatus: true, showBack: false, syncStatus: HeaderView.SyncStatus.synced)
                Spacer(minLength: 0)
                VStack(spacing: 24) {
                    if status == "pending" {
                        ProgressView("Generating summary...")
                    } else if status == "complete" {
                        ScrollView {
                            VStack(spacing: 16) {
                                SummaryTextView(
                                    summaryText: summary ?? "",
                                    serviceType: serviceType
                                )
                                .padding(.horizontal)
                                
                                // DEBUG: Refresh button section - THIS SHOULD BE VISIBLE
                                VStack(spacing: 12) {
                                    // Debug info
                                    Text("DEBUG: Refresh Section - Status: \(status), Count: \(refreshCount), Tier: \(userTier)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(.horizontal)
                                    
                                    // Prominent refresh button
                                    VStack(spacing: 8) {
                                        Button {
                                            refreshSummary()
                                        } label: {
                                            HStack {
                                                Image(systemName: "arrow.clockwise")
                                                Text("Refresh Summary")
                                            }
                                            .padding()
                                            .frame(maxWidth: .infinity)
                                        }
                                        .disabled(!summaryService.canRefreshSummary(currentRefreshCount: refreshCount, userTier: userTier))
                                        .buttonStyle(.borderedProminent)
                                        .padding(.horizontal)
                                        
                                        let remaining = summaryService.getRemainingRefreshes(currentRefreshCount: refreshCount, userTier: userTier)
                                        Text("\(remaining) refreshes left today")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        if !summaryService.canRefreshSummary(currentRefreshCount: refreshCount, userTier: userTier) {
                                            Text("Daily refresh limit reached. Upgrade for more refreshes.")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal)
                                        }
                                    }
                                    .padding()
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.bottom, 100)
                        }
                    } else if status == "failed" {
                        VStack(spacing: 16) {
                            Text("Failed to generate summary.")
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                            
                            if let errorMessage = summary, errorMessage.hasPrefix("[Error]") {
                                Text(errorMessage.replacingOccurrences(of: "[Error] ", with: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            
                            HStack(spacing: 12) {
                                Button("Retry") {
                                    summaryService.retrySummary(for: transcript?.text ?? "", type: serviceType)
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Button("Basic Summary") {
                                    summaryService.generateBasicSummary(for: transcript?.text ?? "", type: serviceType)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    Button("Continue") {
                        saveSermonAndContinue()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .alert("Refresh Limit Reached", isPresented: $showingRefreshLimit) {
            Button("OK", role: .cancel) { }
            Button("Upgrade") {
                // TODO: Navigate to subscription/upgrade screen
            }
        } message: {
            Text("You've reached your daily refresh limit. Upgrade your subscription to get more refreshes per day.")
        }
        .onAppear {
            summaryService.generateSummary(for: transcript?.text ?? "", type: serviceType)
            summaryService.summaryPublisher
                .receive(on: RunLoop.main)
                .sink { value in
                    summary = value
                }
                .store(in: &cancellables)
            summaryService.statusPublisher
                .receive(on: RunLoop.main)
                .sink { value in
                    status = value
                }
                .store(in: &cancellables)
        }
    }

    private func refreshSummary() {
        guard let transcript = transcript else { return }
        
        // Check if refresh is allowed
        if !summaryService.canRefreshSummary(currentRefreshCount: refreshCount, userTier: userTier) {
            showingRefreshLimit = true
            return
        }
        
        // Call the refresh endpoint
        summaryService.refreshSummary(for: transcript.text, type: serviceType)
        
        // Increment refresh count
        refreshCount += 1
    }
    
    private func saveSermonAndContinue() {
        guard let summaryText = summary else { onNext?(); return }
        let title = "Sermon on " + DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let date = Date()
        let notes = noteService.currentNotes // Use the current notes array from noteService
        let summaryModel = Summary(text: summaryText, type: serviceType, status: status, refreshCount: refreshCount, lastRefreshedAt: refreshCount > 0 ? Date() : nil)
        guard let audioFileURL = audioFileURL else {
            print("[SummaryView] No audioFileURL provided!")
            return
        }
        print("[SummaryView] Saving sermon with audioFileURL: \(audioFileURL), transcript: \(transcript?.text.prefix(100) ?? "")...")
        guard let transcript = transcript else {
            print("[SummaryView] No transcript provided!")
            return
        }
        sermonService.saveSermon(title: title, audioFileURL: audioFileURL, date: date, serviceType: serviceType, speaker: nil, transcript: transcript, notes: notes, summary: summaryModel)
        
        // Clear the session notes after successfully saving to sermon
        noteService.clearSession()
        
        onNext?()
    }
}

#Preview {
    SummaryView(serviceType: "Sermon", transcript: Transcript(text: "Sample transcript text..."), audioFileURL: nil, sermonService: SermonService(modelContext: try! ModelContext(ModelContainer(for: Sermon.self))), noteService: NoteService())
}
