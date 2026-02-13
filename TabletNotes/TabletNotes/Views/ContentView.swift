//
//  ContentView.swift
//  TabletNotes
//
//  Created by Baise Thomas on 6/6/25.
//

import Foundation
import SwiftUI
import SwiftData
// import TabletNotes // Uncomment if models are in a separate module

@MainActor
func sermonStatusText(transcriptionStatus: String, summaryStatus: String) -> (String, Color) {
    if transcriptionStatus == "failed" || summaryStatus == "failed" {
        return ("Failed", .red)
    } else if transcriptionStatus == "processing" || summaryStatus == "processing" {
        return ("Processing...", .orange)
    } else {
        return ("Ready", .green)
    }
}

struct ContentView: View {
    var sermonService: SermonService
    @State private var showServiceTypeModal = false
    @State private var selectedServiceType: String? = nil
    var onStartRecording: ((String) -> Void)?
    var onViewPastSermons: (() -> Void)?
    let serviceTypes = ["Sermon", "Bible Study", "Youth Group", "Conference"]

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(title: "TabletNotes", showLogo: true, showSearch: true, showSyncStatus: true, showBack: false, syncStatus: HeaderView.SyncStatus.synced)
            Spacer(minLength: 0)
            VStack(spacing: 24) {
                Text("Tablet Notes Home")
                    .font(.largeTitle)
                    .padding()
                Button("Start Recording") {
                    onStartRecording?("")
                }
                .buttonStyle(.borderedProminent)
                Button("View Past Sermons") {
                    onViewPastSermons?()
                }
                .foregroundColor(.blue)
                .padding(.top, 16)
            }
            if sermonService.sermons.isEmpty {
                Spacer()
                Text("No sermons yet. Start recording")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(sermonService.sermons) { sermon in
                        let (statusText, statusColor) = sermonStatusText(transcriptionStatus: sermon.transcriptionStatus, summaryStatus: sermon.summaryStatus)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sermon.title)
                                    .font(.headline)
                                Text(sermon.serviceType)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(sermon.date, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(statusText)
                                .font(.caption)
                                .foregroundColor(statusColor)
                                .padding(6)
                                .background(statusColor.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
                .listStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    ContentView(sermonService: SermonService(modelContext: try! ModelContext(ModelContainer(for: Sermon.self))))
}
