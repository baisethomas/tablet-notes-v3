# Summary Function Reliability Analysis

## Executive Summary

This document analyzes potential failure points in the summary generation flow to ensure summaries are reliably generated after every sermon recording. **Several critical issues were identified that could prevent summaries from being generated.**

---

## Critical Failure Points

### 1. **Publisher Subscription Lifecycle Issues** ⚠️ CRITICAL

**Location:** `RecordingView.swift` (lines 983-1021), `MainAppView.swift` (lines 252-273, 424-445)

**Problem:**
- Summary completion subscriptions are stored in view-level `cancellables` sets
- If the user navigates away from `RecordingView` before summary completes, the subscription is cancelled
- The summary may complete successfully on the server, but the local sermon is never updated
- Sermon remains stuck in "processing" status indefinitely

**Impact:** HIGH - User loses summary even though it was generated successfully

**Example Scenario:**
1. User records sermon
2. Transcription completes, summary generation starts
3. User navigates to sermon list before summary completes
4. Summary completes on server but local update never happens
5. Sermon stuck in "processing" status forever

**Code Evidence:**
```swift
// RecordingView.swift:983-1021
self.summaryService.summaryPublisher
    .combineLatest(self.summaryService.statusPublisher)
    .sink { summaryText, status in
        // This subscription is cancelled if view is dismissed
    }
    .store(in: &cancellables) // ❌ View-scoped cancellables
```

---

### 2. **No Automatic Retry for Failed Summaries** ⚠️ CRITICAL

**Location:** `SummaryService.swift`, `RecordingView.swift`, `MainAppView.swift`

**Problem:**
- When summary generation fails (network error, timeout, server error), the sermon is marked as "failed"
- No automatic retry mechanism exists
- User must manually retry from `SermonDetailView` or `SermonListView`
- If user doesn't notice the failure, summary is never generated

**Impact:** HIGH - Failed summaries stay failed unless user intervenes

**Missing Features:**
- No exponential backoff retry logic
- No automatic retry on network recovery
- No retry queue system (unlike transcriptions which have `TranscriptionRetryService`)

**Code Evidence:**
```swift
// RecordingView.swift:1003-1018
else if status == "failed" {
    // Just marks as failed, no retry logic
    let failedSummary = Summary(text: summaryText ?? "Summary generation failed", ...)
    sermonService.saveSermon(..., summaryStatus: "failed", ...)
}
```

---

### 3. **No Recovery Mechanism for Stuck "Processing" Status** ⚠️ CRITICAL

**Location:** App-wide

**Problem:**
- If app crashes, backgrounds, or subscription is cancelled while summary is "processing", the sermon remains stuck in "processing" status
- No background job checks for sermons with "processing" status that never completed
- No automatic recovery on app launch

**Impact:** HIGH - Sermons can be permanently stuck in processing state

**Missing Implementation:**
- No service similar to `TranscriptionRetryService` for summaries
- No check on app launch for stuck summaries
- No timeout mechanism to detect stale "processing" status

---

### 4. **MainAppView Creates New SummaryService Instances** ⚠️ HIGH

**Location:** `MainAppView.swift` (lines 248, 420)

**Problem:**
- New `SummaryService()` instances are created for each summary generation
- Subscriptions are stored in view-level `cancellables`
- If view state changes or view is recreated, subscriptions are lost
- Summary may complete but sermon is never updated

**Impact:** MEDIUM-HIGH - Summary generation can succeed but sermon not updated

**Code Evidence:**
```swift
// MainAppView.swift:248
let summaryService = SummaryService() // ❌ New instance
summaryService.generateSummary(for: text, type: serviceType)

summaryService.summaryPublisher
    .combineLatest(summaryService.statusPublisher)
    .sink { ... }
    .store(in: &self.cancellables) // ❌ May be cancelled
```

---

### 5. **No Background Task Support** ⚠️ HIGH

**Location:** `SummaryService.swift`

**Problem:**
- Summary generation uses `URLSession.shared.dataTask` which can be cancelled when app backgrounds
- No `BGTaskScheduler` or background task identifier to ensure completion
- If user backgrounds app during summary generation, request may be cancelled

**Impact:** MEDIUM-HIGH - Summary generation can be interrupted by app backgrounding

**Missing Implementation:**
```swift
// SummaryService.swift:138
let task = URLSession.shared.dataTask(with: request) { ... }
// ❌ No background task identifier
// ❌ No background task scheduling
```

---

### 6. **Missing Fallback to Basic Summary** ⚠️ MEDIUM

**Location:** `SummaryService.swift` (line 359)

**Problem:**
- `generateBasicSummary()` method exists but is never automatically called
- If AI summary fails, user must manually request basic summary
- No automatic fallback ensures user always gets some form of summary

**Impact:** MEDIUM - Users don't get summaries when AI service fails

**Code Evidence:**
```swift
// SummaryService.swift:359
func generateBasicSummary(for transcript: String, type: String) {
    // ✅ Method exists but never called automatically
}
```

---

### 7. **No Summary Retry Queue System** ⚠️ MEDIUM

**Location:** App-wide

**Problem:**
- Transcriptions have `TranscriptionRetryService` with queue, retry logic, and network monitoring
- Summaries have no equivalent service
- Failed summaries don't automatically retry when network recovers
- No persistent queue for failed summary attempts

**Impact:** MEDIUM - Failed summaries don't recover automatically

**Comparison:**
- ✅ Transcriptions: `TranscriptionRetryService` with queue, retries, network monitoring
- ❌ Summaries: No equivalent service

