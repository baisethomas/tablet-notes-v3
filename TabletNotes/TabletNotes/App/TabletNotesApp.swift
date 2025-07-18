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
    let container: ModelContainer
    
    init() {
        do {
            // Configure the container with migration options - include User models
            let schema = Schema([
                Sermon.self, 
                Note.self, 
                Transcript.self, 
                Summary.self, 
                TranscriptSegment.self,
                User.self,
                UserNotificationSettings.self
            ])
            let configuration = ModelConfiguration(schema: schema)
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // If migration fails, try to create a fresh container
            print("Migration failed, creating fresh container: \(error)")
            do {
                let schema = Schema([
                    Sermon.self, 
                    Note.self, 
                    Transcript.self, 
                    Summary.self, 
                    TranscriptSegment.self,
                    User.self,
                    UserNotificationSettings.self
                ])
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                container = try ModelContainer(for: schema, configurations: configuration)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }
    
    var modelContext: ModelContext { ModelContext(container) }
    var body: some Scene {
        WindowGroup {
            MainAppView(modelContext: modelContext)
                .requiresAuthentication()
                .environment(\.authManager, AuthenticationManager.shared)
        }
    }
}
