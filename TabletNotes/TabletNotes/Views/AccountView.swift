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
                                    title: "Rate Tablet Notes",
                                    subtitle: "Share your experience on the App Store"
                                ) {
                                    // Handle app rating
                                }
                                
                                Divider()
                                    .padding(.leading, 52)
                                
                                AccountRowView(
                                    icon: "bubble.left.and.bubble.right",
                                    title: "Send Feedback",
                                    subtitle: "Help us improve Tablet Notes"
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
                                    subtitle: "Learn about Tablet Notes team"
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 20) // Reduced padding since footer is removed
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
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showingTerms) {
            TermsOfServiceView()
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
                        Text("Tablet Notes")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(AppVersion.shortVersion)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(spacing: 16) {
                        Text("Tablet Notes is built by a team passionate about helping churches and organizations capture and share their messages more effectively.")
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

// MARK: - Terms of Service View
struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Terms of Service")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.bottom, 8)
                    
                    Group {
                        Text("Effective Date: July 17, 2025")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Last Updated: December 21, 2025")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    // Introduction
                    SectionView(
                        title: "Introduction",
                        content: "Welcome to Tablet Notes. These Terms of Service (\"Terms\") govern your use of our mobile application and related services (\"Service\"). By accessing or using Tablet Notes, you agree to be bound by these Terms. If you do not agree, please do not use the Service."
                    )
                    
                    // Acceptance of Terms
                    SectionView(
                        title: "Acceptance of Terms",
                        content: "By creating an account or using Tablet Notes, you confirm that you have read, understood, and agree to these Terms and our Privacy Policy."
                    )
                    
                    // Changes to Terms
                    SectionView(
                        title: "Changes to Terms",
                        content: "We may update these Terms from time to time. We will notify you of significant changes by email or app notification. Continued use of the Service after changes means you accept the new Terms."
                    )
                    
                    // User Accounts
                    VStack(alignment: .leading, spacing: 8) {
                        Text("User Accounts")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            BulletPoint(text: "You must provide accurate and complete information when creating an account.")
                            BulletPoint(text: "You are responsible for maintaining the confidentiality of your account credentials.")
                            BulletPoint(text: "You are responsible for all activities that occur under your account.")
                            BulletPoint(text: "Notify us immediately of any unauthorized use of your account.")
                        }
                    }
                    .padding(.bottom, 8)
                    
                    // Acceptable Use
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Acceptable Use")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            BulletPoint(text: "Do not use the Service for unlawful, harmful, or abusive purposes.")
                            BulletPoint(text: "Do not attempt to gain unauthorized access to the Service or its systems.")
                            BulletPoint(text: "Do not upload or share content that infringes on others' rights or is offensive.")
                            BulletPoint(text: "Do not interfere with or disrupt the Service or servers.")
                        }
                    }
                    .padding(.bottom, 8)
                    
                    // Intellectual Property
                    SectionView(
                        title: "Intellectual Property",
                        content: "All content, trademarks, and intellectual property on Tablet Notes are owned by us or our licensors. You may not use, copy, or distribute any content from the Service without our permission."
                    )
                    
                    // Disclaimers
                    SectionView(
                        title: "Disclaimers",
                        content: "The Service is provided \"as is\" and \"as available\" without warranties of any kind. We do not guarantee that the Service will be uninterrupted, error-free, or secure."
                    )
                    
                    // Limitation of Liability
                    SectionView(
                        title: "Limitation of Liability",
                        content: "To the fullest extent permitted by law, Tablet Notes and its affiliates are not liable for any indirect, incidental, special, or consequential damages arising from your use of the Service."
                    )
                    
                    // Termination
                    SectionView(
                        title: "Termination",
                        content: "We may suspend or terminate your access to the Service at any time, with or without notice, for any reason, including violation of these Terms."
                    )
                    
                    // Governing Law
                    SectionView(
                        title: "Governing Law",
                        content: "These Terms are governed by the laws of the United States and the State of [Your State], without regard to conflict of law principles."
                    )
                    
                    // Contact Information
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contact Information")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("If you have questions about these Terms, please contact us:")
                            .font(.body)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            BulletPoint(text: "Email: support@tabletnotes.io")
                            BulletPoint(text: "Website: https://www.tabletnotes.io/terms")
                        }
                    }
                    .padding(.bottom, 8)
                }
                .padding(20)
            }
            .navigationTitle("Terms of Service")
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

