import SwiftUI

struct SignUpView: View {
    @ObservedObject var authService: SupabaseAuthService
    @Environment(\.dismiss) private var dismiss
    
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
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        AppLogoView(size: 60, cornerRadius: 12)
                        
                        VStack(spacing: 8) {
                            Text("Create Account")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Join thousands of churches using TabletNotes")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 20)
                    
                    // Form
                    VStack(spacing: 20) {
                        // Name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Full Name")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
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
                                .foregroundColor(.primary)
                            
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
                                .foregroundColor(.primary)
                            
                            SecureField("Create a password", text: $password)
                                .textFieldStyle(AuthTextFieldStyle())
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .password)
                                .onSubmit {
                                    focusedField = .confirmPassword
                                }
                            
                            Text("Must be at least 8 characters")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Confirm password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Password")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
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
                    
                    // Sign in link
                    HStack {
                        Text("Already have an account?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button("Sign In") {
                            dismiss()
                            // Navigate to sign in
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 32)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.accentColor)
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
                _ = try await authService.signUp(data: signUpData)
                
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
}

// MARK: - Auth Text Field Style
struct AuthTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
    }
}

#Preview {
    SignUpView(authService: SupabaseAuthService())
}