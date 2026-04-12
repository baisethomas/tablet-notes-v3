import SwiftUI

struct SignUpView: View {
    var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var activeSocialProvider: SocialAuthProvider?

    @FocusState private var focusedField: Field?

    enum Field {
        case name, email, password, confirmPassword
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        email.contains("@") &&
        password.count >= 8 &&
        password == confirmPassword
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

                            Text("Create Account")
                                .font(.system(size: 28, weight: .bold, design: .serif))
                                .foregroundStyle(Color.SV.onSurface)
                        }

                        Spacer().frame(height: 40)

                        // Form
                        VStack(spacing: 20) {
                            // Name
                            VStack(alignment: .leading, spacing: 6) {
                                Text("FULL NAME")
                                    .font(.system(size: 11, weight: .medium))
                                    .tracking(1)
                                    .foregroundStyle(Color.SV.onSurface.opacity(0.4))

                                TextField("Enter your full name", text: $name)
                                    .textFieldStyle(AuthTextFieldStyle())
                                    .textContentType(.name)
                                    .autocapitalization(.words)
                                    .focused($focusedField, equals: .name)
                                    .onSubmit { focusedField = .email }
                            }

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
                                Text("PASSWORD")
                                    .font(.system(size: 11, weight: .medium))
                                    .tracking(1)
                                    .foregroundStyle(Color.SV.onSurface.opacity(0.4))

                                SecureField("Create a password", text: $password)
                                    .textFieldStyle(AuthTextFieldStyle())
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .password)
                                    .onSubmit { focusedField = .confirmPassword }

                                Text("Must be at least 8 characters")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.SV.onSurface.opacity(0.35))
                            }

                            // Confirm password
                            VStack(alignment: .leading, spacing: 6) {
                                Text("CONFIRM PASSWORD")
                                    .font(.system(size: 11, weight: .medium))
                                    .tracking(1)
                                    .foregroundStyle(Color.SV.onSurface.opacity(0.4))

                                SecureField("Confirm your password", text: $confirmPassword)
                                    .textFieldStyle(AuthTextFieldStyle())
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .confirmPassword)
                                    .onSubmit {
                                        if isFormValid { signUp() }
                                    }

                                if !confirmPassword.isEmpty && password != confirmPassword {
                                    Text("Passwords don't match")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.SV.error)
                                }
                            }
                        }

                        Spacer().frame(height: 28)

                        // Create account CTA
                        Button(action: signUp) {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Create Account")
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

                        // Sign in link
                        Button {
                            dismiss()
                        } label: {
                            Text("Already have an account? Sign In")
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
        .alert("Account Created!", isPresented: $showingSuccess) {
            Button("Continue") { dismiss() }
        } message: {
            Text("Please check your email to verify your account before signing in.")
        }
    }

    private func signUp() {
        guard isFormValid else { return }

        isLoading = true
        activeSocialProvider = nil
        focusedField = nil

        let signUpData = SignUpData(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        Task {
            do {
                _ = try await authManager.signUp(data: signUpData)
                await MainActor.run {
                    isLoading = false
                    activeSocialProvider = nil
                    showingSuccess = true
                }
            } catch let error as AuthError {
                await MainActor.run {
                    isLoading = false
                    activeSocialProvider = nil
                    errorMessage = error.localizedDescription
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
                    errorMessage = error.localizedDescription
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

// MARK: - Auth Text Field Style
struct AuthTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.SV.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.SV.onSurface.opacity(0.12), lineWidth: 1)
            )
    }
}

#Preview {
    SignUpView(authManager: AuthenticationManager.shared)
}