// MARK: - Privacy Policy View
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Tablet Notes Privacy Policy")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.bottom, 8)
                    
                    Group {
                        Text("Effective Date: July 17, 2025")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Last Updated: December 21, 2025")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    // Introduction
                    SectionView(
                        title: "Introduction",
                        content: "Tablet Notes (\"we,\" \"our,\" or \"us\") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application and related services."
                    )
                    
                    // Information We Collect
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Information We Collect")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        SubsectionView(
                            subtitle: "Personal Information You Provide",
                            bullets: [
                                "Account Information: Email address, display name (optional)",
                                "Audio Recordings: Sermon recordings and related notes you create",
                                "User-Generated Content: Notes, summaries, and annotations you add to recordings"
                            ]
                        )
                        
                        SubsectionView(
                            subtitle: "Automatically Collected Information",
                            bullets: [
                                "Usage Data: App usage patterns, feature usage, and performance metrics",
                                "Device Information: Device type, operating system version, app version",
                                "Technical Data: Crash reports, error logs (anonymized)"
                            ]
                        )
                        
                        SubsectionView(
                            subtitle: "Information from Third-Party Services",
                            bullets: [
                                "Transcription Data: Audio transcriptions processed by AssemblyAI",
                                "AI-Generated Content: Summaries generated by OpenAI services",
                                "Biblical References: Scripture lookups via Bible API"
                            ]
                        )
                    }
                    .padding(.bottom, 8)
                    
                    // How We Use Your Information
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How We Use Your Information")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        SubsectionView(
                            subtitle: "Primary Uses",
                            bullets: [
                                "Core Functionality: Recording, transcribing, and summarizing audio content",
                                "Cloud Storage: Syncing your data across devices securely",
                                "User Experience: Personalizing features and improving app performance",
                                "Support: Providing customer service and technical support"
                            ]
                        )
                        
                        SubsectionView(
                            subtitle: "Secondary Uses",
                            bullets: [
                                "Analytics: Understanding app usage to improve features (aggregated, anonymized data)",
                                "Communication: Sending important updates about your account or the service"
                            ]
                        )
                    }
                    .padding(.bottom, 8)
                    
                    // Data Processing and Storage
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Data Processing and Storage")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        SubsectionView(
                            subtitle: "Cloud Storage",
                            bullets: [
                                "Audio files are encrypted and stored securely using Supabase",
                                "Transcription processing occurs on secure AssemblyAI servers",
                                "AI summarization uses OpenAI's secure infrastructure",
                                "All data transmission uses industry-standard encryption (TLS 1.2+)"
                            ]
                        )
                        
                        SubsectionView(
                            subtitle: "Data Retention",
                            bullets: [
                                "Active Accounts: Data retained while your account is active",
                                "Deleted Content: Permanently deleted within 30 days of user deletion",
                                "Account Deletion: All user data deleted within 90 days of account closure"
                            ]
                        )
                        
                        SubsectionView(
                            subtitle: "Data Location",
                            bullets: [
                                "Primary storage: United States (Supabase infrastructure)",
                                "Processing: AssemblyAI (US), OpenAI (US), Bible API (US)",
                                "No international transfers outside approved service providers"
                            ]
                        )
                    }
                    .padding(.bottom, 8)
                    
                    // Third-Party Services
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Third-Party Services")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        SubsectionView(
                            subtitle: "Service Providers We Use",
                            bullets: [
                                "Supabase: Database and file storage",
                                "AssemblyAI: Audio transcription services",
                                "OpenAI: AI-powered summarization",
                                "Scripture API: Biblical reference lookups",
                                "Netlify: Backend API hosting"
                            ]
                        )
                        
                        SubsectionView(
                            subtitle: "Data Sharing",
                            bullets: [
                                "We do NOT sell your personal information",
                                "We do NOT share content with third parties except as necessary for core functionality",
                                "Service providers are bound by strict data protection agreements"
                            ]
                        )
                    }
                    .padding(.bottom, 8)
                    
                    // Your Rights and Choices
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Rights and Choices")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        SubsectionView(
                            subtitle: "Data Control",
                            bullets: [
                                "Access: View all your stored data through the app",
                                "Correction: Edit or update your information at any time",
                                "Deletion: Delete specific recordings or your entire account",
                                "Export: Download your data in a standard format"
                            ]
                        )
                        
                        SubsectionView(
                            subtitle: "Privacy Settings",
                            bullets: [
                                "Recording Permissions: Control microphone access",
                                "Sync Settings: Choose what data syncs to the cloud",
                                "Notification Preferences: Manage communication settings"
                            ]
                        )
                        
                        SubsectionView(
                            subtitle: "Account Management",
                            bullets: [
                                "Subscription Control: Manage your subscription tier",
                                "Data Portability: Export your content before canceling",
                                "Account Deletion: Permanently delete your account and all data"
                            ]
                        )
                    }
                    .padding(.bottom, 8)
                    
                    // Security Measures
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Security Measures")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        SubsectionView(
                            subtitle: "Technical Safeguards",
                            bullets: [
                                "Encryption: All data encrypted in transit and at rest",
                                "Authentication: Secure login with industry-standard protocols",
                                "Access Controls: Strict limits on who can access your data",
                                "Regular Audits: Ongoing security assessments and updates"
                            ]
                        )
                        
                        SubsectionView(
                            subtitle: "Your Security",
                            bullets: [
                                "Use strong, unique passwords",
                                "Keep your app updated to the latest version",
                                "Report any security concerns immediately"
                            ]
                        )
                    }
                    .padding(.bottom, 8)
                    
                    // Children's Privacy
                    SectionView(
                        title: "Children's Privacy",
                        content: "Tablet Notes is not intended for children under 13. We do not knowingly collect personal information from children under 13. If you believe we have collected information from a child under 13, please contact us immediately."
                    )
                    
                    // Changes to This Policy
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Changes to This Policy")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("We may update this Privacy Policy to reflect changes in our practices or legal requirements. We will:")
                            .font(.body)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            BulletPoint(text: "Notify you of significant changes via email or app notification")
                            BulletPoint(text: "Post the updated policy with a new effective date")
                            BulletPoint(text: "Maintain previous versions for your reference")
                        }
                    }
                    .padding(.bottom, 8)
                    
                    // Contact Information
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contact Information")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("If you have questions or concerns about this Privacy Policy:")
                            .font(.body)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            BulletPoint(text: "Email: privacy@tabletnotes.io")
                            BulletPoint(text: "Website: https://www.tabletnotes.io/privacy")
                        }
                        
                        Text("For data protection inquiries or to exercise your privacy rights, please use the contact information above.")
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(.top, 4)
                    }
                    .padding(.bottom, 8)
                    
                    // California Privacy Rights (CCPA)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("California Privacy Rights (CCPA)")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("If you are a California resident, you have additional rights:")
                            .font(.body)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            BulletPoint(text: "Right to know what personal information is collected")
                            BulletPoint(text: "Right to delete personal information")
                            BulletPoint(text: "Right to opt-out of sale (we don't sell your information)")
                            BulletPoint(text: "Right to non-discrimination for exercising your rights")
                        }
                    }
                    .padding(.bottom, 8)
                    
                    // International Users
                    SectionView(
                        title: "International Users",
                        content: "If you are located outside the United States, please note that your information will be transferred to and processed in the United States, where our servers are located and our service providers operate."
                    )
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    Text("This Privacy Policy is designed to comply with applicable privacy laws including CCPA, GDPR principles, and App Store requirements. By using Tablet Notes, you agree to the collection and use of information in accordance with this policy.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
                .padding(20)
            }
            .navigationTitle("Privacy Policy")
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

// MARK: - Privacy Policy Components
struct SectionView: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(content)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding(.bottom, 8)
    }
}

struct SubsectionView: View {
    let subtitle: String
    let bullets: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(subtitle)
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(bullets, id: \.self) { bullet in
                    BulletPoint(text: bullet)
                }
            }
        }
    }
}

struct BulletPoint: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body)
                .foregroundColor(.primary)
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    AccountView(onBack: {}, onNavigateToSettings: nil)
}