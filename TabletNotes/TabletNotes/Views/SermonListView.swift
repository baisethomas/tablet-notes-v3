import SwiftUI
import SwiftData

struct SermonListView: View {
    @ObservedObject var sermonService: SermonService
    var onBack: (() -> Void)?
    var onSermonTap: ((Sermon) -> Void)?

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView(title: "Past Sermons", showLogo: true, showSearch: false, showSettings: true, onSettings: onBack)
                Spacer(minLength: 0)
                List(sermonService.sermons) { sermon in
                    Button(action: { onSermonTap?(sermon) }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sermon.title)
                                .font(.headline)
                            Text(sermon.date, style: .date)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(sermon.serviceType)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    SermonListView(sermonService: SermonService(modelContext: try! ModelContext(ModelContainer(for: Sermon.self))))
} 