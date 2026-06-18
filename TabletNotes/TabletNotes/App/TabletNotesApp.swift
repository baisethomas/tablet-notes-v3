//
//  TabletNotesApp.swift
//  TabletNotes
//
//  Created by Baise Thomas on 6/6/25.
//

import SwiftUI
import CoreData
import SwiftData
import FirebaseCore
import Firebase
#if canImport(GoogleSignIn)
@preconcurrency import GoogleSignIn
#endif

@main
struct TabletNotesApp: App {
    let container: ModelContainer
    let modelContext: ModelContext
    @StateObject private var deepLinkHandler = DeepLinkHandler()
    
    init() {
        FirebaseApp.configure()

        // Build the store from the current model set. SwiftData lightweight
        // migration handles compatible changes automatically; the destructive
        // reset in the catch is a genuine last resort (TAB-53), not the normal
        // upgrade path. (A versioned schema/migration plan will be introduced
        // when the first custom migration is actually needed — a baseline
        // version pointing at the live, mutable models gives false safety.)
        let schema = Schema([
            Sermon.self,
            Note.self,
            Transcript.self,
            TranscriptSegment.self,
            Summary.self,
            ChatMessage.self,
            ProcessingJob.self,
            User.self,
            UserNotificationSettings.self
        ])
        let url = URL.documentsDirectory.appending(path: "TabletNotes.store")

        do {
            let configuration = ModelConfiguration(
                url: url,
                allowsSave: true,
                cloudKitDatabase: .none  // Explicit local-only to avoid CloudKit conflicts during migration
            )
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // LAST RESORT: the store genuinely failed to load. We can still fully
            // recover because the cloud copy is authoritative — SyncService
            // re-hydrates the store on next login. Preserve audio files, reset the
            // store, and record that a reset happened so the UI can show a
            // "Restoring…" state instead of a bare empty list (which reads as
            // total data loss). Log loudly.
            print("⛔️ [TAB-53] SwiftData store load failed — destructive reset (cloud will re-hydrate). Error: \(error)")

            DataMigration.recoverAudioFilesAfterMigration()
            DataMigration.recordLocalStoreReset(reason: "\(error)")

            let storeURLShm = url.deletingLastPathComponent().appendingPathComponent("TabletNotes.store-shm")
            let storeURLWal = url.deletingLastPathComponent().appendingPathComponent("TabletNotes.store-wal")
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: storeURLShm)
            try? FileManager.default.removeItem(at: storeURLWal)

            do {
                // Keep cloudKitDatabase: .none on the fallback too, or it defaults
                // to .automatic (P2).
                let configuration = ModelConfiguration(
                    url: url,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
                container = try ModelContainer(for: schema, configurations: configuration)
                print("✅ [TAB-53] Created fresh ModelContainer after reset; awaiting cloud re-hydration")
            } catch {
                fatalError("Failed to create ModelContainer even after reset: \(error)")
            }
        }

        modelContext = ModelContext(container)
        AppStoreScreenshotSeed.seedIfNeeded(in: modelContext)
    }

    var body: some Scene {
        WindowGroup {
            MainAppView(modelContext: modelContext)
                .requiresAuthentication()
                .environment(\.authManager, AuthenticationManager.shared)
                .environmentObject(deepLinkHandler)
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    #endif
                    deepLinkHandler.handleURL(url)
                }
                .sheet(isPresented: $deepLinkHandler.shouldShowPasswordReset) {
                    ResetPasswordView {
                        deepLinkHandler.shouldShowPasswordReset = false
                    }
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
