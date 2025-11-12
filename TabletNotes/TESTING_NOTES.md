# Testing Notes

---

## Update 7 - Summary Generation Reliability
**Build Date:** December 2025

### What's New
🎯 **Summary generation is now bulletproof!** Summaries will be generated reliably even if you navigate away, lose network connection, or the app backgrounds. Automatic retry system ensures you always get a summary, with fallback to basic summary if AI service fails.

### What Changed

#### SummaryRetryService - Automatic Retry System
- **Queue System:** Failed summaries automatically added to retry queue
- **Exponential Backoff:** Retries wait 2^retryCount minutes between attempts (2 min, 4 min, 8 min)
- **Network Monitoring:** Automatically retries when network connection is restored
- **Max Retries:** 3 attempts before falling back to basic summary
- **Persistent Storage:** Retry queue survives app restarts

#### Service-Layer Summary Handling
- **Persistent Subscriptions:** Summary completion handled at service level, not view level
- **No Lost Updates:** Summaries update sermons even if you navigate away before completion
- **Centralized Logic:** All summary generation goes through SermonService for consistency
- **Automatic Sync:** Successful summaries automatically trigger sync to cloud

#### Recovery Mechanism
- **Stuck Status Detection:** Automatically detects sermons stuck in "processing" status > 10 minutes
- **Auto-Recovery:** Stuck summaries automatically added to retry queue on app launch
- **Timeout Protection:** Prevents summaries from being stuck forever

#### Fallback System
- **Basic Summary Fallback:** If AI summary fails after all retries, automatically generates basic summary
- **Always Get Summary:** Users always receive some form of summary, even if AI service is down
- **Graceful Degradation:** App continues working even when external services fail

### What to Test

**Test 1: Navigate Away During Summary Generation**
1. Record a new sermon (at least 2-3 minutes)
2. Let transcription complete
3. **Immediately navigate away** from recording screen (go to sermon list)
4. Wait 1-2 minutes for summary to complete
5. Return to sermon details
6. **Expected:**
   - Summary appears even though you navigated away
   - Sermon status shows "complete" (not stuck in "processing")
   - Summary text is visible and complete

**Test 2: Network Failure During Summary**
1. Record a sermon and let transcription complete
2. **Turn OFF WiFi** immediately after transcription finishes
3. Watch sermon details screen
4. **Expected:**
   - Summary status shows "processing" then "failed"
   - Sermon is added to retry queue automatically
5. Turn WiFi back ON
6. Wait 2-3 minutes
7. **Expected:**
   - Summary automatically retries when network restored
   - Summary completes successfully
   - Sermon status updates to "complete"

**Test 3: App Crash Recovery**
1. Record a sermon and let transcription complete
2. Summary generation starts (status shows "processing")
3. **Force quit the app** (swipe up from app switcher)
4. Wait 2 minutes
5. Reopen the app
6. Navigate to the sermon
7. **Expected:**
   - App detects sermon stuck in "processing" status
   - Automatically adds to retry queue
   - Summary generation retries automatically
   - Summary completes within a few minutes

**Test 4: Multiple Retry Attempts**
1. Record a sermon
2. After transcription, **repeatedly turn WiFi OFF/ON** during summary generation
3. Let it fail 2-3 times
4. **Expected:**
   - Each failure adds to retry queue
   - Retries happen with increasing delays (exponential backoff)
   - After 3 failures, falls back to basic summary
   - Basic summary appears automatically

**Test 5: Background App During Summary**
1. Record a sermon and let transcription complete
2. Summary generation starts
3. **Background the app** (press home button)
4. Wait 2-3 minutes
5. Return to app
6. Navigate to sermon
7. **Expected:**
   - Summary completed while app was backgrounded
   - Sermon shows complete summary
   - No stuck "processing" status

**Test 6: Stuck Processing Status Recovery**
1. Admin: Manually set a sermon's `summaryStatus` to "processing" and `updatedAt` to 15 minutes ago
2. Open app
3. Navigate to that sermon
4. **Expected:**
   - App detects sermon stuck > 10 minutes
   - Automatically adds to retry queue
   - Summary generation retries
   - Status updates to "complete" or "failed" (not stuck)

**Test 7: Basic Summary Fallback**
1. Record a sermon
2. Simulate AI service failure (admin: block summarize endpoint)
3. Let retry attempts fail 3 times
4. **Expected:**
   - After 3 failures, basic summary generates automatically
   - Basic summary contains key points from transcript
   - Sermon status shows "complete" (not "failed")
   - User still gets useful summary content

