import SwiftUI

struct AuthenticationView: View {
    @Environment(\.authManager) private var authManager
    @State private var showingSignUp = false
    @State private var showingSignIn = false
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    // Background gradient
                    LinearGradient(
                        gradient: Gradient(colors: colorScheme == .dark ? [
                            Color(red: 0.07, green: 0.11, blue: 0.18), // Navy dark primary
                            Color(red: 0.10, green: 0.15, blue: 0.24), // Navy dark secondary
                            Color(red: 0.07, green: 0.11, blue: 0.18)  // Navy dark primary
                        ] : [
                            Color.white,
                            Color.gray.opacity(0.1),
                            Color.white
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    ScrollView {
                        VStack(spacing: 40) {
                            Spacer(minLength: geometry.size.height * 0.1)
                            
                            // Logo and branding
                            VStack(spacing: 24) {
                                // App Logo
                                ZStack {
                                    Circle()
                                        .fill(colorScheme == .dark ? Color(red: 0.14, green: 0.22, blue: 0.33) : Color.white)
                                        .frame(width: 120, height: 120)
                                        .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
                                    
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.1))
                                        .frame(width: 110, height: 110)
                                    
                                    AppLogoView(size: 90, cornerRadius: 18)
                                }
                                
                                VStack(spacing: 12) {
                                    Text("Welcome to Tablet Notes")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundColor(colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color.primary)
                                        .multilineTextAlignment(.center)
                                    
                                    Text("Record, transcribe, and summarize your sermons with AI-powered insights")
                                        .font(.body)
                                        .foregroundColor(colorScheme == .dark ? Color(red: 0.70, green: 0.76, blue: 0.85) : Color.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 20)
                                }
                            }
                            
                            // Features preview
                            VStack(spacing: 20) {
                                FeatureHighlight(
                                    icon: "mic.circle.fill",
                                    title: "High-Quality Recording",
                                    description: "Crystal clear audio capture with real-time note-taking"
                                )
                                
                                FeatureHighlight(
                                    icon: "text.bubble.fill",
                                    title: "AI Transcription",
                                    description: "Automatic transcription with speaker identification"
                                )
                                
                                FeatureHighlight(
                                    icon: "doc.text.fill",
                                    title: "Smart Summaries",
                                    description: "AI-generated key points and sermon summaries"
                                )
                                
                                FeatureHighlight(
                                    icon: "icloud.fill",
                                    title: "Cloud Sync",
                                    description: "Access your content across all your devices"
                                )
                            }
                            
                            // Action buttons
                            VStack(spacing: 16) {
                                Button(action: {
                                    showingSignUp = true
                                }) {
                                    HStack {
                                        Image(systemName: "person.badge.plus")
                                        Text("Create Account")
                                    }
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.accentColor)
                                    .cornerRadius(12)
                                }
                                .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                                
                                Button(action: {
                                    showingSignIn = true
                                }) {
                                    HStack {
                                        Image(systemName: "person.fill")
                                        Text("Sign In")
                                    }
                                    .font(.headline)
                                    .foregroundColor(Color.accentColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                
                                // Divider
                                HStack {
                                    Rectangle()
                                        .fill(colorScheme == .dark ? Color(red: 0.20, green: 0.29, blue: 0.42) : Color(.systemGray4))
                                        .frame(height: 1)
                                    
                                    Text("or")
                                        .font(.subheadline)
                                        .foregroundColor(colorScheme == .dark ? Color(red: 0.70, green: 0.76, blue: 0.85) : Color.secondary)
                                        .padding(.horizontal, 16)
                                    
                                    Rectangle()
                                        .fill(colorScheme == .dark ? Color(red: 0.20, green: 0.29, blue: 0.42) : Color(.systemGray4))
                                        .frame(height: 1)
                                }
                                .padding(.vertical, 8)
                                
                                // Google Sign In button
                                Button(action: signInWithGoogle) {
                                    HStack {
                                        Image(systemName: "globe")
                                            .font(.system(size: 18))
                                        Text("Continue with Google")
                                            .font(.headline)
                                    }
                                    .foregroundColor(colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(colorScheme == .dark ? Color(red: 0.14, green: 0.22, blue: 0.33) : Color(.systemGray6))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(colorScheme == .dark ? Color(red: 0.20, green: 0.29, blue: 0.42) : Color(.systemGray4), lineWidth: 1)
                                    )
                                }
                                
                                // Terms and privacy
                                VStack(spacing: 8) {
                                    Text("By continuing, you agree to our")
                                        .font(.caption)
                                        .foregroundColor(colorScheme == .dark ? Color(red: 0.70, green: 0.76, blue: 0.85) : Color.secondary)
                                    
                                    HStack(spacing: 4) {
                                        Button("Terms of Service") {
                                            // Show terms
                                        }
                                        .font(.caption)
                                        .foregroundColor(Color.accentColor)
                                        
                                        Text("and")
                                            .font(.caption)
                                            .foregroundColor(colorScheme == .dark ? Color(red: 0.70, green: 0.76, blue: 0.85) : Color.secondary)
                                        
                                        Button("Privacy Policy") {
                                            // Show privacy policy
                                        }
                                        .font(.caption)
                                        .foregroundColor(Color.accentColor)
                                    }
                                }
                                .padding(.top, 8)
                            }
                            .padding(.horizontal, 32)
                            
                            Spacer(minLength: 40)
                        }
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
    
    private func signInWithGoogle() {
        isLoading = true
        
        Task {
            do {
                _ = try await authManager.signInWithGoogle()
                // OAuth flow will complete via callback
                await MainActor.run {
                    isLoading = false
                }
            } catch let error as AuthError {
                await MainActor.run {
                    isLoading = false
                    // Don't show error for OAuth initiation - it's expected
                    if !error.localizedDescription.contains("OAuth flow initiated") {
                        errorMessage = error.localizedDescription ?? "An error occurred"
                        showingError = true
                    }
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

// MARK: - Feature Highlight Component
struct FeatureHighlight: View {
    let icon: String
    let title: String
    let description: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(Color.accentColor)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color.primary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(colorScheme == .dark ? Color(red: 0.70, green: 0.76, blue: 0.85) : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    AuthenticationView()
}
