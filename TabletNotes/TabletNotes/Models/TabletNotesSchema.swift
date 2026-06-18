import Foundation
import SwiftData

/// Versioned SwiftData schema + migration plan for the app's local store.
///
/// Why this exists: the app previously created its `ModelContainer` from a bare
/// `Schema([...])` with no migration plan. When the model set changed between
/// releases, SwiftData couldn't always migrate the existing store, the container
/// init threw, and the launch code fell back to **deleting** the store and
/// recreating it empty (TAB-53) — which looked like total data loss to users.
///
/// Anchoring the current model set as `TabletNotesSchemaV1` and routing the
/// container through `TabletNotesMigrationPlan` gives every *future* schema
/// change a real migration stage (lightweight or custom) instead of relying on
/// the destructive fallback. When you change the models:
///   1. Add a `TabletNotesSchemaV2` enum capturing the new shape.
///   2. Append a `MigrationStage` (`.lightweight` for additive changes, or
///      `.custom` when data must be transformed) to `stages`.
///   3. Add `TabletNotesSchemaV2.self` to `schemas` and point the container's
///      `Schema(versionedSchema:)` at the latest version.
enum TabletNotesSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Sermon.self,
            Note.self,
            Transcript.self,
            TranscriptSegment.self,
            Summary.self,
            ChatMessage.self,
            ProcessingJob.self,
            User.self,
            UserNotificationSettings.self
        ]
    }
}

enum TabletNotesMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TabletNotesSchemaV1.self]
    }

    // No stages yet: V1 is the baseline. Add a `MigrationStage` here the next
    // time the schema changes so the store migrates in place rather than being
    // wiped. See the type doc above.
    static var stages: [MigrationStage] {
        []
    }
}