**Test 8: Multiple Sermons Simultaneous**
1. Record 2-3 sermons in quick succession
2. Let all transcriptions complete
3. Navigate between sermons while summaries are generating
4. **Expected:**
   - All summaries complete successfully
   - No summaries get lost or stuck
   - Each sermon gets its own summary
   - Can navigate freely without affecting summary generation

### What to Report

**Summary Generation Issues:**
1. Did summary fail to generate after recording?
2. How long did you wait? (summaries can take 1-3 minutes)
3. Did you navigate away during generation?
4. What was the summary status? ("processing", "failed", "complete")
5. Screenshot of sermon details showing status

**Retry Issues:**
1. Did summary retry automatically after network restored?
2. How many times did it retry?
3. Did it eventually succeed or fall back to basic summary?
4. Any error messages shown?

**Stuck Status Issues:**
1. Did any sermon get stuck in "processing" status?
2. How long was it stuck? (> 10 minutes?)
3. Did it recover automatically on next app launch?
4. Screenshot showing stuck status

**Fallback Issues:**
1. Did basic summary generate when AI failed?
2. Was basic summary useful/readable?
3. Did it contain relevant content from transcript?

### Known Behaviors
- **Summary generation takes 1-3 minutes** depending on transcript length
- **Retries use exponential backoff:** 2 min, 4 min, 8 min delays
- **Stuck detection:** Sermons in "processing" > 10 minutes are auto-recovered
- **Basic summary fallback:** Triggers after 3 failed retry attempts
- **Network required:** AI summaries need internet, but basic summaries work offline
- **Retry queue persists:** Survives app restarts and is processed on launch
- **Service-level handling:** Summaries update even if you navigate away

### Technical Details (For Debugging)
- SummaryRetryService stores pending summaries in UserDefaults
- Retry queue processed automatically on app launch and network recovery
- SermonService manages summary subscriptions at service level (not view level)
- Stuck status detection runs on app launch via `recoverStuckSummaries()`
- Basic summary uses extractive summarization (first sentences + key phrases)
- Summary completion triggers automatic sync if user has Premium subscription

---

## Update 6 - Error Handling & Data Reliability
**Build Date:** November 9, 2025

### What's New
🎯 **Improved reliability and error handling** across the app with comprehensive error states, migration safety for TestFlight users, and fixes for notes/transcript/summary sync issues.

### What Changed

#### Error State UI System
- **ErrorStateView Component:** New consistent error UI throughout the app
- **LoadingStates Component:** Unified loading indicators for all async operations
- **Enhanced Error Handling:** Better error messages in RecordingView, SermonDetailView, SummaryView, and other screens
- **User-Friendly Messaging:** Clear, actionable error states instead of silent failures

#### Migration Safety for TestFlight
- **Safe Schema Updates:** Added `MigrationSafety` utility to prevent data loss during app updates
- **Automatic Migration:** Database schema changes now migrate automatically with default values
- **Migration Documentation:** Comprehensive guide for developers on safe vs. dangerous schema changes
- **TestFlight Protection:** Special safeguards for beta testers to preserve existing data

#### Notes Sync Fixes
- **Database Compatibility:** Fixed notes timestamp field to use integer format (was causing "invalid input syntax" errors)
- **Array/Object Handling:** Backend now handles notes in both array and object formats from Supabase
- **Default Values:** Added default timestamp (0) to satisfy database constraints
- **Improved Logging:** Better diagnostic logging for notes creation and retrieval

#### Transcript/Summary Sync Improvements
- **Background Processing Sync:** Transcripts and summaries now properly marked for sync after completion
- **Persistence Fix:** `needsSync` flag now saves correctly to trigger sync
- **Object Format Handling:** Backend handles single transcript/summary as objects (not arrays)
- **Retry Logic:** TranscriptionRetryService now marks sermons for sync after processing
- **MainActor Compliance:** SyncService runs on correct thread to prevent context unbinding warnings

#### Backend Data Handling
- **Validation:** Added checks for transcript.text and summary.text before inserting
- **Error Logging:** Improved error messages with codes and details
- **Success Confirmation:** Added .select() to verify inserted data
- **Upsert Operations:** Simplified create/update-sermon with upsert logic
- **Comprehensive Logging:** Track data transformation and API responses

### What to Test

**Test 1: Error States**
1. Turn OFF WiFi
2. Try to sync sermons
3. **Expected:**
   - See clear error message (not silent failure)
   - Error UI shows with retry option
   - Can dismiss and continue using app locally

