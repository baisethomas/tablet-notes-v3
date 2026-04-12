import SwiftUI
import SwiftData
import Foundation
import Combine
import UIKit

// MARK: - Empty State

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.22))

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.SV.onSurface)

                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.SV.primary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.SV.primary.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.SV.surface)
    }
}

// MARK: - Sermon Row

struct SermonRowView: View {
    let sermon: Sermon
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(sermon.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.45))

                Text(sermon.title)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(Color.SV.onSurface)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let preview = previewText {
                    Text(preview)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var previewText: String? {
        if let preview = sermon.summaryPreviewText, !preview.isEmpty {
            return preview
        }
        return sermon.notes.first?.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Sermon List View

struct SermonListView: View {
    @Bindable var sermonService: SermonService
    var onSermonSelected: (Sermon) -> Void
    var onSettings: (() -> Void)? = nil
    var onStartRecording: (() -> Void)? = nil

    @State private var isLoading = true
    @State private var showingDeleteAlert = false
    @State private var sermonToDelete: Sermon?
    @State private var sortOrder: SortOrder = .newestFirst
    @State private var showingSortOptions = false
    @State private var showingSearch = false
    @State private var cancellables = Set<AnyCancellable>()

    enum SortOrder: String, CaseIterable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case titleAZ = "Title A–Z"
        case titleZA = "Title Z–A"
    }

    // MARK: - Computed Data

    private var sortedSermons: [Sermon] {
        let base = sermonService.searchText.isEmpty
            ? sermonService.sermons
            : sermonService.filteredSermons
        switch sortOrder {
        case .newestFirst: return base.sorted { $0.date > $1.date }
        case .oldestFirst: return base.sorted { $0.date < $1.date }
        case .titleAZ:     return base.sorted { $0.title < $1.title }
        case .titleZA:     return base.sorted { $0.title > $1.title }
        }
    }

    /// Groups sermons by "MONTH YEAR" (e.g. "FEBRUARY 2026").
    private var groupedSermons: [(String, [Sermon])] {
        let grouped = Dictionary(grouping: sortedSermons) { sermon in
            sermon.date.formatted(.dateTime.month(.wide).year()).uppercased()
        }
        return grouped.sorted { a, b in
            let aDate = a.value.first?.date ?? .distantPast
            let bDate = b.value.first?.date ?? .distantPast
            switch sortOrder {
            case .newestFirst, .titleZA: return aDate > bDate
            case .oldestFirst, .titleAZ: return aDate < bDate
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            svListHeader

            if showingSearch {
                svSearchBar
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Group {
                if isLoading {
                    svLoadingState
                } else if sermonService.sermons.isEmpty {
                    svFirstRecordingPrompt
                } else if !sermonService.searchText.isEmpty && sermonService.filteredSermons.isEmpty {
                    EmptyStateView(
                        title: "No results",
                        subtitle: "Try different search terms.",
                        systemImage: "magnifyingglass",
                        actionTitle: "Clear Search",
                        action: { sermonService.clearSearch() }
                    )
                } else {
                    svSermonList
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isLoading)
        }
        .background(Color.SV.surface.ignoresSafeArea())
        .alert("Delete Sermon", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let sermon = sermonToDelete {
                    withAnimation { sermonService.deleteSermon(sermon) }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .confirmationDialog("Sort by", isPresented: $showingSortOptions, titleVisibility: .visible) {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Button(order.rawValue + (sortOrder == order ? " ✓" : "")) {
                    withAnimation { sortOrder = order }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var svListHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ARCHIVE")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Color.SV.onSurface.opacity(0.4))

                Text("The Word")
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .foregroundStyle(Color.SV.onSurface)
            }

            Spacer()

            HStack(spacing: 20) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showingSearch.toggle() }
                } label: {
                    Image(systemName: showingSearch ? "magnifyingglass.circle.fill" : "magnifyingglass")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.55))
                }

                Button { showingSortOptions = true } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color.SV.surface)
    }

    // MARK: - First Recording Prompt

    private var svFirstRecordingPrompt: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 40) {
                // Decorative icon block
                VStack(spacing: 16) {
                    Rectangle()
                        .fill(Color.SV.primary.opacity(0.15))
                        .frame(width: 44, height: 1)

                    Image(systemName: "mic")
                        .font(.system(size: 52, weight: .ultraLight))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.18))

                    Rectangle()
                        .fill(Color.SV.primary.opacity(0.15))
                        .frame(width: 44, height: 1)
                }

                // Text block
                VStack(spacing: 10) {
                    Text("Every sermon,\nremembered.")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(Color.SV.onSurface)
                        .multilineTextAlignment(.center)

                    Text("Record, transcribe, and revisit\nthe Word — all in one place.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                // CTA
                Button {
                    onStartRecording?()
                } label: {
                    Text("Start Your First Recording")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 13)
                        .background(Color.SV.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.SV.surface)
    }

    // MARK: - Search Bar

    private var svSearchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.35))

                TextField("Search sermons...", text: $sermonService.searchText)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.SV.onSurface)

                if !sermonService.searchText.isEmpty {
                    Button("Clear") { sermonService.clearSearch() }
                        .font(.system(size: 13))
                        .foregroundStyle(Color.SV.primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.SV.surfaceContainerLow)
            .clipShape(.rect(cornerRadius: 8))

            if !sermonService.searchText.isEmpty {
                Text("\(sermonService.filteredSermons.count) result\(sermonService.filteredSermons.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.35))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(Color.SV.surface)
    }

    // MARK: - Sermon List

    private var svSermonList: some View {
        List {
            ForEach(groupedSermons, id: \.0) { monthYear, sermons in
                Section {
                    ForEach(sermons) { sermon in
                        SermonRowView(sermon: sermon) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onSermonSelected(sermon)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.SV.surface)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                sermonToDelete = sermon
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                            Button { onSermonSelected(sermon) } label: {
                                Label("View Details", systemImage: "eye")
                            }
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                sermonService.toggleSermonArchiveStatus(sermon)
                            } label: {
                                Label(
                                    sermon.isArchived ? "Unarchive" : "Archive",
                                    systemImage: sermon.isArchived ? "tray.and.arrow.up" : "tray.and.arrow.down"
                                )
                            }
                            if sermon.summaryStatus == "failed" || sermon.summaryStatus == "processing" {
                                Button { regenerateSummary(for: sermon) } label: {
                                    Label("Regenerate Summary", systemImage: "arrow.clockwise")
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                sermonToDelete = sermon
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    svMonthHeader(monthYear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.SV.surface)
        .listSectionSeparator(.hidden)
        .refreshable {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            await SermonProcessingCoordinator.shared.triggerManualSync()
            sermonService.fetchSermons()
        }
    }

    // MARK: - Section Header

    private func svMonthHeader(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Color.SV.onSurface.opacity(0.4))

            Rectangle()
                .fill(Color.SV.onSurface.opacity(0.12))
                .frame(height: 0.5)
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .padding(.vertical, 6)
    }

    // MARK: - Loading State

    private var svLoadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.SV.primary.opacity(0.5))
            Text("Loading...")
                .font(.system(size: 13))
                .foregroundStyle(Color.SV.onSurface.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.SV.surface)
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation { isLoading = false }
        }
    }

    // MARK: - Helpers

    private func regenerateSummary(for sermon: Sermon) {
        guard let transcript = sermon.transcript, !transcript.text.isEmpty else {
            print("[SermonListView] Cannot regenerate summary: no transcript")
            return
        }
        sermonService.generateSummaryForSermon(
            sermonId: sermon.id,
            transcript: transcript.text,
            serviceType: sermon.serviceType
        )
    }
}

// MARK: - Preview

#Preview {
    SermonListView(
        sermonService: SermonService(
            modelContext: try! ModelContext(ModelContainer(
                for: Sermon.self, Note.self, Transcript.self, Summary.self,
                ProcessingJob.self, TranscriptSegment.self
            ))
        ),
        onSermonSelected: { _ in },
        onStartRecording: {}
    )
}
