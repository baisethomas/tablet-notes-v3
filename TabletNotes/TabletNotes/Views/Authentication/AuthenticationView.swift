import SwiftUI

struct AuthenticationView: View {
    @Environment(\.authManager) private var authManager
    @State private var showingSignUp = false
    @State private var showingSignIn = false
    @State private var isSocialLoading = false
    @State private var activeSocialProvider: SocialAuthProvider?
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            Color.SV.surface.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 80)

                    // Logo + wordmark
                    VStack(spacing: 20) {
                        AppLogoView(size: 100, cornerRadius: 22)

                        VStack(spacing: 8) {
                            Text("Tablet Notes")
                                .font(.system(size: 34, weight: .bold, design: .serif))
                                .foregroundStyle(Color.SV.onSurface)

                            Text("Every sermon, remembered.")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.SV.onSurface.opacity(0.45))
                        }
                    }

                    Spacer().frame(height: 60)

                    // Primary actions
                    VStack(spacing: 14) {
                        Button {
                            showingSignUp = true
                        } label: {
                            Text("Get Started")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Color.SV.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            showingSignIn = true
                        } label: {
                            Text("Sign In")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.SV.onSurface.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 32)

                    Spacer().frame(height: 36)

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
                    .padding(.horizontal, 32)

                    Spacer().frame(height: 20)

                    // Social auth
                    VStack(spacing: 12) {
                        SocialAuthButton(
                            provider: .google,
                            isLoading: activeSocialProvider == .google && isSocialLoading
                        ) {
                            signInWithSocial(.google)
                        }
                        .disabled(isSocialLoading)

                        NativeAppleSignInButton(
                            authManager: authManager,
                            isLoading: activeSocialProvider == .apple && isSocialLoading,
                            onStart: {
                                if !isSocialLoading {
                                    activeSocialProvider = .apple
                                    isSocialLoading = true
                                }
                            },
                            onSuccess: {
                                isSocialLoading = false
                                activeSocialProvider = nil
                            },
                            onError: { message in
                                isSocialLoading = false
                                activeSocialProvider = nil
                                errorMessage = message
                                showingError = true
                            }
                        )
                    }
                    .padding(.horizontal, 32)

                    Spacer().frame(height: 44)

                    // Terms
                    VStack(spacing: 6) {
                        Text("BY CONTINUING YOU AGREE TO OUR")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(1)
                            .foregroundStyle(Color.SV.onSurface.opacity(0.28))

                        HStack(spacing: 6) {
                            Button("Terms of Service") { }
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.SV.primary.opacity(0.7))

                            Text("·")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.SV.onSurface.opacity(0.28))

                            Button("Privacy Policy") { }
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.SV.primary.opacity(0.7))
                        }
                    }

                    Spacer().frame(height: 48)
                }
            }
        }
        .sheet(isPresented: $showingSignUp) {
            SignUpView(authManager: authManager)
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView(authManager: authManager)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func signInWithSocial(_ provider: SocialAuthProvider) {
        guard !isSocialLoading else { return }
        guard provider == .google else { return }

        isSocialLoading = true
        activeSocialProvider = provider

        Task {
            do {
                _ = try await authManager.signInWithSocial(provider: provider)
                await MainActor.run {
                    isSocialLoading = false
                    activeSocialProvider = nil
                }
            } catch let error as AuthError {
                await MainActor.run {
                    isSocialLoading = false
                    activeSocialProvider = nil
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            } catch {
                await MainActor.run {
                    isSocialLoading = false
                    activeSocialProvider = nil
                    errorMessage = "Unable to continue with \(provider.displayName)"
                    showingError = true
                }
            }
        }
    }
}

#Preview {
    AuthenticationView()
}
