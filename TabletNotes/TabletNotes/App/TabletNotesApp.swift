//
//  TabletNotesApp.swift
//  TabletNotes
//
//  Created by Baise Thomas on 6/6/25.
//

import SwiftUI
import CoreData
import SwiftData

@main
struct TabletNotesApp: App {
    let container = try! ModelContainer(for: Sermon.self, Note.self, Transcript.self, Summary.self, TranscriptSegment.self)
    var modelContext: ModelContext { ModelContext(container) }
    var body: some Scene {
        WindowGroup {
            MainAppView(modelContext: modelContext)
        }
    }
}
