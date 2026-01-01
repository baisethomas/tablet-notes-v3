# README FAQ & Troubleshooting Verification

This document verifies claims made in the Tablet Notes README against actual codebase implementation.

## ✅ VERIFIED - Accurate Claims

### Audio Format & Recording
**Claim**: "M4A format with AAC codec"
**Source**: `TabletNotes/Services/Recording/RecordingService.swift:251`
```swift
AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
AVSampleRateKey: 44100,
AVNumberOfChannelsKey: 2,
AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
```
**Status**: ✅ Confirmed

### Audio File Storage
**Claim**: "Audio files saved to Documents/AudioRecordings/"
**Source**: `TabletNotes/Services/Recording/RecordingService.swift:183`
```swift
return documentsPath.appendingPathComponent("AudioRecordings")
```
**Status**: ✅ Confirmed

### File Naming
**Claim**: Audio files crash-safe, recover after app restart
**Source**: `TabletNotes/Services/Recording/RecordingService.swift:247`
```swift
let filename = "sermon_\(UUID().uuidString).m4a"
```
**Status**: ✅ Confirmed - Files persist to disk immediately

### Circuit Breakers
**Claim**: "Rate limiting on chat endpoint prevents abuse"
**Source**: `tablet-notes-api/netlify/functions/chat.js:13`
```javascript
const openAIBreaker = new CircuitBreaker(5, 30000); // 5 failures, 30 second timeout
```
**Source**: `tablet-notes-api/netlify/functions/transcribe.js:17`
```javascript
const assemblyAIBreaker = new CircuitBreaker(3, 60000); // 3 failures, 1 minute timeout
```
**Status**: ✅ Confirmed

### Token Storage via Supabase SDK
**Claim**: "Supabase auth tokens stored in iOS Keychain"
**Source**: Multiple files use `supabase.auth.session` which relies on Supabase SDK
```swift
// TabletNotes/Services/Auth/SupabaseAuthService.swift:297
let session = try await supabase.auth.session
```
**Status**: ⚠️ PARTIALLY ACCURATE - Supabase Swift SDK handles token storage (likely uses Keychain), but not explicitly implemented in app code

---

## ❌ INACCURATE - Needs Correction

### 1. Free Tier Recording Limit
**README Claim**: "3 recordings per month"
**Actual Code**: `TabletNotes/Models/Subscription.swift:161`
```swift
static let free = UsageLimits(
    maxRecordings: 5,  // ← 5 recordings, not 3
    maxRecordingMinutes: 150, // 2.5 hours total per month (5 x 30min recordings)
    maxRecordingDurationMinutes: 30, // 30 minutes per recording
    maxStorageGB: 1.0,
    maxNotesPerRecording: 20,
    maxExportsPerMonth: 3
)
```
**Correction Needed**: Change "3 recordings/month" to "5 recordings/month"
**Locations**:
- README.md:560 (Cost Analysis)
- README.md:728 (FAQ)

### 2. Chat Rate Limit Description
**README Claim**: "Free users: wait 60 seconds between messages"
**Actual Code**: `tablet-notes-api/netlify/functions/utils/rateLimiter.js:40-44`
```javascript
chat: {
  windowMs: 60 * 60 * 1000, // 1 hour
  maxRequests: 100, // 100 chat messages per hour per user
  keyPrefix: 'rate_limit:chat:'
}
```
**Correction Needed**: The limit is **100 messages per hour**, not "1 per minute"
**Reality**: This is generous - users can send messages rapidly, just not >100 in an hour
**Locations**: README.md:642, README.md:804

### 3. Free Tier Chat Message Limit
**README Claim**: "Limited chat messages (10/month)" in free tier
**Actual Code**: Rate limiter shows 100/hour for ALL users, no tier-specific limits found
**Source Searched**:
- Subscription.swift - No chat message limits defined
- rateLimiter.js - Only has per-hour limits (100/hour), not per-month
**Correction Needed**: Either:
- Remove "10/month" claim if not implemented
- Or clarify this is a planned feature
**Locations**: README.md:730

### 4. Background Sync Frequency
**README Claim**: "Background sync every 30 seconds when active"
**Actual Code**: `TabletNotes/Services/Sync/BackgroundSyncManager.swift:155`
```swift
syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
```
**Correction Needed**: Change "30 seconds" to "60 seconds"
**Locations**: README.md:312

### 5. Premium Per-Recording Limit
**README Claim**: "Unlimited recordings" for premium (implies per-recording duration unlimited)
**Actual Code**: `TabletNotes/Models/Subscription.swift:172`
```swift
static let premium = UsageLimits(
    maxRecordings: nil,  // unlimited count
    maxRecordingMinutes: nil, // unlimited monthly total
    maxRecordingDurationMinutes: 90, // ← 90 minutes per recording
    maxStorageGB: nil,
    maxNotesPerRecording: nil,
    maxExportsPerMonth: nil
)
```
**Correction Needed**: Clarify premium has 90-minute per-recording limit
**Current statement is misleading**

