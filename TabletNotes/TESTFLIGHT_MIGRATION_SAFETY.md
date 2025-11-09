# TestFlight Migration Safety Guide

## Overview
This document ensures that when users update the app from TestFlight, **all their existing recordings are preserved** and synced to the cloud before any migration occurs.

## Migration Safety System

### Components

1. **MigrationSafety.swift** - Handles pre-migration preparation and recovery
2. **Enhanced DataMigration.swift** - Backs up audio files and notes
3. **Updated TabletNotesApp.swift** - Automatically restores data after migration
4. **Updated SyncService.swift** - Syncs all local-only recordings

## How It Works

### Before Migration (App Update)

1. **Automatic Preparation**:
   - On app launch, `MigrationSafety.prepareForMigration()` marks all local-only sermons for sync
   - `MigrationSafety.backupAllSermonData()` creates a complete backup of all sermon data
   - Audio files are cataloged for recovery via `DataMigration.recoverAudioFilesAfterMigration()`

2. **Automatic Sync**:
   - `SyncService` syncs all sermons marked `needsSync=true` OR `remoteId == nil`
   - This ensures ALL local recordings are uploaded to Supabase before migration

### During Migration

1. **If Migration Succeeds**:
   - SwiftData automatically migrates the schema
   - All data is preserved
   - App continues normally

2. **If Migration Fails**:
   - App detects migration failure
   - Backs up all sermon data BEFORE deleting database
   - Deletes corrupted database files
   - Creates fresh database
   - Restores all sermon data from backup
   - Audio files are preserved (stored separately in file system)

### After Migration

1. **Automatic Recovery**:
   - App checks for backup data
   - Restores sermons from backup if needed
   - Audio files are automatically re-linked
   - User sees all their recordings intact

## Key Safety Features

### 1. Triple Backup System
- **Cloud Backup**: All recordings synced to Supabase
- **Local Backup**: Complete sermon data backed up to UserDefaults
- **Audio Backup**: Audio files cataloged separately

### 2. Automatic Sync Before Migration
- All local-only sermons are automatically marked for sync
- Sync happens on app launch before any migration
- Ensures cloud backup exists even if local migration fails

### 3. Graceful Recovery
- If migration fails, data is restored from backup
- Audio files are preserved (stored in Documents/AudioRecordings)
- User sees no data loss

## Pre-Deployment Checklist

Before pushing to TestFlight:

- [ ] **Verify Backend is Ready**
  - Supabase schema matches iOS models
  - Backend functions handle transcript/summary/notes storage
  - Storage bucket is configured correctly

- [ ] **Test Migration Locally**
  1. Install current production version
  2. Create test recordings with notes, transcripts, summaries
  3. Install new version
  4. Verify all data is preserved
  5. Verify sync works correctly

- [ ] **Test Migration Failure Recovery**
  1. Force migration failure (temporarily break schema)
  2. Verify backup is created
  3. Verify data is restored
  4. Verify audio files are preserved

- [ ] **Verify Sync Works**
  1. Create local-only recordings
  2. Update app
  3. Verify recordings sync to cloud
  4. Verify recordings appear on other devices

## User Experience

### Best Case Scenario
- User updates app
- All recordings sync to cloud automatically
- Migration succeeds seamlessly
- User sees no interruption

### Worst Case Scenario (Migration Fails)
- User updates app
- Migration fails
- App automatically backs up data
- App restores data from backup
- User sees all recordings intact
- Audio files are preserved

## Monitoring

### Check Migration Success
```swift
// In logs, look for:
"[MigrationSafety] ✅ Backed up X sermons"
"[MigrationSafety] ✅ Marked X sermons for sync"
"[TabletNotesApp] ✅ Restored X sermons from backup"
```

### Check Sync Status
```swift
// In logs, look for:
"[SyncService] Found X sermons to sync"
"[SyncService] ✅ Sermon created with ID: ..."
```

## Troubleshooting

### If Users Report Missing Recordings

1. **Check Cloud Sync**:
   - Verify recordings exist in Supabase
   - Check `sermons` table for user's recordings
   - Check `transcripts`, `summaries`, `notes` tables

2. **Check Local Backup**:
   - Look for `migration_backup_all_sermons` in UserDefaults
   - Check backup date matches update time
   - Verify audio files exist in Documents/AudioRecordings

3. **Recovery Steps**:
   - Audio files should be recoverable via `DataMigration.getRecoverableAudioFiles()`
   - Sermon data can be restored from backup
   - Cloud sync should restore everything

## Technical Details

### Backup Storage
- **Location**: UserDefaults
- **Keys**: 
  - `migration_backup_all_sermons` - Complete sermon data JSON
  - `migration_backup_date` - Backup timestamp
  - `migration_prepared` - Flag indicating preparation completed
  - `recoverable_audio_*` - Audio file metadata

### Sync Strategy
- **Pre-Migration**: Mark all local-only sermons for sync
- **During Sync**: Upload all marked sermons to Supabase
- **Post-Migration**: Pull cloud changes to local

### Recovery Strategy
- **Primary**: Restore from cloud (Supabase)
- **Fallback**: Restore from local backup (UserDefaults)
- **Last Resort**: Recover audio files and recreate sermons

## Version History

### v1.1.0 (Current)
- Added MigrationSafety system
- Enhanced backup and recovery
- Automatic sync before migration
- Graceful migration failure handling

### v1.0.0
- Initial release
- Basic migration support
- Audio file recovery

## Questions?

If you encounter issues:
1. Check logs for `[MigrationSafety]` and `[SyncService]` messages
2. Verify Supabase backend is working
3. Check UserDefaults for backup data
4. Verify audio files exist in Documents/AudioRecordings

