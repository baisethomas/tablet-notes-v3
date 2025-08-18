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
                    
                    if status == "complete" {
                        HStack(spacing: 12) {
                            Button("Share Summary") {
                                shareSummary()
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Continue") {
                                saveSermonAndContinue()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        Button("Continue") {
                            saveSermonAndContinue()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea(edges: .bottom)
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

    private func saveSermonAndContinue() {
        guard let summaryText = summary else { onNext?(); return }
        let title = "Sermon on " + DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let date = Date()
        let notes = noteService.currentNotes // Use the current notes array from noteService
        let summaryModel = Summary(text: summaryText, type: serviceType, status: status)
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
    
    private func shareSummary() {
        guard let summaryText = summary else { return }
        
        let shareText = """
        AI Summary - \(serviceType)
        
        \(summaryText)
        
        Generated by TabletNotes
        """
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
            
            // Configure for iPad
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
}

#Preview {
    SummaryView(serviceType: "Sermon", transcript: Transcript(text: "Sample transcript text..."), audioFileURL: nil, sermonService: SermonService(modelContext: try! ModelContext(ModelContainer(for: Sermon.self))), noteService: NoteService())
}
