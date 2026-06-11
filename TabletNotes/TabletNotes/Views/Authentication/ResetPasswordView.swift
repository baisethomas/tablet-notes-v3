import SwiftUI

/// Presented after the user opens a password-recovery deep link and a
/// recovery session has been established. Lets them choose a new password.
struct ResetPasswordView: View {
    let onComplete: () -> Void

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSucceed = false

    private let authManager = AuthenticationManager.shared

    private var validationMessage: String? {
        if newPassword.isEmpty || confirmPassword.isEmpty { return nil }
        if newPassword.count < 8 { return "Password must be at least 8 characters." }
        if newPassword != confirmPassword { return "Passwords don't match." }
        return nil
    }

    private var canSubmit: Bool {
        !isSubmitting &&
        newPassword.count >= 8 &&
        newPassword == confirmPassword
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                    Text("Choose a New Password")
                        .font(.title3.bold())
                    Text("Enter a new password for your account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                VStack(spacing: 12) {
                    SecureField("New password", text: $newPassword)
                        .textContentType(.newPassword)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Confirm new password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .textFieldStyle(.roundedBorder)
                }

                if let message = validationMessage ?? errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if didSucceed {
                    Label("Password updated successfully!", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                Button(action: submit) {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Update Password")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)

                Spacer()
            }
            .padding(.horizontal, 24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }
                        .disabled(isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task {
            do {
                try await authManager.updatePassword(newPassword: newPassword)
                didSucceed = true
                isSubmitting = false
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                onComplete()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

#Preview {
    ResetPasswordView(onComplete: {})
}
