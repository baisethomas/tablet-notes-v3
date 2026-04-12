import SwiftUI

struct SignInView: View {
    var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingForgotPassword = false
    @State private var activeSocialProvider: SocialAuthProvider?

    @FocusState private var focusedField: Field?

    enum Field {
        case email, password
    }

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        email.contains("@") &&
        !password.isEmpty
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.SV.surface.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 48)

                        // Header
                        VStack(spacing: 16) {
                            AppLogoView(size: 56, cornerRadius: 12)

                            Text("Welcome Back")
                                .font(.system(size: 28, weight: .bold, design: .serif))
                                .foregroundStyle(Color.SV.onSurface)
                        }

                        Spacer().frame(height: 40)

                        // Form
                        VStack(spacing: 20) {
                            // Email
                            VStack(alignment: .leading, spacing: 6) {
                                Text("EMAIL ADDRESS")
                                    .font(.system(size: 11, weight: .medium))
                                    .tracking(1)
                                    .foregroundStyle(Color.SV.onSurface.opacity(0.4))

                                TextField("Enter your email", text: $email)
                                    .textFieldStyle(AuthTextFieldStyle())
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .email)
                                    .onSubmit { focusedField = .password }
                            }

                            // Password
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("PASSWORD")
                                        .font(.system(size: 11, weight: .medium))
                                        .tracking(1)
                                        .foregroundStyle(Color.SV.onSurface.opacity(0.4))

                                    Spacer()

                                    Button("Forgot?") {
                                        showingForgotPassword = true
                                    }
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.SV.primary)
                                }

                                SecureField("Enter your password", text: $password)
                                    .textFieldStyle(AuthTextFieldStyle())
                                    .textContentType(.password)
                                    .focused($focusedField, equals: .password)
                                    .onSubmit {
                                        if isFormValid { signIn() }
                                    }
                            }
                        }

                        Spacer().frame(height: 28)

                        // Sign in CTA
                        Button(action: signIn) {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Sign In")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(isFormValid && !isLoading ? Color.SV.primary : Color.SV.primary.opacity(0.35))
                            .clipShape(Capsule())
                        }
                        .disabled(!isFormValid || isLoading)
                        .buttonStyle(.plain)

                        Spacer().frame(height: 28)

                        // Or divider
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.SV.onSurface.opacity(0.1))
                                .frame(height: 1)
                            Text("or")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.SV.onSurface.opacity(0.35))
                            Rectangle()
                                .fill(Color.SV.onSurface.opacity(0.1))
                                .frame(height: 1)
                        }

                        Spacer().frame(height: 16)

                        // Social auth
                        VStack(spacing: 12) {
                            SocialAuthButton(
                                provider: .google,
                                isLoading: activeSocialProvider == .google && isLoading
                            ) {
                                signInWithSocial(.google)
                            }
                            .disabled(isLoading)

                            NativeAppleSignInButton(
                                authManager: authManager,
                                isLoading: activeSocialProvider == .apple && isLoading,
                                onStart: {
                                    if !isLoading {
                                        activeSocialProvider = .apple
                                        isLoading = true
                                    }
                                },
                                onSuccess: {
                                    isLoading = false
                                    activeSocialProvider = nil
                                    dismiss()
                                },
                                onError: { message in
                                    isLoading = false
                                    activeSocialProvider = nil
                                    errorMessage = message
                                    showingError = true
                                }
                            )
                        }

                        Spacer().frame(height: 32)

                        // New account link
                        Button {
                            dismiss()
                        } label: {
                            Text("New here? Create an account")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.SV.onSurface.opacity(0.45))
                        }
                        .buttonStyle(.plain)

                        Spacer().frame(height: 40)
                    }
                    .padding(.horizontal, 32)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingForgotPassword) {
            ForgotPasswordView(authManager: authManager)
        }
    }

    private func signIn() {
        guard isFormValid else { return }

        isLoading = true
        activeSocialProvider = nil
        focusedField = nil

        Task {
            do {
                _ = try await authManager.signIn(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                await MainActor.run {
                    isLoading = false
                    activeSocialProvider = nil
                    dismiss()
                }
            } catch let error as AuthError {
                await MainActor.run {
                    isLoading = false
                    activeSocialProvider = nil
                    errorMessage = error.localizedDescription ?? "An error occurred"
                    showingError = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    activeSocialProvider = nil
                    errorMessage = "An unexpected error occurred"
                    showingError = true
                }
            }
        }
    }

    private func signInWithSocial(_ provider: SocialAuthProvider) {
        guard !isLoading else { return }
        guard provider == .google else { return }

        isLoading = true
        activeSocialProvider = provider
        focusedField = nil

        Task {
            do {
                _ = try await authManager.signInWithSocial(provider: provider)
                await MainActor.run {
                    isLoading = false
                    activeSocialProvider = nil
                    dismiss()
                }
            } catch let error as AuthError {
                await MainActor.run {
                    isLoading = false
                    activeSocialProvider = nil
                    errorMessage = error.localizedDescription ?? "Unable to continue with \(provider.displayName)"
                    showingError = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    activeSocialProvider = nil
                    errorMessage = "Unable to continue with \(provider.displayName)"
                    showingError = true
                }
            }
        }
    }
}

// MARK: - Forgot Password View
struct ForgotPasswordView: View {
    var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false

    private var isEmailValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        email.contains("@")
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.SV.surface.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer().frame(height: 48)

                    VStack(spacing: 16) {
                        Image(systemName: "envelope")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(Color.SV.primary)

                        VStack(spacing: 8) {
                            Text("Reset Password")
                                .font(.system(size: 26, weight: .bold, design: .serif))
                                .foregroundStyle(Color.SV.onSurface)

                            Text("Enter your email and we'll send reset instructions.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }
                    }

                    Spacer().frame(height: 40)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("EMAIL ADDRESS")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(1)
                            .foregroundStyle(Color.SV.onSurface.opacity(0.4))

                        TextField("Enter your email", text: $email)
                            .textFieldStyle(AuthTextFieldStyle())
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }

                    Spacer().frame(height: 24)

                    Button(action: resetPassword) {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Send Reset Link")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(isEmailValid && !isLoading ? Color.SV.primary : Color.SV.primary.opacity(0.35))
                        .clipShape(Capsule())
                    }
                    .disabled(!isEmailValid || isLoading)
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 32)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Email Sent", isPresented: $showingSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Check your email for password reset instructions.")
        }
    }

    private func resetPassword() {
        guard isEmailValid else { return }

        isLoading = true

        Task {
            do {
                try await authManager.resetPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
                await MainActor.run {
                    isLoading = false
                    showingSuccess = true
                }
            } catch let error as AuthError {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription ?? "An error occurred"
                    showingError = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "An unexpected error occurred"
                    showingError = true
                }
            }
        }
    }
}

#Preview("Sign In") {
    SignInView(authManager: AuthenticationManager.shared)
}

#Preview("Forgot Password") {
    ForgotPasswordView(authManager: AuthenticationManager.shared)
}
