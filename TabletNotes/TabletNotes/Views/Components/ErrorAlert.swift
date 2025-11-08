import SwiftUI

// MARK: - Error Alert Model
struct ErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let primaryAction: AlertAction?
    let secondaryAction: AlertAction?
    let type: ErrorType
    
    enum ErrorType {
        case network
        case recording
        case permission
        case general
        
        var icon: String {
            switch self {
            case .network:
                return "wifi.exclamationmark"
            case .recording:
                return "mic.slash.fill"
            case .permission:
                return "lock.fill"
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
            case .general:
                return .warningOrange
            }
        }
    }
    
    struct AlertAction {
        let title: String
        let style: ActionStyle
        let handler: (() -> Void)?
        
        enum ActionStyle {
            case primary
            case secondary
            case destructive
            case cancel
        }
    }
    
    static func networkError(message: String, retry: (() -> Void)? = nil) -> ErrorAlert {
        ErrorAlert(
            title: "Network Error",
            message: message,
            primaryAction: retry.map { AlertAction(title: "Retry", style: .primary, handler: $0) },
            secondaryAction: AlertAction(title: "OK", style: .secondary, handler: nil),
            type: .network
        )
    }
    
    static func recordingError(message: String, retry: (() -> Void)? = nil) -> ErrorAlert {
        ErrorAlert(
            title: "Recording Error",
            message: message,
            primaryAction: retry.map { AlertAction(title: "Retry", style: .primary, handler: $0) },
            secondaryAction: AlertAction(title: "OK", style: .secondary, handler: nil),
            type: .recording
        )
    }
    
    static func permissionError(message: String, openSettings: (() -> Void)? = nil) -> ErrorAlert {
        ErrorAlert(
            title: "Permission Required",
            message: message,
            primaryAction: openSettings.map { AlertAction(title: "Settings", style: .primary, handler: $0) },
            secondaryAction: AlertAction(title: "Cancel", style: .cancel, handler: nil),
            type: .permission
        )
    }
    
    static func generalError(title: String, message: String, action: (() -> Void)? = nil) -> ErrorAlert {
        ErrorAlert(
            title: title,
            message: message,
            primaryAction: action.map { AlertAction(title: "OK", style: .primary, handler: $0) },
            secondaryAction: nil,
            type: .general
        )
    }
}

// MARK: - Error Alert View Modifier
struct ErrorAlertModifier: ViewModifier {
    @Binding var errorAlert: ErrorAlert?
    
    func body(content: Content) -> some View {
        content
            .alert(errorAlert?.title ?? "", isPresented: Binding(
                get: { errorAlert != nil },
                set: { if !$0 { errorAlert = nil } }
            )) {
                if let primaryAction = errorAlert?.primaryAction {
                    Button(primaryAction.title, role: primaryAction.style == .destructive ? .destructive : nil) {
                        primaryAction.handler?()
                        errorAlert = nil
                    }
                }
                
                if let secondaryAction = errorAlert?.secondaryAction {
                    Button(secondaryAction.title, role: secondaryAction.style == .cancel ? .cancel : nil) {
                        secondaryAction.handler?()
                        errorAlert = nil
                    }
                }
                
                // If no actions provided, add default OK button
                if errorAlert?.primaryAction == nil && errorAlert?.secondaryAction == nil {
                    Button("OK") {
                        errorAlert = nil
                    }
                }
            } message: {
                Text(errorAlert?.message ?? "")
            }
    }
}

extension View {
    func errorAlert(_ alert: Binding<ErrorAlert?>) -> some View {
        modifier(ErrorAlertModifier(errorAlert: alert))
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
            switch recordingError {
            case .limitExceeded(let reason):
                return reason
            case .permissionDenied:
                return "Microphone access is required to record. Please enable it in Settings > Privacy & Security > Microphone."
            case .audioSessionFailed:
                return "Unable to set up audio recording. Please close other audio apps and try again."
            case .recordingFailed:
                return "Recording failed to start. Please try again or restart the app if the problem persists."
            }
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
    
    static func errorAlert(from error: Error, retry: (() -> Void)? = nil) -> ErrorAlert {
        let nsError = error as NSError
        let message = userFriendlyMessage(from: error)
        
        // Determine error type
        if nsError.domain == NSURLErrorDomain {
            return .networkError(message: message, retry: retry)
        } else if error is RecordingError {
            return .recordingError(message: message, retry: retry)
        } else {
            return .generalError(title: "Error", message: message, action: retry)
        }
    }
}

