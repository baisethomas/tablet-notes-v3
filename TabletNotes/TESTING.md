# Tablet Notes Testing Guide

This document outlines the testing strategy and implementation for the Tablet Notes iOS application.

## Testing Overview

The TabletNotes app now includes comprehensive test coverage across three levels:

### 1. Unit Tests (`TabletNotesTests/`)
- **Service Layer Tests**: Core business logic validation
- **Mock Services**: Reliable test doubles for external dependencies
- **Edge Case Coverage**: Error handling and boundary conditions

### 2. Integration Tests (`TabletNotesTests/Integration/`)
- **Workflow Tests**: End-to-end user scenarios
- **Service Integration**: Cross-service communication validation
- **Data Flow**: Complete data pipeline testing

### 3. UI Tests (`TabletNotesUITests/`)
- **User Flow Tests**: Critical user journeys
- **Performance Tests**: App responsiveness and stability
- **Accessibility Tests**: UI element interaction validation

## Test Structure

```
TabletNotesTests/
├── Mocks/
│   ├── MockAuthService.swift           # Authentication testing
│   ├── MockRecordingService.swift      # Audio recording testing  
│   └── MockSupabaseService.swift       # Backend service testing
├── Services/
│   ├── AuthServiceTests.swift          # Authentication unit tests
│   ├── RecordingServiceTests.swift     # Recording unit tests
│   └── SupabaseServiceTests.swift      # Backend unit tests
├── Integration/
│   └── RecordingWorkflowTests.swift    # End-to-end workflow tests
└── TabletNotesTests.swift              # Main test file

TabletNotesUITests/
├── TabletNotesUITests.swift            # Main UI tests
└── TabletNotesUITestsLaunchTests.swift # Launch performance tests
```

## Running Tests

### Via Xcode
1. **Unit Tests**: `Cmd+U` or Product → Test
2. **Specific Test Suite**: Right-click test file → "Run Tests"
3. **Single Test**: Click diamond next to test method

### Via Command Line
```bash
# All tests
xcodebuild test -scheme TabletNotes -destination 'platform=iOS Simulator,name=iPhone 15'

# Unit tests only
xcodebuild test -scheme TabletNotes -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TabletNotesTests

# UI tests only  
xcodebuild test -scheme TabletNotes -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TabletNotesUITests
```

## Test Coverage

### Authentication Service Tests ✅
- [x] Sign up with valid/invalid data
- [x] Sign in with correct/incorrect credentials
- [x] Sign out functionality
- [x] Profile updates
- [x] Session refresh and expiration
- [x] Subscription tier management
- [x] Password reset functionality

### Recording Service Tests ✅
- [x] Audio permission handling
- [x] Recording start/stop/pause/resume
- [x] Duration tracking and state management
- [x] Error handling for various scenarios
- [x] Concurrent recording prevention
- [x] Publisher state updates
- [x] File URL management

### Supabase Service Tests ✅
- [x] File upload/download/delete operations
- [x] Signed URL generation
- [x] User profile management
- [x] Data synchronization
- [x] Sermon management (upload/download)
- [x] Error handling for network issues
- [x] Authentication integration

### Integration Workflow Tests ✅
- [x] Complete recording → upload → download cycle
- [x] Recording with pause/resume functionality
- [x] Authentication failure handling
- [x] Network failure recovery
- [x] Permission denied scenarios
- [x] Data persistence and sync workflows
- [x] Error recovery with retry logic
- [x] Concurrent operation handling

### UI Tests ✅
- [x] App launch and stability
- [x] Basic navigation without crashes
- [x] Memory management across sessions
- [x] Performance under load
- [x] Launch performance metrics
- [x] Responsiveness testing

## Mock Services

### MockAuthService
**Purpose**: Tests authentication flows without network dependencies
**Features**:
- Configurable success/failure responses
- User state management
- Session simulation
- Error condition testing

### MockRecordingService  
**Purpose**: Tests audio recording without hardware requirements
**Features**:
- Recording state simulation
- Duration tracking with timers
- Permission state control
- Error injection capabilities
- Publisher state updates

### MockSupabaseService
**Purpose**: Tests backend operations without network calls
**Features**:
- In-memory file storage simulation
- User profile management
- Sermon data management
- Configurable error responses
- Data persistence simulation

## Critical Test Scenarios

### Beta Testing Confidence Tests

1. **Authentication Flow** (AuthServiceTests)
   - User registration and login
   - Session management
   - Profile updates