**Test 2: Notes Sync Across Devices**
1. Record sermon on Device A with 3-4 notes during recording
2. Let sync complete (check sync status)
3. Open app on Device B
4. View the sermon details
5. **Expected:**
   - All notes appear on Device B
   - Notes are in correct order
   - Timestamps preserved (if visible in UI)

**Test 3: Background Transcription Sync**
1. Record a sermon and let it finish
2. Keep app open while transcription processes in background
3. Watch for "Syncing..." indicator
4. Open same sermon on Device B after sync completes
5. **Expected:**
   - Transcript appears on Device B
   - Summary appears on Device B
   - AI-generated title syncs correctly

**Test 4: App Update Migration (TestFlight)**
1. Install this update over previous TestFlight version
2. Launch app
3. Navigate to sermon list
4. **Expected:**
   - All previous sermons still visible
   - No data loss
   - No crashes on first launch
   - Database migrates smoothly

**Test 5: Loading States**
1. Sign in with account that has many sermons
2. Navigate to sermon list (watch for loading)
3. Tap a sermon with transcript (watch for loading)
4. Request a new summary (watch for loading)
5. **Expected:**
   - See consistent loading indicators
   - Clear "processing" states
   - Smooth transitions from loading → content

**Test 6: Retry After Error**
1. Turn OFF WiFi
2. Try to sync or transcribe
3. See error message
4. Tap "Retry" button (if available)
5. Turn WiFi back ON
6. **Expected:**
   - Operation retries automatically
   - Success after network restored
   - Clear feedback on retry progress

**Test 7: Summary/Transcript Persistence**
1. Generate transcript for a sermon
2. Force close app completely
3. Reopen app
4. Navigate to sermon
5. **Expected:**
   - Transcript still visible
   - Summary still visible
   - No need to regenerate

### What to Report

**Error Issues:**
1. Did you see an error message or silent failure?
2. Screenshot of error state
3. Was there a "Retry" button? Did it work?
4. What were you doing when error occurred?

**Sync Issues:**
1. Which items didn't sync? (notes, transcript, summary, audio)
2. How long did you wait for sync?
3. Any error indicators shown?
4. Check Settings → Account for subscription status

**Migration Issues:**
1. Did app crash on first launch after update?
2. Are any sermons missing?
3. Are notes/transcripts/summaries missing from existing sermons?
4. Screenshot sermon list if data is missing

**Loading/UI Issues:**
1. Did loading indicators appear?
2. Any screens stuck in loading state?
3. Any unexpected blank screens?
4. Screenshot of issue

### Known Behaviors
- **Migration is automatic** - no user action required
- **Sync requires Premium subscription** and internet connection
- **Notes timestamps default to 0** - visible timestamp feature coming later
- **Error states are dismissible** - can continue using app offline
- **Background transcription can take 2-5 minutes** for long sermons
- **Sync happens on app launch** and after recording/transcription

### Technical Details (For Debugging)
- Migration uses SwiftData automatic migration with default values
- Notes timestamp field: Integer (0 as default)
- Transcript/Summary: Stored as single objects in database
- needsSync flag: Set to `true` after transcript/summary completion
- SyncService runs on @MainActor to prevent context issues
- Backend validates text content before inserting to database

---

## Update 5 - Cross-Device Sync Implementation
**Build Date:** November 3, 2025

### What's New
🎉 **Sermons now sync across all your devices!** When you sign in with the same account on your iPhone and iPad, your sermons, notes, transcripts, and summaries automatically sync between devices.

### How It Works
- **Record on iPhone** → Sermon automatically uploads to cloud
- **Open iPad** → Sermon appears in your list with full audio
- **Make changes on any device** → Updates sync to all devices
- **AI-generated titles** → Summaries now include smart titles (e.g., "Faith in Difficult Times" instead of "Sermon on Nov 3")

### What Changed

#### Backend Infrastructure
- **Supabase Database:** Added sync metadata to all tables (sermons, notes, transcripts, summaries)
- **Row Level Security:** Your data is protected - users can only access their own sermons
- **Audio Storage:** Sermon audio files stored securely in Supabase Storage
- **Conflict Resolution:** Last-write-wins strategy prevents sync conflicts
- **API Endpoints:** Three new Netlify functions for creating, updating, and fetching sermons

#### iOS App
- **Automatic Sync:** App syncs when launched and when user logs in
- **Background Upload:** Audio files upload automatically after recording
- **Download on Demand:** Audio files download when needed on new device
- **Sync Status Tracking:** Each sermon tracks whether it's synced to cloud
- **AI Title Generation:** OpenAI generates descriptive sermon titles automatically

