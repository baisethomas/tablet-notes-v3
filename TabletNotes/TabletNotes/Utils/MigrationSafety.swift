//
//  MigrationSafety.swift
//  TabletNotes
//
//  Created for TestFlight deployment safety
//

import Foundation
import SwiftData

/// Ensures all local recordings are synced to cloud before migration
class MigrationSafety {
    
    /// Marks all local-only sermons for sync before migration
    /// This ensures they will be synced on next app launch
    static func prepareForMigration(modelContext: ModelContext) {
        print("[MigrationSafety] Preparing for migration - marking all local-only sermons for sync")
        
        do {
            // Fetch all sermons that haven't been synced yet
            let descriptor = FetchDescriptor<Sermon>(
                predicate: #Predicate<Sermon> { sermon in
                    sermon.remoteId == nil || sermon.syncStatus == "localOnly"
                }
            )
            
            let localOnlySermons = try modelContext.fetch(descriptor)
            print("[MigrationSafety] Found \(localOnlySermons.count) local-only sermons")
            
            var markedCount = 0
            for sermon in localOnlySermons {
                // Mark for sync if not already marked
                if !sermon.hasPendingSyncWork {
                    sermon.markPendingSync(
                        metadata: true,
                        notes: !sermon.notes.isEmpty,
                        transcript: sermon.transcript != nil,
                        summary: sermon.summary != nil
                    )
                    markedCount += 1
                }
            }
            
            if markedCount > 0 {
                try modelContext.save()
                print("[MigrationSafety] ✅ Marked \(markedCount) sermons for sync")
                
                // Store flag that we've prepared for migration
                UserDefaults.standard.set(true, forKey: "migration_prepared")
                UserDefaults.standard.set(Date(), forKey: "migration_prepared_date")
            } else {
                print("[MigrationSafety] ℹ️ No sermons needed marking (all already synced or marked)")
            }
            
        } catch {
            print("[MigrationSafety] ❌ Error preparing for migration: \(error)")
        }
    }
    
    /// Backs up all sermon data before migration
    /// This provides a recovery mechanism if migration fails
    static func backupAllSermonData(modelContext: ModelContext) {
        print("[MigrationSafety] Backing up all sermon data before migration...")
        
        do {
            let descriptor = FetchDescriptor<Sermon>()
            let allSermons = try modelContext.fetch(descriptor)
            
            var backupData: [[String: Any]] = []
            
            for sermon in allSermons {
                var sermonData: [String: Any] = [
                    "id": sermon.id.uuidString,
                    "title": sermon.title,
                    "audioFileName": sermon.audioFileName,
                    "date": sermon.date.timeIntervalSince1970,
                    "serviceType": sermon.serviceType,
                    "speaker": sermon.speaker ?? NSNull(),
                    "syncStatus": sermon.syncStatus,
                    "transcriptionStatus": sermon.transcriptionStatus,
                    "summaryStatus": sermon.summaryStatus,
                    "isArchived": sermon.isArchived,
                    "remoteId": sermon.remoteId ?? NSNull(),
                    "lastSyncedAt": sermon.lastSyncedAt?.timeIntervalSince1970 ?? NSNull(),
                    "updatedAt": sermon.updatedAt?.timeIntervalSince1970 ?? NSNull(),
                    "needsSync": sermon.needsSync,
                    "metadataNeedsSync": sermon.metadataNeedsSync,
                    "notesNeedSync": sermon.notesNeedSync,
                    "transcriptNeedsSync": sermon.transcriptNeedsSync,
                    "summaryNeedsSync": sermon.summaryNeedsSync,
                    "userId": sermon.userId?.uuidString ?? NSNull()
                ]
                
                // Backup notes
                if !sermon.notes.isEmpty {
                    var notesArray: [[String: Any]] = []
                    for note in sermon.notes {
                        notesArray.append([
                            "id": note.id.uuidString,
                            "text": note.text,
                            "timestamp": note.timestamp,
                            "remoteId": note.remoteId ?? NSNull(),
                            "updatedAt": note.updatedAt?.timeIntervalSince1970 ?? NSNull(),
                            "needsSync": note.needsSync
                        ])
                    }
                    sermonData["notes"] = notesArray
                }
                
                // Backup transcript
                if let transcript = sermon.transcript {
                    sermonData["transcript"] = [
                        "id": transcript.id.uuidString,
                        "text": transcript.text,
                        "remoteId": transcript.remoteId ?? NSNull(),
                        "updatedAt": transcript.updatedAt?.timeIntervalSince1970 ?? NSNull(),
                        "needsSync": transcript.needsSync
                    ]
                }
                
                // Backup summary
                if let summary = sermon.summary {
                    sermonData["summary"] = [
                        "id": summary.id.uuidString,
                        "title": summary.title,
                        "text": summary.text,
                        "type": summary.type,
                        "status": summary.status,
                        "remoteId": summary.remoteId ?? NSNull(),
                        "updatedAt": summary.updatedAt?.timeIntervalSince1970 ?? NSNull(),
                        "needsSync": summary.needsSync
                    ]
                }
                
                backupData.append(sermonData)
            }
            
            // Save backup to UserDefaults
            if let jsonData = try? JSONSerialization.data(withJSONObject: backupData) {
                UserDefaults.standard.set(jsonData, forKey: "migration_backup_all_sermons")
                UserDefaults.standard.set(Date(), forKey: "migration_backup_date")
                print("[MigrationSafety] ✅ Backed up \(backupData.count) sermons")
            } else {
                print("[MigrationSafety] ❌ Failed to serialize backup data")
            }
            
        } catch {
            print("[MigrationSafety] ❌ Error backing up sermon data: \(error)")
        }
    }
    
    /// Checks if migration preparation is needed
    static func needsMigrationPreparation() -> Bool {
        // Check if we've already prepared for migration recently (within last 24 hours)
        if let preparedDate = UserDefaults.standard.object(forKey: "migration_backup_date") as? Date {
            let hoursSinceBackup = Date().timeIntervalSince(preparedDate) / 3600
            if hoursSinceBackup < 24 {
                return false // Already prepared recently
            }
        }
        return true
    }
    
    /// Performs complete migration safety preparation
    /// Call this before deploying to TestFlight
    static func performMigrationSafetyPreparation(modelContext: ModelContext) {
        print("[MigrationSafety] 🛡️ Performing migration safety preparation...")
        
        // 1. Mark all local-only sermons for sync
        prepareForMigration(modelContext: modelContext)
        
        // 2. Backup all sermon data
        backupAllSermonData(modelContext: modelContext)
        
        // 3. Also backup audio files (handled by DataMigration)
        DataMigration.recoverAudioFilesAfterMigration()
        
        print("[MigrationSafety] ✅ Migration safety preparation complete")
    }
    
    /// Restores sermon data from backup after migration failure
    static func restoreFromBackup(modelContext: ModelContext) -> Int {
        print("[MigrationSafety] Attempting to restore from backup...")
        
        guard let backupData = UserDefaults.standard.data(forKey: "migration_backup_all_sermons"),
              let sermonsArray = try? JSONSerialization.jsonObject(with: backupData) as? [[String: Any]] else {
            print("[MigrationSafety] ❌ No backup data found")
            return 0
        }
        
        var restoredCount = 0
        
        for sermonData in sermonsArray {
            guard let idString = sermonData["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let title = sermonData["title"] as? String,
                  let audioFileName = sermonData["audioFileName"] as? String,
                  let dateTimestamp = sermonData["date"] as? TimeInterval,
                  let serviceType = sermonData["serviceType"] as? String else {
                continue
            }
            
            let date = Date(timeIntervalSince1970: dateTimestamp)
            let speaker = sermonData["speaker"] as? String
            let syncStatus = sermonData["syncStatus"] as? String ?? "localOnly"
            let transcriptionStatus = sermonData["transcriptionStatus"] as? String ?? "pending"
            let summaryStatus = sermonData["summaryStatus"] as? String ?? "pending"
            let isArchived = sermonData["isArchived"] as? Bool ?? false
            let remoteId = sermonData["remoteId"] as? String
            let lastSyncedAt = (sermonData["lastSyncedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            let updatedAt = (sermonData["updatedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            let legacyNeedsSync = sermonData["needsSync"] as? Bool ?? false
            let notesNeedSync = sermonData["notesNeedSync"] as? Bool ?? false
            let transcriptNeedsSync = sermonData["transcriptNeedsSync"] as? Bool ?? false
            let summaryNeedsSync = sermonData["summaryNeedsSync"] as? Bool ?? false
            let userIdString = sermonData["userId"] as? String
            let userId = userIdString != nil ? UUID(uuidString: userIdString!) : nil

            let notesArray = sermonData["notes"] as? [[String: Any]]
            let transcriptData = sermonData["transcript"] as? [String: Any]
            let summaryData = sermonData["summary"] as? [String: Any]
            let restoredChildHasPendingSync =
                (notesArray?.contains { ($0["needsSync"] as? Bool) == true } ?? false) ||
                ((transcriptData?["needsSync"] as? Bool) == true) ||
                ((summaryData?["needsSync"] as? Bool) == true)
            let metadataNeedsSync = sermonData["metadataNeedsSync"] as? Bool ??
                (legacyNeedsSync && !restoredChildHasPendingSync && !notesNeedSync && !transcriptNeedsSync && !summaryNeedsSync)
            
            // Check if sermon already exists
            let descriptor = FetchDescriptor<Sermon>(
                predicate: #Predicate<Sermon> { sermon in
                    sermon.id == id
                }
            )
            
            do {
                let existing = try modelContext.fetch(descriptor)
                if existing.isEmpty {
                    // Create sermon
                    let sermon = Sermon(
                        id: id,
                        title: title,
                        audioFileName: audioFileName,
                        date: date,
                        serviceType: serviceType,
                        speaker: speaker,
                        syncStatus: syncStatus,
                        transcriptionStatus: transcriptionStatus,
                        summaryStatus: summaryStatus,
                        isArchived: isArchived,
                        userId: userId,
                        lastSyncedAt: lastSyncedAt,
                        remoteId: remoteId,
                        updatedAt: updatedAt,
                        needsSync: legacyNeedsSync,
                        metadataNeedsSync: metadataNeedsSync,
                        notesNeedSync: notesNeedSync,
                        transcriptNeedsSync: transcriptNeedsSync,
                        summaryNeedsSync: summaryNeedsSync
                    )
                    
                    // Restore notes
                    if let notesArray {
                        for noteData in notesArray {
                            if let noteIdString = noteData["id"] as? String,
                               let noteId = UUID(uuidString: noteIdString),
                               let text = noteData["text"] as? String,
                               let timestamp = noteData["timestamp"] as? TimeInterval {
                                let note = Note(
                                    id: noteId,
                                    text: text,
                                    timestamp: timestamp,
                                    remoteId: noteData["remoteId"] as? String,
                                    needsSync: noteData["needsSync"] as? Bool ?? false
                                )
                                sermon.notes.append(note)
                            }
                        }
                    }
                    
                    // Restore transcript
                    if let transcriptData,
                       let transcriptIdString = transcriptData["id"] as? String,
                       let transcriptId = UUID(uuidString: transcriptIdString),
                       let text = transcriptData["text"] as? String {
                        let transcript = Transcript(
                            id: transcriptId,
                            text: text,
                            remoteId: transcriptData["remoteId"] as? String,
                            needsSync: transcriptData["needsSync"] as? Bool ?? false
                        )
                        sermon.transcript = transcript
                    }
                    
                    // Restore summary
                    if let summaryData,
                       let summaryIdString = summaryData["id"] as? String,
                       let summaryId = UUID(uuidString: summaryIdString),
                       let text = summaryData["text"] as? String,
                       let type = summaryData["type"] as? String,
                       let status = summaryData["status"] as? String {
                        let summary = Summary(
                            id: summaryId,
                            title: summaryData["title"] as? String ?? "",
                            text: text,
                            type: type,
                            status: status,
                            remoteId: summaryData["remoteId"] as? String,
                            needsSync: summaryData["needsSync"] as? Bool ?? false
                        )
                        sermon.summary = summary
                        sermon.summaryPreviewText = Sermon.makeSummaryPreview(from: text)
                    }

                    sermon.refreshPendingSyncState()
                    
                    modelContext.insert(sermon)
                    restoredCount += 1
                }
            } catch {
                print("[MigrationSafety] ❌ Error restoring sermon \(idString): \(error)")
            }
        }
        
        if restoredCount > 0 {
            do {
                try modelContext.save()
                print("[MigrationSafety] ✅ Restored \(restoredCount) sermons from backup")
            } catch {
                print("[MigrationSafety] ❌ Error saving restored sermons: \(error)")
            }
        }
        
        return restoredCount
    }
}
