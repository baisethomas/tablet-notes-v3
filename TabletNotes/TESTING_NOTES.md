# Testing Notes

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
