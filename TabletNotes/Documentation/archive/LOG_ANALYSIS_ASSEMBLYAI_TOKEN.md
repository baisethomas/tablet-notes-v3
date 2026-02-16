# Log Analysis: AssemblyAI Live Token Authentication Issues

**Date:** December 9, 2025  
**Function:** `assemblyai-live-token` Netlify Function  
**Issue:** Intermittent authentication failures

## Summary

The logs show **2 successful requests followed by 1 authentication failure** within a 29-second window. The failure indicates a missing authentication session, suggesting a potential race condition or session expiration issue.

## Log Timeline

### Request 1: ✅ Success (11:28:22 PM)
- **Duration:** 597.57 ms
- **Status:** 200 OK
- **User ID:** `94771a20-c9e7-4a85-ad3d-b8ac29a23501`
- **User Agent:** `TabletNotes/1 CFNetwork/3860.100.1 Darwin/24.6.0`
- **Authentication:** ✅ Successful
- **Result:** Session token generated successfully (expires in 600 seconds)

### Request 2: ✅ Success (11:28:34 PM)
- **Duration:** 438.82 ms  
- **Status:** 200 OK
- **User ID:** `4921ee96-d064-49e8-95a2-3969d7916f38` (different user)
- **User Agent:** `TabletNotes/1 CFNetwork/3826.500.111.2.2 Darwin/24.4.0`
- **Authentication:** ✅ Successful
- **Result:** Session token generated successfully (expires in 600 seconds)

### Request 3: ❌ Failure (11:28:51 PM)
- **Duration:** 60.04 ms
- **Status:** 401 Unauthorized
- **User ID:** `anonymous` (no authentication)
- **User Agent:** `TabletNotes/1 CFNetwork/3826.600.41 Darwin/24.6.0`
- **Authentication:** ❌ Failed - "Auth session missing!"
- **Error:** `Authentication failed: Auth session missing!`

## Key Observations

### 1. **Different Users**
- Requests 1 and 2 are from **different user IDs**, indicating two separate users/devices
- Request 3 shows `userId: "anonymous"`, meaning no authentication token was sent

### 2. **User Agent Variations**
All three requests have different CFNetwork versions:
- Request 1: `CFNetwork/3860.100.1 Darwin/24.6.0`
- Request 2: `CFNetwork/3826.500.111.2.2 Darwin/24.4.0`
- Request 3: `CFNetwork/3826.600.41 Darwin/24.6.0`

This suggests:
- Different iOS versions or device configurations
- Request 3 might be from a different device or app version

### 3. **Authentication Flow Issue**

Looking at the iOS code (`AssemblyAILiveTranscriptionService.swift` lines 82-89):

```swift
do {
    let session = try await supabase.client.auth.session
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    print("[AssemblyAI Live] Using authenticated session for live transcription")
} catch {
    print("[AssemblyAI Live] No authentication available, using public access")
    // Continue without authentication - the Netlify function should handle unauthenticated requests
}
```

**Problem:** The code catches authentication errors and continues without auth, but the backend **requires authentication** (returns 401).

### 4. **No Token Refresh Logic**

Unlike other services (`SummaryService`, `AssemblyAITranscriptionService`), `AssemblyAILiveTranscriptionService` does **not attempt to refresh expired tokens**. It simply continues without authentication if the session check fails.

Compare with `SummaryService.swift` (lines 59-75):
```swift
private func getAuthToken() async throws -> String {
    do {
        let session = try await supabase.auth.session
        return session.accessToken
    } catch {
        // Token might be expired, try to refresh
        print("[SummaryService] Session expired or invalid, attempting to refresh token...")
        do {
            let refreshedSession = try await supabase.auth.refreshSession()
            return refreshedSession.accessToken
        } catch {
            throw SummaryError.auth("Authentication failed. Please sign in again.")
        }
    }
}
```

### 5. **Backend Configuration Warning**

```
[RateLimiter] Redis not configured, allowing all requests
```

This indicates rate limiting is disabled, which could allow abuse but isn't directly related to the auth failure.

## Root Cause Analysis

The third request failed because:

1. **Session retrieval failed** - `supabase.client.auth.session` threw an error
2. **No token refresh attempted** - Unlike other services, this one doesn't try to refresh
3. **Request sent without auth** - Code continues without Authorization header
4. **Backend rejects unauthenticated requests** - Returns 401

## Potential Causes

