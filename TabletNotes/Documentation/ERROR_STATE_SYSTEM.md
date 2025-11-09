# Error State UI System

## Overview

A comprehensive, consistent error state UI system with retry mechanisms has been implemented across the TabletNotes app. The system provides three display styles and supports various error types with consistent styling and retry functionality.

## Components

### ErrorStateView

The main error state component located in `TabletNotes/Views/Components/ErrorStateView.swift`.

**Features:**
- Three display styles: inline, fullScreen, and banner
- Support for multiple error types (network, recording, permission, transcription, upload, auth, general)
- Built-in retry mechanisms with loading states
- Consistent styling matching the app's design system
- Haptic feedback integration
- Dismiss functionality

### ErrorAlert

Modal alert component for critical errors, located in `TabletNotes/Views/Components/ErrorAlert.swift`.

**Features:**
- Native iOS alert presentation
- Retry support
- Conversion to ErrorState for inline display
- Integration with ErrorMessageFormatter

## Usage Examples

### Inline Error Display

```swift
@State private var errorState: ErrorState? = nil

// In your view body:
if let errorState = errorState {
    ErrorStateView(
        errorState: errorState,
        style: .inline,
        onDismiss: {
            errorState = nil
        }
    )
}

// Creating error state from an Error:
errorState = ErrorState.from(
    error,
    retry: {
        // Retry logic
        retryOperation()
    },
    secondaryAction: ErrorState.ErrorAction(
        title: "Cancel",
        action: {
            // Secondary action
        }
    )
)
```

### Full Screen Error Display

```swift
ErrorStateView(
    errorState: ErrorState(
        error: myError,
        title: "Operation Failed",
        message: "A detailed error message",
        type: .network,
        retryAction: {
            retryOperation()
        },
        secondaryAction: nil
    ),
    style: .fullScreen
)
```

### Banner Error Display

```swift
.errorState($errorState, style: .banner) {
    // Your content
}
```

### Using ErrorAlert (Modal)

```swift
@State private var errorAlert: ErrorAlert? = nil

// In your view:
.errorAlert($errorAlert)

// Creating error alert:
errorAlert = ErrorAlert.from(
    error,
    retry: {
        retryOperation()
    }
)
```

## Error Types

The system supports the following error types:

- **network**: Network connectivity issues
- **recording**: Audio recording failures
- **permission**: Permission denied errors
- **transcription**: Transcription service errors
- **upload**: File upload failures
- **auth**: Authentication errors
- **general**: Generic errors

Each type has:
- Custom icon
- Color scheme
- Default title

## Error Message Formatting

The `ErrorMessageFormatter` provides user-friendly error messages:

```swift
let message = ErrorMessageFormatter.userFriendlyMessage(from: error)
```

It handles:
- Network errors (NSURLErrorDomain)
- Recording errors (RecordingError)
- Transcription errors
- Upload errors
- Auth errors
- Generic errors with localized descriptions

## Integration Points

### Updated Views

1. **RecordingView**: Uses inline ErrorStateView for transcription processing errors
2. **SummaryView**: Uses fullScreen ErrorStateView for summary generation failures
3. **SermonDetailView**: Uses fullScreen ErrorStateView for transcription and summary errors

### Best Practices

1. **Use inline style** for errors within content areas
2. **Use fullScreen style** for critical errors that block the entire view
3. **Use banner style** for non-blocking notifications
4. **Always provide retry actions** when the operation can be retried
5. **Use ErrorAlert** for critical errors requiring immediate user attention

## Styling

The error state UI uses the app's adaptive color scheme:
- `warningOrange` for most error types
- `recordingRed` for recording errors
- Adaptive text colors for light/dark mode support
- Consistent corner radius (12px) and padding

## Accessibility

- Proper semantic colors
- Clear error messages
- Retry actions are clearly labeled
- Haptic feedback for user actions

## Migration Guide

To migrate existing error handling:

1. Replace custom error UI with `ErrorStateView`
2. Convert error objects using `ErrorState.from()`
3. Choose appropriate display style
4. Add retry logic where applicable
5. Remove duplicate error handling code

## Example: Complete Error Handling

```swift
struct MyView: View {
    @State private var errorState: ErrorState? = nil
    @State private var isLoading = false
    
    var body: some View {
        VStack {
            // Your content
        }
        .errorState($errorState, style: .inline)
        .onAppear {
            loadData()
        }
    }
    
    private func loadData() {
        isLoading = true
        Task {
            do {
                let data = try await fetchData()
                await MainActor.run {
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorState = ErrorState.from(
                        error,
                        retry: {
                            loadData()
                        }
                    )
                }
            }
        }
    }
}
```

