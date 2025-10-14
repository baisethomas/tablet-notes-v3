# Testing Notes - Background Recording Fix

## Build Date
October 14, 2025

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
