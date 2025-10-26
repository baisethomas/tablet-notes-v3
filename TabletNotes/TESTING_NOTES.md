# Testing Notes

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
