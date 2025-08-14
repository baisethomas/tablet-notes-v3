//
//  DataMigration.swift
//  TabletNotes
//
//  Created by Claude for data migration
//

import Foundation
import SwiftData

struct DataMigration {
    
    /// Attempt to recover audio files after SwiftData migration failure
    static func recoverAudioFilesAfterMigration() {
        print("[DataMigration] Starting audio file recovery process...")
        
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
    }
    
    /// Check if there are recoverable audio files and prompt user
    static func hasRecoverableAudioFiles() -> Bool {
        return UserDefaults.standard.bool(forKey: "has_recoverable_audio_files")
    }
    
    /// Clear recovery flags after successful recovery
    static func clearRecoveryFlags() {
        UserDefaults.standard.removeObject(forKey: "has_recoverable_audio_files")
        
        // Clear individual recovery entries
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys {
            if key.hasPrefix("recoverable_audio_") {
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
}