import SwiftUI

// MARK: - Error State Model
struct ErrorState: Identifiable, Equatable {
    let id = UUID()
    let error: Error
    let title: String?
    let message: String
    let type: ErrorType
    let retryAction: (() -> Void)?
    let secondaryAction: ErrorAction?
    
    struct ErrorAction: Equatable {
        let title: String
        let action: () -> Void
        
        static func == (lhs: ErrorAction, rhs: ErrorAction) -> Bool {
            lhs.title == rhs.title
        }
    }
    
    enum ErrorType: Equatable {
        case network
        case recording
        case permission
        case transcription
        case upload
        case auth
        case general
        
        var icon: String {
            switch self {
            case .network:
                return "wifi.exclamationmark"
            case .recording:
                return "mic.slash.fill"
            case .permission:
                return "lock.fill"
            case .transcription:
                return "text.bubble.fill"
            case .upload:
                return "arrow.up.circle.fill"
            case .auth:
                return "person.crop.circle.badge.exclamationmark"
            case .general:
                return "exclamationmark.triangle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .network:
                return .warningOrange
            case .recording:
                return .recordingRed
            case .permission:
                return .warningOrange
            case .transcription:
                return .warningOrange
            case .upload:
                return .warningOrange
            case .auth:
                return .warningOrange
            case .general:
                return .warningOrange
            }
        }
        
        var defaultTitle: String {
            switch self {
            case .network:
                return "Network Error"
            case .recording:
                return "Recording Error"
            case .permission:
                return "Permission Required"
            case .transcription:
                return "Transcription Error"
            case .upload:
                return "Upload Error"
            case .auth:
                return "Authentication Error"
            case .general:
                return "Error"
            }
        }
    }
    
    static func == (lhs: ErrorState, rhs: ErrorState) -> Bool {
        lhs.id == rhs.id
    }
    
    static func from(_ error: Error, retry: (() -> Void)? = nil, secondaryAction: ErrorAction? = nil) -> ErrorState {
        let nsError = error as NSError
        let message = ErrorMessageFormatter.userFriendlyMessage(from: error)
        
        // Determine error type
        let errorType: ErrorType
        if nsError.domain == NSURLErrorDomain {
            errorType = .network
        } else if error is RecordingError {
            errorType = .recording
        } else if nsError.domain == "TranscriptionServiceError" || nsError.domain == "TranscriptionError" {
            errorType = .transcription
        } else if nsError.domain == "UploadFailed" {
            errorType = .upload
        } else if nsError.domain == "AuthError" {
            errorType = .auth
        } else {
            errorType = .general
        }
        
        return ErrorState(
            error: error,
            title: nil,
            message: message,
            type: errorType,
            retryAction: retry,
            secondaryAction: secondaryAction
        )
    }
}

// MARK: - Error State View Component
struct ErrorStateView: View {
    let errorState: ErrorState
    let style: DisplayStyle
    let onDismiss: (() -> Void)?
    
    enum DisplayStyle {
        case inline      // Compact card-style for inline display
        case fullScreen  // Full-screen centered display
        case banner      // Top banner style
    }
    
    @State private var isRetrying = false
    
    init(
        errorState: ErrorState,
        style: DisplayStyle = .inline,
        onDismiss: (() -> Void)? = nil
    ) {
        self.errorState = errorState
        self.style = style
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        switch style {
        case .inline:
            inlineView
        case .fullScreen:
            fullScreenView
        case .banner:
            bannerView
        }
    }
    