---

### 8. **Error Handling Doesn't Update Sermon in All Cases** ⚠️ MEDIUM

**Location:** `MainAppView.swift` (lines 252-273, 424-445)

**Problem:**
- Summary failure handling only updates sermon if status is "complete" or "failed"
- If subscription is cancelled before status update, sermon remains in "processing"
- No handling for intermediate states or cancellation

**Impact:** MEDIUM - Sermons can remain in wrong state

**Code Evidence:**
```swift
// MainAppView.swift:254-271
.sink { summaryText, status in
    if status == "complete", let summaryText = summaryText {
        // ✅ Handles success
    }
    // ❌ No else clause - if status is "pending" and subscription cancelled, nothing happens
}
```

---

### 9. **No Timeout Detection for Stale Processing Status** ⚠️ MEDIUM

**Location:** App-wide

**Problem:**
- No mechanism to detect if a sermon has been in "processing" status too long
- If summary generation hangs or is lost, sermon stays "processing" forever
- No timeout threshold (e.g., if processing > 10 minutes, mark as failed and retry)

**Impact:** MEDIUM - Stale processing states never recover

---

### 10. **Summary Service Instance Management** ⚠️ LOW-MEDIUM

**Location:** Multiple views

**Problem:**
- `RecordingView` uses `@StateObject` (good)
- `MainAppView` creates new instances (bad)
- `SermonDetailView` creates new instances (bad)
- `SermonListView` creates new instances (bad)
- Inconsistent instance management leads to subscription issues

**Impact:** LOW-MEDIUM - Inconsistent behavior across views

---

## Recommended Solutions

### Priority 1: Critical Fixes

#### 1. Create SummaryRetryService (Similar to TranscriptionRetryService)
- Queue system for failed summaries
- Automatic retry with exponential backoff
- Network monitoring to retry when network recovers
- Persistent storage of pending summaries
- Automatic recovery of stuck "processing" status

#### 2. Move Summary Completion Handling to Service Layer
- Don't rely on view-level subscriptions
- Use `SermonService` to listen for summary completion
- Persist subscriptions at service level, not view level
- Ensure updates happen even if view is dismissed

#### 3. Add Background Task Support
- Use `BGTaskScheduler` for summary generation
- Ensure summaries complete even when app backgrounds
- Add background task identifier tracking

#### 4. Add Recovery Mechanism on App Launch
- Check for sermons with "processing" status older than threshold
- Automatically retry or mark as failed
- Query for any summaries that completed but weren't updated locally

### Priority 2: Important Improvements

#### 5. Automatic Fallback to Basic Summary
- If AI summary fails after retries, automatically generate basic summary
- Ensure user always gets some form of summary
- Log when fallback is used for monitoring

#### 6. Add Timeout Detection
- Detect sermons stuck in "processing" > 10 minutes
- Automatically retry or mark as failed
- Alert user if multiple retries fail

#### 7. Centralize SummaryService Instance
- Use singleton or shared instance
- Ensure subscriptions persist across view lifecycle
- Consistent behavior across all views

### Priority 3: Nice to Have

#### 8. Add Summary Generation Status Tracking
- Track when summary generation started
- Track retry attempts
- Better error messages with retry counts

#### 9. Add Summary Generation Monitoring
- Analytics on success/failure rates
- Track average generation time
- Monitor for patterns in failures

---

## Implementation Priority

1. **IMMEDIATE:** Create `SummaryRetryService` with queue and retry logic
2. **IMMEDIATE:** Move summary completion handling to service layer
3. **HIGH:** Add recovery mechanism for stuck "processing" status
4. **HIGH:** Add background task support
5. **MEDIUM:** Automatic fallback to basic summary
6. **MEDIUM:** Add timeout detection
7. **LOW:** Centralize SummaryService instance management

---

## Testing Scenarios

### Must Test:
1. ✅ Record sermon, navigate away before summary completes → Summary should still update sermon
2. ✅ Record sermon, background app during summary → Summary should complete
3. ✅ Record sermon, app crashes during summary → Summary should retry on next launch
4. ✅ Record sermon with poor network → Summary should retry when network recovers
5. ✅ Record sermon, summary fails → Should automatically retry with backoff
6. ✅ Record sermon, summary fails after retries → Should fallback to basic summary
7. ✅ Record sermon, leave in "processing" > 10 min → Should detect and retry

---

## Code Locations for Fixes

### Files to Modify:
1. `TabletNotes/Services/Summary/SummaryService.swift` - Add retry logic
2. `TabletNotes/Services/Sync/SyncService.swift` - Ensure summary sync works
3. `TabletNotes/Views/RecordingView.swift` - Fix subscription lifecycle
4. `TabletNotes/Views/MainAppView.swift` - Fix subscription lifecycle
5. `TabletNotes/Services/SermonService.swift` - Add summary completion listener

### Files to Create:
1. `TabletNotes/Services/Summary/SummaryRetryService.swift` - New retry service
2. `TabletNotes/Services/Summary/SummaryBackgroundTask.swift` - Background task support

---

## Conclusion

**The summary generation feature has multiple critical failure points that could prevent summaries from being generated reliably.** The most critical issues are:

1. **Publisher subscription lifecycle** - Summaries can complete but sermons never update
2. **No automatic retry** - Failed summaries stay failed
3. **No recovery mechanism** - Stuck "processing" status never recovers

**Recommendation:** Implement `SummaryRetryService` and move summary completion handling to service layer as highest priority fixes.