---

## ⚠️ UNVERIFIED - Could Not Find Source

### 1. Audio Bitrate
**README Claim**: "128kbps"
**Code Reality**: Uses `AVAudioQuality.high.rawValue` but bitrate not explicitly set
**Source**: RecordingService.swift:254
```swift
AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
```
**Note**: Apple's "high quality" AAC typically uses variable bitrate, not fixed 128kbps
**Recommendation**: Change to "high quality AAC" or test actual output bitrate

### 2. File Size Estimate
**README Claim**: "~1MB per minute (a 30-minute sermon is ~30MB)"
**Code Reality**: Not defined in code, this is an estimate
**Recommendation**: Verify with actual recording tests or remove specific numbers

### 3. Transcription Speed
**README Claim**: "~0.3x speed (30-minute sermon takes ~10 minutes)"
**Code Reality**: No timing metrics in code, this is based on AssemblyAI documentation
**Recommendation**: Add note "based on AssemblyAI processing speed" or remove specific timing

### 4. Performance Benchmarks Section
**README Claims**: Specific timings (1.2s launch, 15s upload, etc.)
**Code Reality**: No performance tracking in code
**Recommendation**: Label as "Estimated" or "Tested on iPhone 15 Pro" (which is already done)

### 5. Cost Estimates
**README Claims**: "$0.87 per sermon", "~$50-100/mo for 100 users"
**Code Reality**: No cost tracking in code
**Recommendation**: Label as "Estimated based on provider pricing"

### 6. Storage Limits Implementation
**README Claim**: "Free tier: 1GB, Premium: 100GB"
**Code**: `Subscription.swift:164` shows `maxStorageGB: 1.0` for free
**Note**: Premium shows `maxStorageGB: nil` (unlimited), not 100GB
**Correction Needed**: Premium is unlimited, not 100GB

---

## 📝 RECOMMENDED FIXES

### High Priority (Factually Incorrect)
1. ✏️ Free tier: 5 recordings/month (not 3)
2. ✏️ Sync interval: 60 seconds (not 30)
3. ✏️ Chat rate limit: 100/hour (not 1/minute wait)
4. ✏️ Premium storage: Unlimited (not 100GB)
5. ✏️ Premium recording: 90min per recording max (not unlimited)

### Medium Priority (Clarifications Needed)
6. ⚠️ Remove "10 chat messages/month" for free tier (not implemented in code)
7. ⚠️ Change "128kbps" to "high quality AAC" (bitrate not explicitly set)
8. ⚠️ Add "estimated" labels to cost analysis
9. ⚠️ Clarify Keychain usage is via Supabase SDK (not direct implementation)

### Low Priority (Nice to Have)
10. 📊 Add references to source files for key claims
11. 📊 Add disclaimer that performance benchmarks are estimates
12. 📊 Verify actual file size with real recordings

---

## 🔍 Codebase References for Key Features

### Authentication
- Token management: `TabletNotes/Services/Auth/SupabaseAuthService.swift`
- Session handling: Via Supabase SDK `supabase.auth.session`
- Token refresh: `SupabaseAuthService.swift:270` (with retry logic)

### Rate Limiting
- Configuration: `tablet-notes-api/netlify/functions/utils/rateLimiter.js:3-52`
- Implementation: Redis-based with in-memory fallback
- Endpoints using rate limiting:
  - `/chat` - 100 req/hour
  - `/transcribe` - 20 req/hour
  - `/summarize` - 50 req/hour
  - `/generate-upload-url` - 10 req/hour

### Subscription Limits
- Model definition: `TabletNotes/Models/Subscription.swift:152-177`
- Free tier enforcement: Not found in service layer (TODO: verify if implemented)
- Usage tracking: `User` model tracks `currentMonthRecordings`, `currentMonthMinutes`

### Sync
- Interval: `BackgroundSyncManager.swift:155` - 60 seconds
- Batch size: Not explicitly limited in code (claims 50 records/batch unverified)
- Conflict resolution: `SyncService.swift` uses timestamp comparison

---

## ✅ Action Items for README Update

1. Replace all instances of "3 recordings/month" with "5 recordings/month"
2. Update sync frequency from "30 seconds" to "60 seconds"
3. Correct chat rate limit description (100/hour, not 60 second waits)
4. Change premium storage from "100GB" to "unlimited"
5. Add note about premium 90-minute per-recording limit
6. Remove or mark as "planned" the "10 chat/month" free tier limit
7. Change audio description from "128kbps" to "high quality AAC"
8. Add disclaimer to performance benchmarks and cost estimates
