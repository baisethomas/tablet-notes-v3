import SwiftUI

struct AccountView: View {
    @Environment(\.authManager) private var authManager
    @State private var showingEditProfile = false
    @State private var showingAbout = false
    @State private var showingPrivacyPolicy = false
    @State private var showingTerms = false
    @State private var showingSupport = false
    @State private var showingSignOutAlert = false
    @State private var isSigningOut = false
    
    let onBack: () -> Void
    let onNavigateToSettings: (() -> Void)?
    
    private var currentUser: User? {
        authManager.currentUser
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.adaptiveAccent)
                    }
                    
                    Spacer()
                    
                    Text("Account")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.adaptivePrimaryText)
                    
                    Spacer()
                    
                    // Placeholder for balance
                    Color.clear
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.navigationBackground)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile Section
                        VStack(spacing: 16) {
                            // Profile picture and basic info
                            VStack(spacing: 12) {
                                Circle()
                                    .fill(Color.adaptiveAccent.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 36))
                                            .foregroundColor(.adaptiveAccent)
                                    )
                                
                                VStack(spacing: 4) {
                                    Text(currentUser?.name ?? "User")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.adaptivePrimaryText)
                                    
                                    Text(currentUser?.email ?? "user@example.com")
                                        .font(.subheadline)
                                        .foregroundColor(.adaptiveSecondaryText)
                                    
                                    if let user = currentUser {
                                        HStack(spacing: 8) {
                                            if user.isEmailVerified {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "checkmark.seal.fill")
                                                        .font(.caption)
                                                        .foregroundColor(.successGreen)
                                                    Text("Verified")
                                                        .font(.caption)
                                                        .foregroundColor(.successGreen)
                                                }
                                            } else {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                        .font(.caption)
                                                        .foregroundColor(.warningOrange)
                                                    Text("Verify Email")
                                                        .font(.caption)
                                                        .foregroundColor(.warningOrange)
                                                }
                                            }
                                            
                                            Text("•")
                                                .font(.caption)
                                                .foregroundColor(.adaptiveSecondaryText)
                                            
                                            Text(user.subscriptionTier.capitalized)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.adaptiveSecondaryText)
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                                
                                Button("Edit Profile") {
                                    showingEditProfile = true
                                }
                                .font(.subheadline)
                                .foregroundColor(.adaptiveAccent)
                            }
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity)
                            .background(Color.adaptiveCardBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.adaptiveBorder, lineWidth: 1)
                            )
                        }
                        
                        // Account Settings Section
                        VStack(spacing: 0) {
                            AccountSectionHeader(title: "Account Settings")
                            
                            VStack(spacing: 0) {
                                AccountRowView(
                                    icon: "bell",
                                    title: "Notifications",
                                    subtitle: "Push notifications and alerts"
                                ) {
                                    // Handle notifications
                                }
                                
                                Divider()
                                    .padding(.leading, 52)
                                
                                AccountRowView(
                                    icon: "key",
                                    title: "Security",
                                    subtitle: "Password and account security"
                                ) {
                                    // Handle account security
                                }
                                
                                Divider()
                                    .padding(.leading, 52)
                                
                                AccountRowView(
                                    icon: "square.and.arrow.down",
                                    title: "Export My Data",
                                    subtitle: "Download your account data"
                                ) {
                                    // Handle data export
                                }
                            }
                            .background(Color.adaptiveCardBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.adaptiveBorder, lineWidth: 1)
                            )
                        }
                        
                        // Support & Feedback Section
                        VStack(spacing: 0) {
                            AccountSectionHeader(title: "Support & Feedback")
                            
                            VStack(spacing: 0) {
                                AccountRowView(
                                    icon: "questionmark.circle",
                                    title: "Help Center",
                                    subtitle: "Get help with your account and billing"
                                ) {
                                    showingSupport = true
                                }
                                
                                Divider()
                                    .padding(.leading, 52)
                                
                                AccountRowView(
                                    icon: "envelope",
                                    title: "Contact Support",
                                    subtitle: "Get in touch with our support team"
                                ) {
                                    // Handle contact support
                                }
                                
                                Divider()
                                    .padding(.leading, 52)
                                
                                AccountRowView(
                                    icon: "star",
                                    title: "Rate TabletNotes",
                                    subtitle: "Share your experience on the App Store"
                                ) {
                                    // Handle app rating
                                }
                                
                                Divider()
                                    .padding(.leading, 52)
                                
                                AccountRowView(
                                    icon: "bubble.left.and.bubble.right",
                                    title: "Send Feedback",
                                    subtitle: "Help us improve TabletNotes"
                                ) {
                                    // Handle feedback
                                }
                            }
                            .background(Color.adaptiveCardBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.adaptiveBorder, lineWidth: 1)
                            )
                        }
                        
                        // Legal & Privacy Section
                        VStack(spacing: 0) {
                            AccountSectionHeader(title: "Legal & Privacy")
                            
                            VStack(spacing: 0) {
                                AccountRowView(
                                    icon: "doc.text",
                                    title: "Privacy Policy",
                                    subtitle: "How we protect and handle your data"
                                ) {
                                    showingPrivacyPolicy = true
                                }
                                
                                Divider()
                                    .padding(.leading, 52)
                                
                                AccountRowView(
                                    icon: "doc.plaintext",
                                    title: "Terms of Service",
                                    subtitle: "Terms and conditions of use"
                                ) {
                                    showingTerms = true
                                }
                                
                                Divider()
                                    .padding(.leading, 52)
                                
                                AccountRowView(
                                    icon: "building.2",
                                    title: "About Our Company",
                                    subtitle: "Learn about TabletNotes team"
                                ) {
                                    showingAbout = true
                                }
                            }
                            .background(Color.adaptiveCardBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.adaptiveBorder, lineWidth: 1)
                            )
                        }
                        
                        // App Settings Section
                        VStack(spacing: 0) {
                            AccountSectionHeader(title: "More Options")
                            
                            VStack(spacing: 0) {
                                AccountRowView(
                                    icon: "gearshape",
                                    title: "App Settings",
                                    subtitle: "Recording, transcription, and app preferences"
                                ) {
                                    onNavigateToSettings?()
                                }
                            }
                            .background(Color.adaptiveCardBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.adaptiveBorder, lineWidth: 1)
                            )
                        }
                        
                        // Sign Out Section
                        VStack(spacing: 0) {
                            Button(action: {
                                if !isSigningOut {
                                    showingSignOutAlert = true
                                }
                            }) {
                                HStack {
                                    if isSigningOut {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .recordingRed))
                                            .scaleEffect(0.8)
                                            .frame(width: 24, height: 24)
                                    } else {
                                        Image(systemName: "arrow.right.square")
                                            .font(.title3)
                                            .foregroundColor(.recordingRed)
                                            .frame(width: 24, height: 24)
                                    }
                                    
                                    Text(isSigningOut ? "Signing Out..." : "Sign Out")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.recordingRed)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .background(Color.adaptiveCardBackground)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.adaptiveBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isSigningOut)
                        }
                        
                        // App Version Footer
                        VStack(spacing: 8) {
                            Text("TabletNotes")
                                .font(.caption)
                                .foregroundColor(.adaptiveSecondaryText)
                            
                            Text(AppVersion.shortVersion)
                                .font(.caption2)
                                .foregroundColor(.adaptiveSecondaryText)
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 100) // Extra padding for footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
                .background(Color.adaptiveBackground)
            }
            .navigationBarHidden(true)
            .background(Color.adaptiveBackground)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(user: currentUser)
        }
        .sheet(isPresented: $showingAbout) {
            AppAboutView()
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            WebView(url: "https://yourapp.com/privacy")
        }
        .sheet(isPresented: $showingTerms) {
            WebView(url: "https://yourapp.com/terms")
        }
        .sheet(isPresented: $showingSupport) {
            SupportView()
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }
    
    // MARK: - Private Methods
    
    private func signOut() {
        isSigningOut = true
        
        Task {
            do {
                print("[AccountView] Starting sign out process...")
                try await authManager.signOut()
                print("[AccountView] Sign out successful")
                
                await MainActor.run {
                    isSigningOut = false
                    // Navigation back to auth screen will happen automatically
                    // via the AuthenticationRequired modifier
                }
            } catch {
                print("[AccountView] Sign out failed: \(error.localizedDescription)")
                await MainActor.run {
                    isSigningOut = false
                    // Could show an error alert here, but sign out should rarely fail
                    // For now, we'll just reset the loading state
                }
            }
        }
    }
}