### What to Test

**Test 1: Basic Cross-Device Sync**
1. Sign in on your iPhone with your account
2. Record a new sermon (can be just 30 seconds)
3. Let the sermon finish processing (transcription + summary)
4. Sign in on your iPad with the SAME account
5. **Expected:**
   - Sermon appears in your sermon list on iPad
   - Tap sermon to view details
   - Audio plays correctly
   - Transcript and summary are visible
   - All notes you took appear

**Test 2: AI-Generated Titles**
1. Record a sermon on any device
2. Let AI summary complete
3. View the sermon details
4. **Expected:**
   - Title is descriptive (e.g., "Walking in Faith") NOT "Sermon on [date]"
   - Title relates to sermon content
   - Title appears on both devices after sync

**Test 3: Archive Sync**
1. Record sermon on iPhone
2. Wait for sync (open iPad to verify it appears)
3. On iPhone: Archive the sermon
4. Close and reopen iPad app
5. **Expected:**
   - Sermon is archived on iPad too
   - Archive status syncs within a few seconds

**Test 4: Edit Sync**
1. Record sermon on Device A
2. On Device B: View sermon and edit the title or notes
3. Return to Device A, close and reopen app
4. **Expected:**
   - Changes from Device B appear on Device A
   - Edits sync bidirectionally

**Test 5: Multiple Sermons**
1. Record 3-5 sermons on iPhone over several days
2. Sign in on iPad for the first time
3. **Expected:**
   - All sermons appear on iPad
   - Audio files download automatically or on-demand
   - Newest sermons appear first

**Test 6: Offline Recording → Online Sync**
1. Turn OFF WiFi on iPhone
2. Record a sermon (works locally)
3. Stop recording, let it save
4. Turn WiFi back ON
5. Wait 30-60 seconds
6. Open iPad
7. **Expected:**
   - Sermon syncs to cloud automatically when online
   - Appears on iPad after sync completes

**Test 7: Delete Doesn't Sync (Currently)**
⚠️ **Known Limitation:** Deleting a sermon on one device does NOT delete it on other devices yet. This will be addressed in a future update.

### What to Report

If you encounter sync issues:
1. **Sermon not appearing on second device?**
   - How long did you wait after recording?
   - Is WiFi connected on both devices?
   - Are you signed in with the same account email on both devices?

2. **Audio won't play on second device?**
   - Does the sermon show in the list but audio won't load?
   - Any error message displayed?
   - Check Settings → Account to verify Premium subscription (sync requires Premium)

3. **Wrong title or missing AI title?**
   - What does the title say?
   - Did the summary generate successfully?
   - Screenshot the sermon details screen

4. **Sync seems stuck?**
   - Close app completely (swipe up from app switcher)
   - Reopen app and wait 30 seconds
   - If still not syncing, report the issue

### Known Behaviors
- **Sync requires Premium subscription** (active trial or paid premium)
- **Initial sync may take 30-60 seconds** depending on audio file size
- **Large audio files (20+ min sermons) may take 2-3 minutes** to upload on slower WiFi
- **Sync happens automatically** on app launch and after recording
- **Audio downloads on-demand** when you open a synced sermon for the first time
- **Deletes don't sync yet** - will be added in future update
- **Conflict resolution:** If sermon edited on multiple devices simultaneously, last edit wins

### Requirements for Sync
✅ **Premium subscription** (trial or paid)
✅ **Internet connection** (WiFi or cellular)
✅ **Same account** on all devices
✅ **iOS 17+** on all devices

### Technical Details (For Debugging)
- Sermons sync via Supabase database
- Audio files stored in Supabase Storage bucket: `sermon-audio`
- Sync endpoint: `https://comfy-daffodil-7ecc55.netlify.app/.netlify/functions/`
- Each sermon has `remoteId` (cloud ID) and `localId` (device ID)
- Sync status tracked: `localOnly`, `syncing`, `synced`, `error`

---

## Update 4 - AssemblyAI Live Transcription Fix
**Build Date:** November 2, 2025

### What Was Fixed
Fixed critical issues preventing live transcription from working:
1. Users were getting 401 Unauthorized errors when trying to use live transcription
2. AssemblyAI API had changed from v2 to v3, breaking token generation
3. iOS app wasn't properly using session tokens for WebSocket authentication

