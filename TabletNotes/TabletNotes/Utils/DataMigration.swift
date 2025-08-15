//
//  DataMigration.swift
//  TabletNotes
//
//  Created by Claude for data migration
//

import Foundation
import SwiftData

struct DataMigration {
    
    /// Backup existing sermon-note relationships before migration
    static func backupSermonNotesBeforeMigration(modelContext: ModelContext) {
        print("[DataMigration] Backing up sermon-note relationships before migration...")
        
        do {
            // Fetch all sermons with their notes
            let fetchDescriptor = FetchDescriptor<Sermon>()
            let sermons = try modelContext.fetch(fetchDescriptor)
            
            var backupData: [String: [[String: Any]]] = [:]
            var totalNotesBackedUp = 0
            
            for sermon in sermons {
                if !sermon.notes.isEmpty {
                    let audioFileName = sermon.audioFileURL.lastPathComponent
                    
                    var notesArray: [[String: Any]] = []
                    for note in sermon.notes {
                        notesArray.append([
                            "id": note.id.uuidString,
                            "text": note.text,
                            "timestamp": note.timestamp,
                            "remoteId": note.remoteId ?? "",
                            "updatedAt": note.updatedAt?.timeIntervalSince1970 ?? Date().timeIntervalSince1970,
                            "needsSync": note.needsSync
                        ])
                    }
                    
                    backupData[audioFileName] = notesArray
                    totalNotesBackedUp += sermon.notes.count
                    print("[DataMigration] Backed up \(sermon.notes.count) notes for \(audioFileName)")
                }
            }
            
            if !backupData.isEmpty {
                // Save backup to UserDefaults
                if let data = try? JSONSerialization.data(withJSONObject: backupData) {
                    UserDefaults.standard.set(data, forKey: "sermon_notes_backup")
                    UserDefaults.standard.set(true, forKey: "has_notes_backup")
                    print("[DataMigration] Successfully backed up \(totalNotesBackedUp) notes from \(backupData.count) sermons")
                }
            }
            
        } catch {
            print("[DataMigration] Error backing up sermon notes: \(error)")
        }
    }
    
    /// Attempt to recover audio files and notes after SwiftData migration failure
    static func recoverAudioFilesAfterMigration() {
        print("[DataMigration] Starting audio file and notes recovery process...")
        
        let audioDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioRecordings")
        
        do {
            let audioFiles = try FileManager.default.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: [.contentModificationDateKey])
            
            print("[DataMigration] Found \(audioFiles.count) audio files to potentially recover")
            
            for audioFile in audioFiles {
                let filename = audioFile.lastPathComponent
                if filename.hasPrefix("sermon_") && filename.hasSuffix(".m4a") {
                    print("[DataMigration] Audio file available for recovery: \(filename)")
                    
                    // Extract creation date from file
                    let attributes = try FileManager.default.attributesOfItem(atPath: audioFile.path)
                    let creationDate = attributes[.creationDate] as? Date ?? Date()
                    
                    // Store info for potential recovery
                    UserDefaults.standard.set([
                        "filename": filename,
                        "creationDate": creationDate,
                        "path": audioFile.path
                    ], forKey: "recoverable_audio_\(filename)")
                }
            }
            
            if !audioFiles.isEmpty {
                UserDefaults.standard.set(true, forKey: "has_recoverable_audio_files")
                print("[DataMigration] Marked \(audioFiles.count) audio files as recoverable")
            }
            
        } catch {
            print("[DataMigration] Error during audio file recovery: \(error)")
        }
        
        // Also backup any remaining notes data that might be in UserDefaults
        backupNotesFromUserDefaults()
    }
    
    /// Backup notes that might still be in UserDefaults from recording sessions
    private static func backupNotesFromUserDefaults() {
        print("[DataMigration] Checking for notes in UserDefaults...")
        
        let userDefaults = UserDefaults.standard
        let allKeys = userDefaults.dictionaryRepresentation().keys
        
        var notesBackedUp = 0
        for key in allKeys {
            if key.hasPrefix("recordingSessionNotes_") {
                if let notesData = userDefaults.data(forKey: key) {
                    // Copy to backup key
                    userDefaults.set(notesData, forKey: "backup_\(key)")
                    notesBackedUp += 1
                    print("[DataMigration] Backed up notes from session: \(key)")
                }
            }
        }
        
        if notesBackedUp > 0 {
            userDefaults.set(true, forKey: "has_recoverable_notes")
            print("[DataMigration] Backed up notes from \(notesBackedUp) recording sessions")
        }
    }
    
    /// Check if there are recoverable audio files and prompt user
    static func hasRecoverableAudioFiles() -> Bool {
        return UserDefaults.standard.bool(forKey: "has_recoverable_audio_files")
    }
    
    /// Check if there are recoverable notes
    static func hasRecoverableNotes() -> Bool {
        return UserDefaults.standard.bool(forKey: "has_recoverable_notes")
    }
    
    /// Check if there are backed up sermon notes
    static func hasNotesBackup() -> Bool {
        return UserDefaults.standard.bool(forKey: "has_notes_backup")
    }
    
    /// Clear recovery flags after successful recovery
    static func clearRecoveryFlags() {
        UserDefaults.standard.removeObject(forKey: "has_recoverable_audio_files")
        UserDefaults.standard.removeObject(forKey: "has_recoverable_notes")
        UserDefaults.standard.removeObject(forKey: "has_notes_backup")
        UserDefaults.standard.removeObject(forKey: "sermon_notes_backup")
        
        // Clear individual recovery entries
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys {
            if key.hasPrefix("recoverable_audio_") || key.hasPrefix("backup_recordingSessionNotes_") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    
    /// Get list of recoverable audio files
    static func getRecoverableAudioFiles() -> [(filename: String, creationDate: Date, path: String)] {
        var recoverableFiles: [(filename: String, creationDate: Date, path: String)] = []
        
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys {
            if key.hasPrefix("recoverable_audio_") {
                if let fileInfo = UserDefaults.standard.dictionary(forKey: key),
                   let filename = fileInfo["filename"] as? String,
                   let creationDate = fileInfo["creationDate"] as? Date,
                   let path = fileInfo["path"] as? String {
                    recoverableFiles.append((filename: filename, creationDate: creationDate, path: path))
                }
            }
        }
        
        return recoverableFiles.sorted { $0.creationDate > $1.creationDate }
    }
    
    /// Get recoverable notes data from UserDefaults backups
    static func getRecoverableNotes() -> [String: Data] {
        var recoverableNotes: [String: Data] = [:]
        
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys {
            if key.hasPrefix("backup_recordingSessionNotes_") {
                if let notesData = UserDefaults.standard.data(forKey: key) {
                    // Extract original session ID from backup key
                    let originalKey = String(key.dropFirst("backup_".count))
                    recoverableNotes[originalKey] = notesData
                }
            }
        }
        
        return recoverableNotes
    }
    
    /// Get backed-up sermon notes
    static func getBackedUpSermonNotes() -> [String: [[String: Any]]] {
        guard let backupData = UserDefaults.standard.data(forKey: "sermon_notes_backup"),
              let notesBackup = try? JSONSerialization.jsonObject(with: backupData) as? [String: [[String: Any]]] else {
            return [:]
        }
        
        return notesBackup
    }
}