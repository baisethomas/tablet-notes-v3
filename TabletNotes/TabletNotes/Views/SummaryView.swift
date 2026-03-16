import Foundation
import SwiftData
import SwiftUI

struct SummaryView: View {
    let serviceType: String
    let transcript: Transcript?
    let audioFileURL: URL?
    let sermonService: SermonService
    let noteService: NoteService
    var onNext: (() -> Void)?

    private let summaryService: any SummaryServiceProtocol

    @State private var title: String?
    @State private var summary: String?
    @State private var status = "idle"
    @State private var summaryTask: Task<Void, Never>?

    init(
        serviceType: String,
        transcript: Transcript?,
        audioFileURL: URL?,
        sermonService: SermonService,
        noteService: NoteService,
        summaryService: any SummaryServiceProtocol = SummaryService(),
        onNext: (() -> Void)? = nil
    ) {
        self.serviceType = serviceType
        self.transcript = transcript
        self.audioFileURL = audioFileURL
        self.sermonService = sermonService
        self.noteService = noteService
        self.summaryService = summaryService
        self.onNext = onNext
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView(
                    title: "Summary",
                    showLogo: true,
                    showSearch: false,
                    showSyncStatus: true,
                    showBack: false,
                    syncStatus: HeaderView.SyncStatus.synced
                )

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
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)

                            if let errorMessage = summary, errorMessage.hasPrefix("[Error]") {
                                Text(errorMessage.replacingOccurrences(of: "[Error] ", with: ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }

                            HStack(spacing: 12) {
                                Button("Retry") {
                                    requestSummary()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Basic Summary") {
                                    requestBasicSummary()
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
            requestSummary()
        }
        .onDisappear {
            summaryTask?.cancel()
            summaryTask = nil
        }
    }

    private func requestSummary() {
        let transcriptText = transcript?.text ?? ""
        startSummaryTask {
            try await summaryService.generateSummaryResult(for: transcriptText, type: serviceType)
        }
    }

    private func requestBasicSummary() {
        let transcriptText = transcript?.text ?? ""
        startSummaryTask {
            summaryService.generateBasicSummaryResult(for: transcriptText, type: serviceType)
        }
    }

    private func startSummaryTask(
        _ operation: @escaping @Sendable () async throws -> SummaryGenerationResult
    ) {
        summaryTask?.cancel()
        summaryTask = nil

        title = nil
        summary = nil
        status = "pending"

        summaryTask = Task {
            do {
                let result = try await operation()
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    title = result.title
                    summary = result.summary
                    status = "complete"
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                let errorMessage = summaryService.userFacingMessage(for: error)

                await MainActor.run {
                    title = nil
                    summary = errorMessage
                    status = "failed"
                }
            }
        }
    }

    private func saveSermonAndContinue() {
        guard status == "complete", let summaryText = summary else {
            onNext?()
            return
        }

        let sermonTitle = title ?? "Sermon on " + DateFormatter.localizedString(
            from: Date(),
            dateStyle: .medium,
            timeStyle: .short
        )
        let date = Date()
        let notes = noteService.currentNotes
        let summaryModel = Summary(title: sermonTitle, text: summaryText, type: serviceType, status: status)

        guard let audioFileURL else {
            print("[SummaryView] No audioFileURL provided!")
            return
        }

        print("[SummaryView] Saving sermon with audioFileURL: \(audioFileURL), transcript: \(transcript?.text.prefix(100) ?? "")...")

        guard let transcript else {
            print("[SummaryView] No transcript provided!")
            return
        }

        sermonService.saveSermon(
            title: sermonTitle,
            audioFileURL: audioFileURL,
            date: date,
            serviceType: serviceType,
            speaker: nil,
            transcript: transcript,
            notes: notes,
            summary: summaryModel
        )

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
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)

            if let popover = activityVC.popoverPresentationController {
                let bounds = window.bounds
                let isValidBounds = bounds.width > 0 && bounds.height > 0 &&
                    bounds.width.isFinite && bounds.height.isFinite &&
                    !bounds.width.isNaN && !bounds.height.isNaN

                if isValidBounds {
                    popover.sourceView = window
                    popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
                } else {
                    let viewBounds = rootViewController.view.bounds
                    let isValidViewBounds = viewBounds.width > 0 && viewBounds.height > 0 &&
                        viewBounds.width.isFinite && viewBounds.height.isFinite &&
                        !viewBounds.width.isNaN && !viewBounds.height.isNaN

                    if isValidViewBounds {
                        popover.sourceView = rootViewController.view
                        popover.sourceRect = CGRect(x: viewBounds.midX, y: viewBounds.midY, width: 0, height: 0)
                    } else {
                        popover.sourceView = rootViewController.view
                        popover.sourceRect = CGRect(x: 400, y: 400, width: 0, height: 0)
                    }
                }

                popover.permittedArrowDirections = []
            }

            rootViewController.present(activityVC, animated: true)
        }
    }
}

#Preview {
    SummaryView(
        serviceType: "Sermon",
        transcript: Transcript(text: "Sample transcript text..."),
        audioFileURL: nil,
        sermonService: SermonService(
            modelContext: try! ModelContext(
                ModelContainer(
                    for: Sermon.self,
                    Note.self,
                    Transcript.self,
                    Summary.self,
                    ProcessingJob.self,
                    TranscriptSegment.self
                )
            )
        ),
        noteService: NoteService()
    )
}
