# Testing Notes

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