// MARK: - Account Section Header
struct AccountSectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.adaptivePrimaryText)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Account Row View
struct AccountRowView: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.adaptiveAccent)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.adaptivePrimaryText)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.adaptiveSecondaryText)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.adaptiveSecondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Edit Profile View
struct EditProfileView: View {
    let user: User?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.authManager) private var authManager
    
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Personal Information") {
                    TextField("Name", text: $name)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isLoading ? "Saving..." : "Save") {
                        saveProfile()
                    }
                    .fontWeight(.semibold)
                    .disabled(isLoading || !isFormValid)
                }
            }
        }
        .onAppear {
            // Pre-populate with current user data
            if let user = user {
                name = user.name
                email = user.email
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        email.contains("@")
    }
    
    private func saveProfile() {
        guard isFormValid else { return }
        
        isLoading = true
        
        Task {
            do {
                let updatedUser = try await authManager.updateProfile(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
                
                print("[EditProfileView] Profile updated successfully: \(updatedUser.name)")
                
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
                
                print("[EditProfileView] Profile update failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - App About View
struct AppAboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // App Icon
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)
                    
                    VStack(spacing: 8) {
                        Text("TabletNotes")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(AppVersion.shortVersion)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(spacing: 16) {
                        Text("TabletNotes is built by a team passionate about helping churches and organizations capture and share their messages more effectively.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 8) {
                            Text("Our Mission:")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text("To make sermon content more accessible and shareable through the power of AI, helping churches reach and serve their communities better.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        VStack(spacing: 8) {
                            Text("Contact Information:")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Email: support@tabletnotes.app")
                                Text("• Website: www.tabletnotes.app")
                                Text("• Follow us on social media")
                                Text("• Based in the United States")
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Support View
struct SupportView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Text("Frequently Asked Questions")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 12) {
                            FAQItem(
                                question: "How do I change my account information?",
                                answer: "Tap 'Edit Profile' at the top of the Account screen to update your name and email address."
                            )
                            
                            FAQItem(
                                question: "How do I manage my notifications?",
                                answer: "Go to Account Settings > Notifications to customize your push notification preferences."
                            )
                            
                            FAQItem(
                                question: "How do I export my data?",
                                answer: "Use 'Export My Data' in Account Settings to download all your recordings, transcripts, and notes."
                            )
                            
                            FAQItem(
                                question: "How do I cancel my subscription?",
                                answer: "Contact our support team through 'Contact Support' and we'll help you manage your subscription."
                            )
                            
                            FAQItem(
                                question: "Is my data secure?",
                                answer: "Yes! All data is encrypted in transit and at rest. See our Privacy Policy for detailed information."
                            )
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
            .navigationTitle("Help & Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - FAQ Item
struct FAQItem: View {
    let question: String
    let answer: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(question)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                Text(answer)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }
}

// MARK: - Web View (placeholder)
struct WebView: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Web content would be loaded here")
                    .foregroundColor(.secondary)
                Text(url)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Web View")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    AccountView(onBack: {}, onNavigateToSettings: nil)
}