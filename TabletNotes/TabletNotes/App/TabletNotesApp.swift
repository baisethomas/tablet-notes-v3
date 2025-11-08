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
    @StateObject private var deepLinkHandler = DeepLinkHandler()
    
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
            
            // Create configuration with migration options
            let url = URL.documentsDirectory.appending(path: "TabletNotes.store")
            let configuration = ModelConfiguration(
                url: url,
                allowsSave: true,
                cloudKitDatabase: .none  // Explicit local-only to avoid CloudKit conflicts during migration
            )
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // If migration fails due to schema changes, preserve audio files and reset database
            print("Schema migration failed, preserving audio files and resetting data store: \(error)")
            
            // First, catalog existing audio files for potential recovery
            DataMigration.recoverAudioFilesAfterMigration()
            
            // Delete the existing store files
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let storeURL = documentsDir.appendingPathComponent("TabletNotes.store")
            let storeURLShm = documentsDir.appendingPathComponent("TabletNotes.store-shm") 
            let storeURLWal = documentsDir.appendingPathComponent("TabletNotes.store-wal")
            
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURLShm)
            try? FileManager.default.removeItem(at: storeURLWal)
            
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
                let configuration = ModelConfiguration(url: storeURL, allowsSave: true)
                container = try ModelContainer(for: schema, configurations: configuration)
                print("Successfully created fresh ModelContainer after migration failure")
            } catch {
                fatalError("Failed to create ModelContainer even after reset: \(error)")
            }
        }
    }
    
    var modelContext: ModelContext { ModelContext(container) }
    var body: some Scene {
        WindowGroup {
            MainAppView(modelContext: modelContext)
                .requiresAuthentication()
                .environment(\.authManager, AuthenticationManager.shared)
                .environmentObject(deepLinkHandler)
                .onOpenURL { url in
                    deepLinkHandler.handleURL(url)
                }
                .overlay(
                    // Show verification success message
                    Group {
                        if deepLinkHandler.shouldShowVerificationSuccess {
                            VStack {
                                Spacer()
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Email verified successfully!")
                                        .foregroundColor(.white)
                                }
                                .padding()
                                .background(Color.green.opacity(0.9))
                                .cornerRadius(10)
                                .shadow(radius: 5)
                                .transition(.move(edge: .bottom))
                                .padding()
                                Spacer().frame(height: 100)
                            }
                            .animation(.easeInOut, value: deepLinkHandler.shouldShowVerificationSuccess)
                        }
                    }
                )
        }
    }
}