    // MARK: - Inline View
    private var inlineView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: errorState.type.icon)
                    .font(.title3)
                    .foregroundColor(errorState.type.color)
                    .frame(width: 24, height: 24)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(errorState.title ?? errorState.type.defaultTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.adaptivePrimaryText)
                    
                    Text(errorState.message)
                        .font(.caption)
                        .foregroundColor(.adaptiveSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                // Dismiss button (if available)
                if let onDismiss = onDismiss {
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        onDismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.adaptiveSecondaryText)
                    }
                }
            }
            
            // Actions
            if errorState.retryAction != nil || errorState.secondaryAction != nil {
                HStack(spacing: 12) {
                    if let retryAction = errorState.retryAction {
                        Button(action: {
                            handleRetry(retryAction)
                        }) {
                            HStack(spacing: 6) {
                                if isRetrying {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Retry")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(errorState.type.color)
                            .cornerRadius(8)
                        }
                        .disabled(isRetrying)
                    }
                    
                    if let secondaryAction = errorState.secondaryAction {
                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            secondaryAction.action()
                        }) {
                            Text(secondaryAction.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.adaptiveAccent)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.adaptiveAccent.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.adaptiveSecondaryBackground.opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(errorState.type.color.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Full Screen View
    private var fullScreenView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 20) {
                // Icon
                ZStack {
                    Circle()
                        .fill(errorState.type.color.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: errorState.type.icon)
                        .font(.system(size: 36))
                        .foregroundColor(errorState.type.color)
                }
                
                // Content
                VStack(spacing: 12) {
                    Text(errorState.title ?? errorState.type.defaultTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.adaptivePrimaryText)
                    
                    Text(errorState.message)
                        .font(.body)
                        .foregroundColor(.adaptiveSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            
            // Actions
            if errorState.retryAction != nil || errorState.secondaryAction != nil {
                VStack(spacing: 12) {
                    if let retryAction = errorState.retryAction {
                        Button(action: {
                            handleRetry(retryAction)
                        }) {
                            HStack(spacing: 8) {
                                if isRetrying {
                                    ProgressView()
                                        .scaleEffect(0.9)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Retry")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(errorState.type.color)
                            .cornerRadius(12)
                        }
                        .disabled(isRetrying)
                        .padding(.horizontal, 32)
                    }
                    
                    if let secondaryAction = errorState.secondaryAction {
                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            secondaryAction.action()
                        }) {
                            Text(secondaryAction.title)
                                .font(.headline)
                                .foregroundColor(.adaptiveAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.adaptiveAccent.opacity(0.1))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 32)
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.adaptiveBackground)
    }
    
    // MARK: - Banner View
    private var bannerView: some View {
        HStack(spacing: 12) {
            Image(systemName: errorState.type.icon)
                .font(.headline)
                .foregroundColor(errorState.type.color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(errorState.title ?? errorState.type.defaultTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.adaptivePrimaryText)
                
                Text(errorState.message)
                    .font(.caption)
                    .foregroundColor(.adaptiveSecondaryText)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if let retryAction = errorState.retryAction {
                Button(action: {
                    handleRetry(retryAction)
                }) {
                    if isRetrying {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: errorState.type.color))
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                            .foregroundColor(errorState.type.color)
                    }
                }
                .disabled(isRetrying)
            }
            
            if let onDismiss = onDismiss {
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.adaptiveSecondaryText)
                }
            }
        }
        .padding()
        .background(errorState.type.color.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 3)
                .foregroundColor(errorState.type.color),
            alignment: .top
        )
    }
    
    // MARK: - Helper Methods
    private func handleRetry(_ action: @escaping () -> Void) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        isRetrying = true
        
        // Execute retry action
        action()
        
        // Reset retrying state after a delay (in case action doesn't handle it)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isRetrying = false
        }
    }
}

// MARK: - Error State View Modifier
struct ErrorStateModifier: ViewModifier {
    @Binding var errorState: ErrorState?
    let style: ErrorStateView.DisplayStyle
    let onDismiss: (() -> Void)?
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if let errorState = errorState {
                ErrorStateView(
                    errorState: errorState,
                    style: style,
                    onDismiss: onDismiss ?? { self.errorState = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(1000)
            }
        }
    }
}

extension View {
    /// Adds an error state overlay to the view
    /// - Parameters:
    ///   - errorState: The error state to display (nil to hide)
    ///   - style: The display style (inline, fullScreen, or banner)
    ///   - onDismiss: Optional callback when error is dismissed
    func errorState(
        _ errorState: Binding<ErrorState?>,
        style: ErrorStateView.DisplayStyle = .fullScreen,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(ErrorStateModifier(
            errorState: errorState,
            style: style,
            onDismiss: onDismiss
        ))
    }
    
    /// Convenience method for displaying error inline
    func inlineErrorState(_ errorState: Binding<ErrorState?>, onDismiss: (() -> Void)? = nil) -> some View {
        self.errorState(errorState, style: .inline, onDismiss: onDismiss)
    }
    
    /// Convenience method for displaying error as banner
    func bannerErrorState(_ errorState: Binding<ErrorState?>, onDismiss: (() -> Void)? = nil) -> some View {
        self.errorState(errorState, style: .banner, onDismiss: onDismiss)
    }
}

// MARK: - Error Message Formatter
struct ErrorMessageFormatter {
    static func userFriendlyMessage(from error: Error) -> String {
        let nsError = error as NSError
        
        // Network errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection detected. Please check your Wi-Fi or cellular data and try again."
            case NSURLErrorNetworkConnectionLost:
                return "Your network connection was lost. Please check your connection and try again."
            case NSURLErrorTimedOut:
                return "The request took too long. This might be due to a slow connection. Please try again."
            case NSURLErrorCannotConnectToHost:
                return "Unable to connect to the server. Please check your internet connection."
            case NSURLErrorCannotFindHost:
                return "Could not find the server. Please check your internet connection."
            case NSURLErrorDNSLookupFailed:
                return "Network lookup failed. Please check your internet connection."
            default:
                return "A network error occurred. Please check your connection and try again."
            }
        }
        
        // Recording errors
        if let recordingError = error as? RecordingError {
            return recordingError.errorDescription ?? "A recording error occurred."
        }
        
        // Transcription errors
        if nsError.domain == "TranscriptionServiceError" || nsError.domain == "TranscriptionError" {
            if let userMessage = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                return userMessage
            }
            return "Transcription failed. Please check your internet connection and try again."
        }
        
        // Upload errors
        if nsError.domain == "UploadFailed" {
            return "Failed to upload audio file. Please check your internet connection and try again."
        }
        
        // Auth errors
        if nsError.domain == "AuthError" {
            return "Authentication failed. Please sign in again."
        }
        
        // Generic error with localized description
        if !error.localizedDescription.isEmpty && error.localizedDescription != "The operation couldn't be completed." {
            return error.localizedDescription
        }
        
        // Fallback
        return "An unexpected error occurred. Please try again."
    }
}

// MARK: - Recording Error Type
enum RecordingError: LocalizedError {
    case limitExceeded(reason: String)
    case permissionDenied
    case audioSessionFailed
    case recordingFailed
    case pauseFailed
    case resumeFailed
    
    var errorDescription: String? {
        switch self {
        case .limitExceeded(let reason):
            return reason
        case .permissionDenied:
            return "Microphone permission denied. Please enable microphone access in Settings > Privacy & Security > Microphone."
        case .audioSessionFailed:
            return "Unable to set up audio recording. Please close other audio apps and try again."
        case .recordingFailed:
            return "Recording failed to start. Please try again or restart the app if the problem persists."
        case .pauseFailed:
            return "Unable to pause recording. Please try again."
        case .resumeFailed:
            return "Unable to resume recording. Please try again."
        }
    }
}

