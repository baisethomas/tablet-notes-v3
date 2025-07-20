import SwiftUI

struct AuthenticationView: View {
    @StateObject private var authService = SupabaseAuthService()
    @State private var showingSignUp = false
    @State private var showingSignIn = false
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    // Background gradient
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.accentColor.opacity(0.1),
                            Color.white,
                            Color.accentColor.opacity(0.05)
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
                                        .fill(Color.white)
                                        .frame(width: 120, height: 120)
                                        .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
                                    
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.05))
                                        .frame(width: 110, height: 110)
                                    
                                    AppLogoView(size: 90, cornerRadius: 18)
                                }
                                
                                VStack(spacing: 12) {
                                    Text("Welcome to Tablet Notes")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.center)
                                    
                                    Text("Record, transcribe, and summarize your sermons with AI-powered insights")
                                        .font(.body)
                                        .foregroundColor(.secondary)
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
                                
                                Button(action: {
                                    showingSignIn = true
                                }) {
                                    HStack {
                                        Image(systemName: "person.fill")
                                        Text("Sign In")
                                    }
                                    .font(.headline)
                                    .foregroundColor(.accentColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(12)
                                }
                                
                                // Terms and privacy
                                VStack(spacing: 8) {
                                    Text("By continuing, you agree to our")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    HStack(spacing: 4) {
                                        Button("Terms of Service") {
                                            // Show terms
                                        }
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                        
                                        Text("and")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Button("Privacy Policy") {
                                            // Show privacy policy
                                        }
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
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
            SignUpView(authService: authService)
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView(authService: authService)
        }
    }
}

// MARK: - Feature Highlight Component
struct FeatureHighlight: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
