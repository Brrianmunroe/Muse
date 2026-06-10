import Foundation
import Supabase
import AuthenticationServices

final class AuthService {
    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseService.shared.client) {
        self.client = client
    }

    var isConfigured: Bool { client != nil }

    var currentUserId: UUID? {
        get async {
            guard let client else { return nil }
            return try? await client.auth.session.user.id
        }
    }

    func signInWithEmail(email: String, password: String) async throws {
        guard let client else { throw MuseError.notConfigured }
        try await client.auth.signIn(email: email, password: password)
    }

    func signUpWithEmail(email: String, password: String) async throws {
        guard let client else { throw MuseError.notConfigured }
        try await client.auth.signUp(email: email, password: password)
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        guard let client else { throw MuseError.notConfigured }
        try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    func signOut() async throws {
        guard let client else { return }
        try await client.auth.signOut()
    }

    func session() async throws -> Session {
        guard let client else { throw MuseError.notConfigured }
        return try await client.auth.session
    }
}

enum MuseError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured. Add your credentials to Info.plist."
        }
    }
}
