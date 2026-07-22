//
//  AuthView.swift
//  Loop
//
//  Sign-in screen shown when there is no active session. Offers Sign in with
//  Apple and Google. A developer email/password path (DEBUG only) is included so
//  auth and sync can be exercised against the local Supabase stack, where OAuth
//  providers aren't configured.
//

import SwiftUI
import AuthenticationServices
import CryptoKit

struct AuthView: View {
    @Environment(AuthService.self) private var authService

    @State private var currentNonce: String?
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Loop")
                    .font(.largeTitle).bold()
                Text("Never miss a follow-up again.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    let nonce = Self.randomNonceString()
                    currentNonce = nonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = Self.sha256(nonce)
                } onCompletion: { result in
                    handleAppleCompletion(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)

                Button(action: { Task { await authService.signInWithGoogle() } }) {
                    HStack {
                        Image(systemName: "globe")
                        Text("Sign in with Google")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.bordered)
            }

            #if DEBUG
            developerSignIn
            #endif

            if let errorMessage = authService.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: Apple

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                return
            }
            Task { await authService.signInWithApple(idToken: idToken, nonce: nonce) }
        case .failure:
            // User cancellation or error; nothing to surface aggressively.
            break
        }
    }

    // MARK: Developer email sign-in (DEBUG)

    #if DEBUG
    private var developerSignIn: some View {
        VStack(spacing: 8) {
            Divider().padding(.vertical, 8)
            Text("Developer sign-in")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
            // Plain TextField (not SecureField) in the DEBUG-only dev path avoids
            // the iOS "Save Password?" system prompt during UI tests.
            TextField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button("Sign In") {
                    Task { await authService.signInWithEmail(email, password: password) }
                }
                Button("Sign Up") {
                    Task { await authService.signUpWithEmail(email, password: password) }
                }
            }
            .buttonStyle(.bordered)
            .disabled(email.isEmpty || password.isEmpty)
        }
    }
    #endif

    // MARK: Nonce helpers

    private static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
