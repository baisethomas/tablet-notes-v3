# SwiftData Migration Strategy

## Overview
This document outlines the migration strategy for TabletNotes to ensure users never lose data during app updates.

## Current Migration System

### Automatic Migration (Preferred)
SwiftData supports automatic lightweight migration when schema changes are simple:
- Adding new optional fields
- Adding new fields with default values
- Removing fields
- Renaming fields (with migration hints)

### Fallback: Audio Recovery System
If automatic migration fails, the app has a fallback system (see `TabletNotesApp.swift` lines 35-67):
1. Catalogs all existing audio files for recovery
2. Backs up notes from UserDefaults
3. Deletes corrupted database
4. Creates fresh database
5. Prompts user to recover audio files and notes

## Recent Migration: Adding Transcript.id Field

### Problem
- Transcript model originally didn't have a local UUID `id` field
- Needed to add one for proper sync with backend

### Solution
```swift
// CORRECT: Field with default value (supports auto-migration)
var id: UUID = UUID()

// WRONG: Required field without default (causes migration failure)
@Attribute(.unique) var id: UUID
```

### Why This Works
- SwiftData can automatically generate UUIDs for existing Transcript records
- No data loss during migration
- Seamless for production users

## Best Practices for Future Schema Changes

### ✅ Safe Changes (Auto-Migration Works)
1. **Adding optional fields**:
   ```swift
   var newField: String?  // OK
   ```

2. **Adding fields with default values**:
   ```swift
   var newField: String = "default"  // OK
   var newId: UUID = UUID()  // OK
   ```

3. **Removing fields**:
   ```swift
   // Just delete the field, SwiftData ignores it
   ```

### ❌ Dangerous Changes (May Cause Migration Failure)
1. **Adding required fields without defaults**:
   ```swift
   var newField: String  // WILL FAIL MIGRATION
   @Attribute(.unique) var id: UUID  // WILL FAIL MIGRATION
   ```

2. **Changing field types**:
   ```swift
   // OLD: var timestamp: TimeInterval
   // NEW: var timestamp: Date  // WILL FAIL MIGRATION
   ```

3. **Changing relationships**:
   ```swift
   // Changing from one-to-one to one-to-many requires careful handling
   ```

### 🔶 Complex Changes (Require Custom Migration)
For complex changes, use versioned schemas (not currently implemented):
```swift
enum SchemaV1: VersionedSchema { ... }
enum SchemaV2: VersionedSchema { ... }
enum MigrationPlan: SchemaMigrationPlan { ... }
```

## Testing Migrations

### Before Deploying Schema Changes
1. **Test on device with existing data**:
   - Install current production version
   - Create test data (sermons, notes, transcripts)
   - Install new version with schema changes
   - Verify all data is preserved

2. **Test fallback recovery**:
   - Force migration failure by making incompatible change
   - Verify audio files are recovered
   - Verify notes are recovered from UserDefaults

3. **Test fresh install**:
   - Install new version on clean device
   - Verify app works correctly without migration

## Migration Checklist

Before merging schema changes to main:
- [ ] Schema change uses default values or optionals
- [ ] Tested migration on device with existing data
- [ ] Tested fresh install
- [ ] Documented change in this file
- [ ] Updated version number if needed

## Version History

### v1.1.0 (Shipped)
- **Change**: Added `id: UUID` field to Transcript model
- **Migration Type**: Automatic (default value)
- **Risk**: Low
- **Impact**: Enables proper multi-device sync for transcripts

### v1.0.0
- **Initial release**
- No migrations needed

## Recovery Tools

### For Developers
If a user reports data loss:
1. Check if they have recoverable audio files (UserDefaults keys `recoverable_audio_*`)
2. Check if notes are backed up (`has_recoverable_notes`, `has_notes_backup`)
3. Guide them through recovery in SermonService (automatic on next launch)

### For Users
The app automatically attempts recovery if migration fails. No manual intervention needed.

## Future Improvements

1. **Implement Versioned Schemas**: For better control over complex migrations
2. **Cloud Backup Before Migration**: Sync all data to cloud before attempting migration
3. **Migration Success Telemetry**: Track migration success rates in production
4. **Rollback Support**: Allow reverting to previous schema if migration fails

## References
- [SwiftData Migration Documentation](https://developer.apple.com/documentation/swiftdata/migrating-your-apps-data-model)
- `TabletNotesApp.swift`: Main migration logic
- `DataMigration.swift`: Audio and notes recovery system
- `Transcript.swift`: Example of migration-safe field addition