### Scenario A: Session Expired
- User's session expired between app launch and token request
- No refresh logic to recover

### Scenario B: Race Condition
- Multiple concurrent requests trying to access session simultaneously
- Session state temporarily unavailable

### Scenario C: User Not Logged In
- User opened app but hasn't authenticated yet
- Code should handle this gracefully but doesn't

### Scenario D: Supabase Client State Issue
- Supabase client lost session state
- Need to re-authenticate or refresh

## Recommendations

### 1. **Add Token Refresh Logic** (High Priority)

Update `AssemblyAILiveTranscriptionService.getSessionToken()` to match the pattern used in other services:

```swift
private func getSessionToken() async throws {
    // ... existing URL setup ...
    
    // Get auth token with automatic refresh
    do {
        let session = try await supabase.client.auth.session
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        print("[AssemblyAI Live] Using authenticated session for live transcription")
    } catch {
        // Token might be expired, try to refresh
        print("[AssemblyAI Live] Session expired or invalid, attempting to refresh token...")
        do {
            let refreshedSession = try await supabase.client.auth.refreshSession()
            request.setValue("Bearer \(refreshedSession.accessToken)", forHTTPHeaderField: "Authorization")
            print("[AssemblyAI Live] Token refreshed successfully")
        } catch {
            print("[AssemblyAI Live] Token refresh failed: \(error.localizedDescription)")
            // Don't continue without auth - throw error instead
            throw NSError(domain: "AuthError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication required. Please sign in again."])
        }
    }
    
    // ... rest of request logic ...
}
```

### 2. **Improve Error Handling**

Instead of silently continuing without auth, throw an error that can be handled by the UI:

```swift
} catch {
    print("[AssemblyAI Live] Authentication required but not available")
    throw NSError(domain: "AuthError", code: 401, userInfo: [
        NSLocalizedDescriptionKey: "Please sign in to use live transcription"
    ])
}
```

### 3. **Add Session State Check**

Before attempting to get token, check if user is authenticated:

```swift
private func getSessionToken() async throws {
    // Check authentication state first
    do {
        let session = try await supabase.client.auth.session
        guard session.user != nil else {
            throw NSError(domain: "AuthError", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Please sign in to use live transcription"
            ])
        }
        // ... continue with authenticated request ...
    } catch {
        // ... refresh logic ...
    }
}
```

### 4. **Backend: Consider Graceful Degradation**

If you want to support unauthenticated users (free tier), update the backend to handle anonymous requests gracefully rather than returning 401. However, this may not be desired for security/cost reasons.

### 5. **Add Logging**

Add more detailed logging to track session state:

```swift
print("[AssemblyAI Live] Checking authentication state...")
let session = try await supabase.client.auth.session
print("[AssemblyAI Live] Session found - User ID: \(session.user.id.uuidString)")
print("[AssemblyAI Live] Token expires at: \(session.expiresAt)")
```

### 6. **Monitor Session Expiration**

Track when sessions expire and proactively refresh before they expire:

```swift
let session = try await supabase.client.auth.session
let expiresAt = Date(timeIntervalSince1970: TimeInterval(session.expiresAt))
let timeUntilExpiry = expiresAt.timeIntervalSinceNow

if timeUntilExpiry < 300 { // Less than 5 minutes
    print("[AssemblyAI Live] Token expiring soon, refreshing...")
    let refreshedSession = try await supabase.client.auth.refreshSession()
    // Use refreshed session
}
```

## Impact Assessment

### User Impact
- **Low-Medium**: Only affects users trying to use live transcription
- **Frequency**: Appears intermittent (1 out of 3 requests in this sample)
- **Recovery**: Users can retry, but may not understand why it failed

### System Impact
- **Low**: Function completes quickly (60ms) even on failure
- **No DoS risk**: Failed requests don't consume significant resources

## Next Steps

1. ✅ **Immediate**: Implement token refresh logic in `AssemblyAILiveTranscriptionService`
2. ✅ **Immediate**: Update error handling to not silently fail
3. ⏳ **Short-term**: Add session expiration monitoring
4. ⏳ **Short-term**: Improve error messages for users
5. ⏳ **Long-term**: Consider backend changes if unauthenticated access is desired

## Testing Recommendations

1. Test with expired tokens to verify refresh logic works
2. Test with unauthenticated users to verify error handling
3. Test concurrent requests to check for race conditions
4. Monitor logs after deployment to track improvement


