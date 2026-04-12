import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct SocialAuthButton: View {
    let provider: SocialAuthProvider
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.SV.onSurface))
                        .scaleEffect(0.8)
                } else {
                    socialIcon
                }

                Text("Continue with \(provider.displayName)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.SV.onSurface)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.SV.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.SV.onSurface.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var socialIcon: some View {
        Group {
            switch provider {
            case .google:
                Text("G")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color(red: 0.26, green: 0.52, blue: 0.96))
                    .clipShape(Circle())
            case .apple:
                Image(systemName: "apple.logo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.SV.onSurface)
                    .frame(width: 24, height: 24)
            }
        }
    }
}

struct NativeAppleSignInButton: View {
    let authManager: AuthenticationManager
    let isLoading: Bool
    let onStart: () -> Void
    let onSuccess: () -> Void
    let onError: (String) -> Void
    
    @State private var currentNonce: String?

    var body: some View {
        ZStack {
            SignInWithAppleButton(
                .continue,
                onRequest: configureAppleRequest,
                onCompletion: handleAppleCompletion
            )
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(isLoading)

            if isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.15))
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
        }
        .frame(height: 50)
    }
    
    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        onStart()
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }
    
    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            onError(error.localizedDescription)
            
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                onError("Invalid Apple Sign-In credential")
                return
            }
            
            guard
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                onError("Apple Sign-In did not return a valid identity token")
                return
            }
            
            let normalizedName = credential.fullName
                .map { PersonNameComponentsFormatter().string(from: $0) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
            let nonce = currentNonce
            
            Task {
                do {
                    _ = try await authManager.signInWithApple(
                        idToken: idToken,
                        nonce: nonce,
                        fullName: normalizedName
                    )
                    await MainActor.run {
                        currentNonce = nil
                        onSuccess()
                    }
                } catch let error as AuthError {
                    await MainActor.run {
                        currentNonce = nil
                        onError(error.localizedDescription)
                    }
                } catch {
                    await MainActor.run {
                        currentNonce = nil
                        onError(error.localizedDescription)
                    }
                }
            }
        }
    }
    
    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with status \(status)")
            }
            
            for random in randoms {
                if remainingLength == 0 {
                    break
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