2. **Recording Workflow** (RecordingServiceTests + RecordingWorkflowTests)
   - Complete recording session
   - File management and upload
   - Error recovery

3. **Data Persistence** (SupabaseServiceTests + RecordingWorkflowTests)
   - Local data management
   - Cloud synchronization
   - User data isolation

4. **Error Handling** (All test suites)
   - Network failures
   - Permission denials
   - Authentication errors
   - Resource limitations

### Performance and Stability Tests

1. **Memory Management** (UI Tests)
   - Multiple app launches
   - Long recording sessions
   - Background/foreground transitions

2. **Responsiveness** (UI Tests)
   - UI interaction speed
   - Load handling
   - Concurrent operations

3. **Launch Performance** (UI Tests)
   - Cold start times
   - Warm start performance
   - Resource initialization

## Test Configuration

### Test Environment Setup
```swift
// Example test setup
private func setupTest() async throws {
    // Reset all services
    mockRecordingService.resetState()
    mockSupabaseService.clearMockData()
    
    // Sign in a test user
    _ = try await mockAuthService.signIn(email: "test@example.com", password: "password123")
}
```

### Error Injection
```swift
// Configure service to fail next call
mockAuthService.setShouldFailNextCall(true, error: AuthError.networkError)

// Test the error scenario
await #expect(throws: AuthError.self) {
    try await mockAuthService.signIn(email: "test@example.com", password: "password123")
}
```

## Beta Testing Checklist

Before releasing to beta testers, ensure all tests pass:

### Must-Pass Tests ✅
- [ ] All AuthServiceTests pass
- [ ] All RecordingServiceTests pass  
- [ ] All SupabaseServiceTests pass
- [ ] All RecordingWorkflowTests pass
- [ ] Basic UI stability tests pass

### Performance Validation ✅
- [ ] Launch time < 3 seconds
- [ ] Memory usage stable across sessions
- [ ] No crashes during basic workflows
- [ ] Recording performance acceptable

### Error Handling Validation ✅
- [ ] Network failure recovery
- [ ] Permission denial handling
- [ ] Authentication error recovery
- [ ] File system error handling

## Continuous Integration

### Automated Testing
```yaml
# Example GitHub Actions workflow
name: iOS Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: |
          xcodebuild test \
            -scheme TabletNotes \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            -resultBundlePath TestResults
```

### Test Reporting
- **Coverage Reports**: Generate test coverage metrics
- **Performance Baselines**: Track performance regression
- **Failure Analysis**: Automated failure categorization

## Adding New Tests

### For New Services
1. Create mock implementation following existing patterns
2. Add comprehensive unit tests
3. Include integration tests for service interactions
4. Update this documentation

### For New UI Features
1. Add UI element identification
2. Create user flow tests
3. Include accessibility validation
4. Test error states and edge cases

### Test Naming Convention
```swift
// Unit Tests
func testMethodNameWithSpecificCondition() async throws
func testMethodNameFailureScenario() async throws

// Integration Tests  
func testCompleteWorkflowName() async throws
func testWorkflowNameWithErrorCondition() async throws

// UI Tests
func testUIFlowName() throws
func testUIElementAccessibility() throws
```

## Troubleshooting

### Common Test Issues

1. **Test Timeouts**
   - Check async/await usage
   - Verify mock timer configurations
   - Increase timeout values if needed

2. **Publisher Tests Failing**
   - Ensure proper publisher subscription
   - Add delays for publisher emissions
   - Check cancellable management

3. **UI Tests Flaky**
   - Add element existence checks
   - Use waitForExistence for dynamic elements
   - Verify simulator state consistency

### Debugging Tests
```swift
// Add debug logging
print("Test state: \(mockService.currentState)")

// Verify expectations
#expect(condition, "Detailed failure message")

// Break on test failures
// Add breakpoints in test methods for debugging
```

## Future Testing Enhancements

### Phase 2 (Post-Beta)
- [ ] Property-based testing for edge cases
- [ ] Performance regression testing
- [ ] Device-specific testing (iPad, different iOS versions)
- [ ] Network condition simulation
- [ ] Battery usage testing

### Phase 3 (Production)
- [ ] A/B testing infrastructure
- [ ] User behavior analytics integration
- [ ] Crash reporting and analysis
- [ ] Real user monitoring (RUM)

This testing implementation provides a solid foundation for beta testing confidence while ensuring the app's core functionality is thoroughly validated.