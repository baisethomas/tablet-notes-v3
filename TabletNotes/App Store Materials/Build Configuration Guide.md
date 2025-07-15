# TabletNotes Build Configuration Guide

This guide outlines the proper build settings and configuration for distributing TabletNotes via TestFlight and the App Store.

## Current Build Settings

### App Identity
- **Bundle Identifier**: `Creative-Native.TabletNotes`
- **Display Name**: `TabletNotes`
- **Marketing Version**: `1.0` (Update in Xcode project settings)
- **Current Project Version**: `1` (Update for each build)
- **Development Team**: `6G6W9N2YC6`

### Deployment Target
- **iOS Deployment Target**: iOS 17.0
- **Supported Devices**: iPhone, iPad
- **Architecture**: arm64 (Apple Silicon)

## Required Configuration Steps

### 1. Xcode Project Settings

#### General Tab
```
Deployment Info:
- iOS 17.0 (minimum)
- iPhone and iPad supported
- Supported interface orientations: All

Identity:
- Display Name: TabletNotes
- Bundle Identifier: Creative-Native.TabletNotes
- Version: 1.0
- Build: [Increment for each submission]

Signing & Capabilities:
- Automatically manage signing: ✓
- Team: [Your Apple Developer Team]
```

#### Build Settings
```
Code Signing:
- Code Signing Identity: Apple Distribution
- Development Team: 6G6W9N2YC6
- Provisioning Profile: Automatic

Build Options:
- Enable Bitcode: NO
- Strip Debug Symbols During Copy: YES (Release only)
- Symbols Hidden by Default: YES (Release only)

Swift Compiler:
- Optimization Level: Optimize for Speed [-O] (Release)
- Compilation Mode: Whole Module Optimization (Release)
```

### 2. App Store Connect Configuration

#### App Information
```
Name: TabletNotes
Subtitle: Record, transcribe & study sermons
Primary Language: English (U.S.)
Bundle ID: Creative-Native.TabletNotes
SKU: tabletnotes-ios-app
```

#### Categories
```
Primary Category: Productivity
Secondary Category: Education
```

#### Age Rating
```
Age Rating: 4+
Content Descriptors: None
```

### 3. Signing & Certificates

#### Required Certificates
1. **Apple Distribution Certificate**
   - Used for App Store distribution
   - Valid for 1 year
   - Must be in your Keychain

2. **Provisioning Profiles**
   - App Store Distribution Profile
   - Generated automatically by Xcode
   - Linked to your Bundle ID

#### Entitlements Configuration
```xml
<!-- Production entitlements -->
<key>aps-environment</key>
<string>production</string>

<key>com.apple.developer.icloud-container-identifiers</key>
<array/>

<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>

<!-- App Sandbox disabled for iOS -->
<key>com.apple.security.app-sandbox</key>
<false/>
```

### 4. Build Schemes

#### Debug Scheme
```
Build Configuration: Debug
- Code Optimization: None
- Debug Information: Include
- Testing enabled
- Profiling enabled
```

#### Release Scheme
```
Build Configuration: Release
- Code Optimization: Optimize for Speed
- Debug Information: Include (for crash reports)
- Archive scheme for distribution
```

## Pre-Distribution Checklist

### Code Preparation
- [ ] All hardcoded version numbers removed
- [ ] AppVersion utility implemented and used
- [ ] Debug logs and print statements removed/disabled
- [ ] API keys properly configured via environment
- [ ] All TODOs and FIXME comments resolved

### Testing Validation
- [ ] All unit tests passing
- [ ] UI tests passing on target devices
- [ ] Performance tests within acceptable limits
- [ ] No memory leaks detected
- [ ] Crash-free on supported iOS versions

### App Store Requirements
- [ ] Privacy policy URL configured
- [ ] Terms of service URL configured
- [ ] Support contact information provided
- [ ] App screenshots prepared (see separate guide)
- [ ] App preview videos created (optional)
- [ ] Metadata and descriptions finalized

### Security & Privacy
- [ ] Info.plist privacy descriptions complete
- [ ] Data handling practices documented
- [ ] Third-party SDKs comply with App Store guidelines
- [ ] No tracking without consent
- [ ] Encryption export compliance determined

