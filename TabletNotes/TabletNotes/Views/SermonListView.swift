import SwiftUI
import SwiftData

struct SermonListView: View {
    @ObservedObject var sermonService: SermonService
    var onBack: (() -> Void)?
    var onSermonTap: ((Sermon) -> Void)?

    // Group sermons by start of day
    var groupedSermons: [Date: [Sermon]] {
        Dictionary(grouping: sermonService.sermons) { Calendar.current.startOfDay(for: $0.date) }
    }
    var sortedDates: [Date] {
        groupedSermons.keys.sorted(by: >)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView(title: "Messages", showLogo: true, showSearch: true, showSettings: true, showBack: false, onSettings: onBack)
                Spacer(minLength: 0)
                List {
                    ForEach(sortedDates, id: \..self) { date in
                        Section(header:
                            Text(sectionHeader(for: date))
                                .font(.headline)
                                .foregroundColor(.gray)
                                .padding(.leading)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        ) {
                            ForEach(groupedSermons[date] ?? []) { sermon in
                                SermonCardView(sermon: sermon)
                                    .onTapGesture {
                                        onSermonTap?(sermon)
                                    }
                                    .padding(.horizontal, 16)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listStyle(.plain)
                                .listRowBackground(Color.white)
                                .background(Color.white)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        sermonService.deleteSermon(sermon)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .listRowBackground(Color.white)
                .background(Color.white)
                .padding(.bottom, 80)
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    func sectionHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            return formatter.string(from: date)
        }
    }
}

struct SermonCardView: View {
    let sermon: Sermon

    // Extract up to 4 lines from the Key Points section of the summary
    func extractKeyPoints(from summary: String?) -> [String] {
        guard let summary = summary else { return [] }
        let clean = summary.replacingOccurrences(of: "**", with: "")
        guard let keyPointsRange = clean.range(of: "Key Points:") else { return [] }
        let afterKeyPoints = clean[keyPointsRange.upperBound...]
        // Find the next section (starts with a line ending with ':')
        let nextSectionRange = afterKeyPoints.range(of: ":\n", options: .regularExpression)
        let keyPointsText = nextSectionRange != nil
            ? String(afterKeyPoints[..<nextSectionRange!.lowerBound])
            : String(afterKeyPoints)
        // Split into lines, filter for non-empty, and trim
        return keyPointsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sermon.title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(formattedDate)
                Text("•")
                Text(formattedDuration)
                Text("• \(sermon.serviceType)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            // Show up to 4 key points
            let keyPoints = extractKeyPoints(from: sermon.summary?.text)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(keyPoints.prefix(4), id: \.self) { point in
                    Text(point)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.07), radius: 4, x: 0, y: 2)
        )
        .padding(.vertical, 4)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: sermon.date)
    }

    var formattedDuration: String {
        // If you have a duration property, use it. Otherwise, leave blank or estimate.
        // For now, we'll use transcript length as a proxy if available.
        if let transcript = sermon.transcript, !transcript.text.isEmpty {
            let wordCount = transcript.text.split(separator: " ").count
            let minutes = max(1, wordCount / 150) // Roughly 150 wpm
            return "\(minutes) min"
        }
        return ""
    }
}

#Preview {
    SermonListView(sermonService: SermonService(modelContext: try! ModelContext(ModelContainer(for: Sermon.self))))
}
