import SwiftUI

struct SignInView: View {
    var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingForgotPassword = false
    @State private var showingResetSuccess = false
    
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
                // Background
                Color(colorScheme == .dark ? Color(red: 0.07, green: 0.11, blue: 0.18) : Color.white)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 16) {
                            AppLogoView(size: 60, cornerRadius: 12)
                            
                            VStack(spacing: 8) {
                                Text("Welcome Back")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color.primary)
                                
                                Text("Sign in to access your sermons and notes")
                                    .font(.subheadline)
                                    .foregroundColor(colorScheme == .dark ? Color(red: 0.70, green: 0.76, blue: 0.85) : Color.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 40)
                        
                        // Form
                        VStack(spacing: 20) {
                            // Email field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email Address")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color.primary)
                                
                                TextField("Enter your email", text: $email)
                                    .textFieldStyle(AuthTextFieldStyle())
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .email)
                                    .onSubmit {
                                        focusedField = .password
                                    }
                            }
                            
                            // Password field
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Password")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color.primary)
                                    
                                    Spacer()
                                    
                                    Button("Forgot?") {
                                        showingForgotPassword = true
                                    }
                                    .font(.caption)
                                    .foregroundColor(Color.accentColor)
                                }
                                
                                SecureField("Enter your password", text: $password)
                                    .textFieldStyle(AuthTextFieldStyle())
                                    .textContentType(.password)
                                    .focused($focusedField, equals: .password)
                                    .onSubmit {
                                        if isFormValid {
                                            signIn()
                                        }
                                    }
                            }
                        }
                        
                        // Sign in button
                        Button(action: signIn) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "person.fill")
                                    Text("Sign In")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isFormValid && !isLoading ? Color.accentColor : Color.gray)
                            .cornerRadius(12)
                        }
                        .disabled(!isFormValid || isLoading)
                        .padding(.top, 8)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                        
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
                        
                        // Create account button
                        Button(action: {
                            dismiss()
                            // Navigate to sign up
                        }) {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                Text("Create New Account")
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
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 32)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Color.accentColor)
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
        .alert("Password Reset Sent", isPresented: $showingResetSuccess) {
            Button("OK") { }
        } message: {
            Text("Check your email for instructions to reset your password.")
        }
    }
    
    private func signIn() {
        guard isFormValid else { return }
        
        isLoading = true
        focusedField = nil
        
        Task {
            do {
                _ = try await authManager.signIn(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                
                await MainActor.run {
                    isLoading = false
                    dismiss()
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

// MARK: - Forgot Password View
struct ForgotPasswordView: View {
    var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
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
                // Background
                Color(colorScheme == .dark ? Color(red: 0.07, green: 0.11, blue: 0.18) : Color.white)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 40))
                            .foregroundColor(Color.accentColor)
                        
                        VStack(spacing: 8) {
                            Text("Reset Password")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color.primary)
                            
                            Text("Enter your email address and we'll send you instructions to reset your password.")
                                .font(.subheadline)
                                .foregroundColor(colorScheme == .dark ? Color(red: 0.70, green: 0.76, blue: 0.85) : Color.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 40)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email Address")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color.primary)
                        
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(AuthTextFieldStyle())
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    
                    Button(action: resetPassword) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "paperplane.fill")
                                Text("Send Reset Link")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isEmailValid && !isLoading ? Color.accentColor : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(!isEmailValid || isLoading)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Spacer()
                }
                .padding(.horizontal, 32)
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Color.accentColor)
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Email Sent", isPresented: $showingSuccess) {
            Button("OK") {
                dismiss()
            }
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