### What Changed
**Backend (Netlify Function):**
- Updated to AssemblyAI v3 streaming API endpoint
- Changed from POST to GET request for token generation
- Token expiration set to 10 minutes (600 seconds)
- Session duration extended to 3 hours (10,800 seconds) for long recordings

**iOS App:**
- WebSocket now uses session token for authentication
- Updated direct API fallback to use v3 endpoint
- Removed hardcoded API key from WebSocket connection (more secure)

### What to Test

**Test 1: Basic Live Transcription**
1. Start a new recording
2. **Expected:**
   - Live transcription connects within 1-2 seconds
   - Transcript appears in real-time as you speak
   - No error messages about authorization

**Test 2: Extended Recording (10+ Minutes)**
1. Start a recording with live transcription
2. Let it run for at least 12-15 minutes while speaking periodically
3. **Expected:**
   - Transcription continues working past the 10-minute mark
   - No disconnections or token expiration errors
   - Session remains active for the full duration

**Test 3: Long Recording (30+ Minutes)**
1. Start a recording with live transcription
2. Let it run for 30+ minutes (simulate a sermon)
3. **Expected:**
   - Transcription works continuously
   - No interruptions in service
   - Full transcript captured

**Test 4: Network Reconnection**
1. Start recording with live transcription
2. Turn OFF WiFi briefly (10-15 seconds)
3. Turn WiFi back ON
4. **Expected:**
   - Recording continues (as before)
   - Live transcription may pause during disconnection
   - Audio is still captured locally

### What to Report
If you encounter any issues:
1. What error message did you see (if any)?
2. How long was the recording when the issue occurred?
3. Did live transcription work at all, or fail immediately?
4. Are you on WiFi or cellular data?
5. Screenshot of any error messages

### Known Behaviors
- Session tokens expire after 10 minutes, but sessions can last up to 3 hours
- First-time connection may take 2-3 seconds
- Network connection required for live transcription (not for basic recording)
- If Netlify function fails, app will use direct API key as fallback

---

## Update 3 - Network Disconnection Fix
**Build Date:** October 25, 2025

### What Was Fixed
Fixed a critical crash that occurred when:
1. Recording was in progress with live transcription active
2. WiFi/network was turned off or lost connection
3. App would crash or become unresponsive

### What Changed
- Live transcription now gracefully handles network disconnections
- Audio recording continues uninterrupted when network is lost
- Added 10-second timeout to network requests to prevent hanging
- WebSocket connections close cleanly when network fails
- User sees friendly error message instead of crash

### What to Test

**Test 1: WiFi Disconnection During Recording**
1. Start a new recording
2. Let it record for ~30 seconds with live transcription active
3. Turn OFF WiFi on your phone
4. **Expected:**
   - App does NOT crash
   - Recording continues
   - Live transcription stops
   - Message shown: "Network connection lost. Recording continues, but live transcription is paused."
5. Turn WiFi back ON
6. Stop recording normally
7. **Expected:** Audio file is complete with no gaps

**Test 2: Airplane Mode During Recording**
1. Start recording
2. Enable Airplane Mode after 1 minute
3. **Expected:** Same graceful behavior as Test 1
4. Continue recording for another minute
5. Disable Airplane Mode
6. Stop recording
7. **Expected:** Full audio captured, no data loss

**Test 3: Poor Network Conditions**
1. Start recording in area with spotty WiFi
2. Let network drop and reconnect naturally
3. **Expected:** App handles intermittent connection without crashing
4. Recording remains stable throughout

**Test 4: Network Loss During Startup**
1. Turn OFF WiFi before opening app
2. Open app and try to start recording
3. **Expected:**
   - Recording still works (local only)
   - Transcription may not start or shows error
   - No crash or hang

### Known Behaviors
- Live transcription requires active network connection
- When network is lost, transcription pauses but recording continues
- Audio is saved locally and can be transcribed later
- Reconnecting network does NOT auto-resume live transcription (must stop/start recording)

### What to Report
If you encounter any issues:
1. When did the network loss occur (during recording start, middle, end)?
2. Did the app crash, freeze, or show an error message?
3. Was the audio file saved completely?
4. Any error messages displayed?

---

## Update 2 - Trial System & Subscription Changes
**Build Date:** October 15, 2025

### What's New

#### 1. Simplified Subscription Tiers
- **Removed:** Pro tier
- **Now:** Only Free and Premium tiers
- **Free Tier:** 30 minutes per recording, 5 recordings/month
- **Premium Tier:** 90 minutes per recording, unlimited recordings
- **Pricing:** $4.99/month or $39.99/year (33% savings)

