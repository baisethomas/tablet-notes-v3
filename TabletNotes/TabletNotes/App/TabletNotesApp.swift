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
