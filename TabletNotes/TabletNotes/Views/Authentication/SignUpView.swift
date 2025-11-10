import SwiftUI

struct SignUpView: View {
    @ObservedObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    
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
                // Background
                Color(colorScheme == .dark ? Color(red: 0.07, green: 0.11, blue: 0.18) : Color.white)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 16) {
                            AppLogoView(size: 60, cornerRadius: 12)
                            
                            VStack(spacing: 8) {
                                Text("Create Account")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color.primary)
                                
                                Text("Join Tablet Notes to start recording and organizing your sermons")
                                    .font(.subheadline)
                                    .foregroundColor(colorScheme == .dark ? Color(red: 0.70, green: 0.76, blue: 0.85) : Color.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 40)
                        
                        // Form
                        VStack(spacing: 20) {
                            // Name field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Full Name")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color.primary)
                                
                                TextField("Enter your full name", text: $name)
                                    .textFieldStyle(AuthTextFieldStyle())
                                    .textContentType(.name)
                                    .autocapitalization(.words)
                                    .focused($focusedField, equals: .name)
                                    .onSubmit {
                                        focusedField = .email
                                    }
                            }
                            
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
                                Text("Password")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color.primary)
                                
                                SecureField("Create a password", text: $password)
                                    .textFieldStyle(AuthTextFieldStyle())
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .password)
                                    .onSubmit {
                                        focusedField = .confirmPassword
                                    }
                                
                                Text("Must be at least 8 characters")
                                    .font(.caption)
                                    .foregroundColor(colorScheme == .dark ? Color(red: 0.70, green: 0.76, blue: 0.85) : Color.secondary)
                            }
                            
                            // Confirm password field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Confirm Password")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(colorScheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.98) : Color.primary)
                                
                                SecureField("Confirm your password", text: $confirmPassword)
                                    .textFieldStyle(AuthTextFieldStyle())
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .confirmPassword)
                                    .onSubmit {
                                        if isFormValid {
                                            signUp()
                                        }
                                    }
                                
                                if !confirmPassword.isEmpty && password != confirmPassword {
                                    Text("Passwords don't match")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        // Sign up button
                        Button(action: signUp) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "person.badge.plus")
                                    Text("Create Account")
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
                        .disabled(isLoading)
                        
                        // Sign in link
                        HStack {
                            Text("Already have an account?")
                                .font(.subheadline)
                                .foregroundColor(colorScheme == .dark ? Color(red: 0.70, green: 0.76, blue: 0.85) : Color.secondary)
                            
                            Button("Sign In") {
                                dismiss()
                                // Navigate to sign in
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Color.accentColor)
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
        .alert("Account Created!", isPresented: $showingSuccess) {
            Button("Continue") {
                dismiss()
            }
        } message: {
            Text("Please check your email to verify your account before signing in.")
        }
    }
    
    private func signUp() {
        guard isFormValid else { return }
        
        isLoading = true
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
                    showingSuccess = true
                }
            } catch let error as AuthError {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
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
    
    private func signInWithGoogle() {
        isLoading = true
        focusedField = nil
        
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

// MARK: - Auth Text Field Style
struct AuthTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(colorScheme == .dark ? Color(red: 0.11, green: 0.17, blue: 0.26) : Color(.systemGray6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ? Color(red: 0.20, green: 0.29, blue: 0.42) : Color(.systemGray4), lineWidth: 1)
            )
    }
}

#Preview {
    SignUpView(authManager: AuthenticationManager.shared)
}