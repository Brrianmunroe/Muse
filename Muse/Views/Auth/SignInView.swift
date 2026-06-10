import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Text("Muse")
                    .font(MuseTheme.serif(48))
                Text("Your design inspiration library")
                    .font(.subheadline)
                    .foregroundStyle(MuseTheme.Semantic.textSecondary)
            }

            if authViewModel.isPreviewMode {
                previewModeSection
            } else {
                emailSection
                dividerWithText("or")
                    .padding(.horizontal, 32)
                appleSignInSection
            }

            if let error = authViewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .background(MuseTheme.Semantic.surfacePage.ignoresSafeArea())
    }

    private var previewModeSection: some View {
        VStack(spacing: 16) {
            Button {
                authViewModel.enterPreview()
            } label: {
                Text("Explore Muse")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(MuseTheme.Semantic.buttonPrimaryBg)

            Text("Preview mode — no Supabase configured yet")
                .font(.caption)
                .foregroundStyle(MuseTheme.Semantic.textSecondary)
        }
        .padding(.horizontal, 32)
    }

    private var emailSection: some View {
        VStack(spacing: 16) {
            TextField("Email", text: $authViewModel.email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)

            SecureField("Password", text: $authViewModel.password)
                .textFieldStyle(.roundedBorder)
                .textContentType(authViewModel.isSignUp ? .newPassword : .password)

            Button {
                Task { await authViewModel.signInWithEmail() }
            } label: {
                Text(authViewModel.isSignUp ? "Create Account" : "Sign In")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(MuseTheme.Semantic.buttonPrimaryBg)

            Button {
                authViewModel.isSignUp.toggle()
            } label: {
                Text(authViewModel.isSignUp
                     ? "Already have an account? Sign In"
                     : "Don't have an account? Create one")
                    .font(.footnote)
                    .foregroundStyle(MuseTheme.Semantic.textSecondary)
            }
        }
        .padding(.horizontal, 32)
    }

    private var appleSignInSection: some View {
        SignInWithAppleButton(.signIn) { request in
            let hashedNonce = authViewModel.prepareAppleSignIn()
            request.requestedScopes = [.email, .fullName]
            request.nonce = hashedNonce
        } onCompletion: { result in
            Task { await authViewModel.handleAppleSignIn(result) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .padding(.horizontal, 32)
    }

    private func dividerWithText(_ text: String) -> some View {
        HStack {
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            Text(text).font(.caption).foregroundStyle(MuseTheme.Semantic.textSecondary)
            Rectangle().frame(height: 1).foregroundStyle(.quaternary)
        }
    }
}