## Build Process

### For TestFlight Beta
1. **Clean Build**
   ```bash
   # Clean derived data
   rm -rf ~/Library/Developer/Xcode/DerivedData
   
   # Open project in Xcode
   open TabletNotes.xcodeproj
   ```

2. **Archive Build**
   - Select "Any iOS Device" target
   - Product → Archive
   - Wait for build completion
   - Upload to App Store Connect

3. **TestFlight Configuration**
   - Add beta testers
   - Configure test information
   - Submit for external testing review

### For App Store Release
1. **Final Testing**
   - Complete regression testing
   - Performance validation
   - Device compatibility testing

2. **Archive & Submit**
   - Create final archive
   - Upload to App Store Connect
   - Submit for App Store review

3. **App Store Connect Setup**
   - Complete all metadata
   - Upload screenshots and videos
   - Set pricing and availability
   - Submit for review

## Environment-Specific Configuration

### Development
```swift
// Debug-only features
#if DEBUG
print("Debug mode active")
#endif

// Development API endpoints
let apiBaseURL = "https://dev-api.tabletnotes.io"
```

### TestFlight Beta
```swift
// Beta-specific features
#if TESTFLIGHT
showBetaFeedbackButton = true
#endif

// Beta API endpoints
let apiBaseURL = "https://beta-api.tabletnotes.io"
```

### Production
```swift
// Production configuration
let apiBaseURL = "https://api.tabletnotes.io"
let crashReportingEnabled = true
let analyticsEnabled = true
```

## Common Build Issues & Solutions

### Signing Issues
```
Problem: "No matching provisioning profiles found"
Solution: 
1. Refresh provisioning profiles in Xcode
2. Clean build folder (Cmd+Shift+K)
3. Restart Xcode
```

### Archive Issues
```
Problem: "Archive failed - Swift compilation error"
Solution:
1. Check for iOS version compatibility
2. Update deprecated APIs
3. Resolve Swift version conflicts
```

### Upload Issues
```
Problem: "Invalid binary - missing Info.plist"
Solution:
1. Verify Info.plist is included in build
2. Check bundle structure
3. Validate entitlements
```

## Version Management

### Semantic Versioning
```
Format: MAJOR.MINOR.PATCH
- MAJOR: Breaking changes
- MINOR: New features (backward compatible)
- PATCH: Bug fixes (backward compatible)

Examples:
- 1.0.0: Initial release
- 1.1.0: New features added
- 1.1.1: Bug fixes
```

### Build Numbers
```
Format: Incrementing integer
- Increment for each build submission
- Must be higher than previous submission
- Can reset with new marketing version

Examples:
- Version 1.0 (Build 1): Initial submission
- Version 1.0 (Build 2): Bug fix submission
- Version 1.1 (Build 3): New feature release
```

## Automation (Future Enhancement)

### Fastlane Configuration
```ruby
# Fastfile example for future use
platform :ios do
  desc "Build and upload to TestFlight"
  lane :beta do
    increment_build_number
    build_app(scheme: "TabletNotes")
    upload_to_testflight
  end
  
  desc "Build and upload to App Store"
  lane :release do
    build_app(scheme: "TabletNotes")
    upload_to_app_store
  end
end
```

### CI/CD Integration
```yaml
# GitHub Actions example for future use
name: Build and Deploy
on:
  push:
    tags: ['v*']
jobs:
  deploy:
    runs-on: macos-latest
    steps:
      - name: Build and upload
        run: fastlane beta
```

## Support & Resources

### Apple Developer Resources
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [iOS App Distribution Guide](https://developer.apple.com/documentation/xcode/distributing_your_app_for_beta_testing_and_releases)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

### Internal Resources
- Build logs: Xcode → Window → Devices and Simulators → View Device Logs
- Crash reports: App Store Connect → TestFlight → Crashes
- Performance data: Xcode → Window → Organizer → Archives

This configuration ensures TabletNotes meets all App Store requirements and provides a smooth distribution experience for beta testers and end users.