#### 2. 14-Day Free Trial System
- All new users get 14-day premium trial automatically
- Full premium features during trial (90-min recordings, unlimited recordings)
- Trial countdown shows days remaining
- After trial ends, users can continue on free tier or upgrade

#### 3. Smart Upgrade Prompts
- **Days 12-14:** Banner at top showing "Trial ending soon"
- **Day 15+:** Dismissible upgrade prompt with feature list
- **Frequency:** Daily for first week, then weekly
- **User Choice:** Can dismiss and continue with free tier (30-min limit)

#### 4. Fixed Subscription Sync Issues
- Fixed bug where users showed wrong tier limits
- Subscription status now properly syncs from database
- Existing "pro" users automatically migrated to "premium"

### What to Test

**Test 1: New User Trial Experience**
1. Create a new account
2. Start recording immediately
3. **Expected:** Should see 90-minute limit (premium trial active)
4. Check settings for trial status

**Test 2: Trial Expiring Banner**
1. Admin: Set your `subscription_expiry` to 2 days from now in Supabase
2. Reopen app
3. **Expected:** See orange banner at top saying "Trial Ending Soon - 2 days remaining"
4. Tap "Upgrade" button → navigates to Settings

**Test 3: Trial Expired Modal**
1. Admin: Set your `subscription_expiry` to yesterday in Supabase
2. Force close and reopen app
3. **Expected:** See full-screen modal with:
   - "Your Trial Has Ended" message
   - Feature list (90-min recordings, unlimited, cloud sync, AI)
   - Pricing options (monthly/annual)
   - "Upgrade to Premium" button
   - "Continue with Free" button (dismissible)
4. Tap "Continue with Free"
5. Start recording
6. **Expected:** Should now see 30-minute limit (free tier)

**Test 4: Prompt Frequency**
1. After dismissing modal, close and reopen app
2. **Expected:** Modal should NOT show immediately (waits 1 day)
3. Admin: Can test by clearing UserDefaults key `lastTrialPromptDismissedDate`

**Test 5: Subscription Status Display**
1. Check Settings page for subscription details
2. **Expected:** Should show current tier, expiry date, and limits
3. Verify upgrade options are visible

### Known Behaviors
- Testers with permanent premium (expiry 2099): Will NOT see trial prompts
- Trial prompts only show for users with expired trials
- Users can fully use free tier after trial (no forced upgrade)
- Dismissing modal doesn't prevent recording, just limits to 30 min

### Migration Notes
- All existing "pro" users automatically become "premium" users
- No data loss during migration
- Product IDs updated automatically

---

## Update 1 - Background Recording Fix
**Build Date:** October 14, 2025

## What Was Fixed
Fixed a critical crash that occurred when:
1. Recording was in progress
2. App was backgrounded or phone went to sleep
3. App was brought back to foreground and recording screen was opened

## What Changed
- Recording now continues seamlessly when app backgrounds or phone sleeps
- Audio session automatically resumes if interrupted (phone calls, alarms, etc.)
- Added robust handling for audio session interruptions

## What to Test

### Primary Test Case (Previously Crashed)
1. Start a new recording
2. Let it record for ~30 seconds
3. Press home button or lock the phone
4. Wait 10-15 seconds
5. Bring app back to foreground
6. Open the recording screen
7. **Expected:** App does NOT crash, recording continues without interruption

### Additional Test Cases

**Test 2: Phone Lock During Recording**
1. Start recording
2. Lock the phone (sleep button)
3. Wait 1 minute
4. Unlock and open app
5. **Expected:** Recording still active, no data loss

**Test 3: Incoming Phone Call**
1. Start recording
2. Receive a phone call (or simulate with another device)
3. End the call
4. Return to app
5. **Expected:** Recording automatically resumes after call

**Test 4: Background Extended Duration**
1. Start recording
2. Background the app for 5+ minutes
3. Return to app
4. **Expected:** Recording continues, timer shows correct duration

**Test 5: Multiple Background Cycles**
1. Start recording
2. Background/foreground the app 3-4 times
3. Stop recording normally
4. **Expected:** Audio file contains all recorded audio, no gaps

## Known Limitations
- Recording in background requires "Background Modes" capability to be enabled (already configured)
- iOS may still terminate recording if system resources are critically low (rare)

## What to Report
If you encounter any issues, please provide:
1. Exact steps to reproduce
2. How long the recording was active
3. How long the app was backgrounded
4. Any error messages shown
5. Whether audio file was saved and if it's complete
