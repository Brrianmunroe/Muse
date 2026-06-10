import Foundation
import SwiftUI
import AuthenticationServices
import CryptoKit

enum AuthState: Equatable {
    case loading
    case signedOut
    case signedIn
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var state: AuthState = .loading
    @Published var email = ""
    @Published var password = ""
    @Published var errorMessage: String?
    @Published var isSignUp = false
    @Published var isPreviewMode = false

    private let authService = AuthService()
    private var currentNonce: String?

    init() {
        Task { await checkSession() }
    }

    func checkSession() async {
        if !authService.isConfigured {
            isPreviewMode = true
            state = .signedOut
            return
        }
        do {
            _ = try await authService.session()
            state = .signedIn
        } catch {
            state = .signedOut
        }
    }

    func enterPreview() {
        isPreviewMode = true
        state = .signedIn
    }

    func signInWithEmail() async {
        errorMessage = nil
        do {
            if isSignUp {
                try await authService.signUpWithEmail(email: email, password: password)
            } else {
                try await authService.signInWithEmail(email: email, password: password)
            }
            state = .signedIn
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce
            else {
                errorMessage = "Could not process Apple Sign-In"
                return
            }
            do {
                try await authService.signInWithApple(idToken: idToken, nonce: nonce)
                state = .signedIn
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        try? await authService.signOut()
        state = .signedOut
    }

    func prepareAppleSignIn() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            for random in randoms {
                if remainingLength == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
