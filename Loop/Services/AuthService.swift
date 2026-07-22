//
//  AuthService.swift
//  Loop
//
//  Wraps Supabase Auth. Tracks the authenticated user, drives `AppSession`'s
//  ownerUserId (which scopes all local data), and exposes sign-in (Apple,
//  Google, and email for local development), sign-out, and account deletion.
//

import Foundation
import Observation
import SwiftData
import Supabase

@MainActor
@Observable
final class AuthService {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn
    }

    private(set) var state: State = .loading
    var errorMessage: String?

    private let client: SupabaseClient?
    private let session: AppSession
    private let modelContainer: ModelContainer

    init(client: SupabaseClient?, session: AppSession, modelContainer: ModelContainer) {
        self.client = client
        self.session = session
        self.modelContainer = modelContainer
    }

    /// Starts observing auth state. Runs for the app's lifetime; the initial
    /// event restores any persisted session (Requirement 1.5).
    func bootstrap() async {
        guard let client else {
            // No backend configured: fall back to local placeholder owner.
            state = .signedOut
            return
        }
        for await change in client.auth.authStateChanges {
            apply(userID: change.session?.user.id.uuidString)
        }
    }

    private func apply(userID: String?) {
        if let userID {
            session.ownerUserId = userID
            state = .signedIn
        } else {
            session.ownerUserId = AppSession.localPlaceholderUserId
            state = .signedOut
        }
    }

    // MARK: Sign in

    /// Email/password sign-in. Primarily for local development, where OAuth
    /// providers aren't configured.
    func signInWithEmail(_ email: String, password: String) async {
        await perform { try await $0.auth.signIn(email: email, password: password) }
    }

    func signUpWithEmail(_ email: String, password: String) async {
        await perform { try await $0.auth.signUp(email: email, password: password) }
    }

    /// Native Sign in with Apple: exchanges the Apple identity token for a
    /// Supabase session.
    func signInWithApple(idToken: String, nonce: String) async {
        await perform {
            try await $0.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
        }
    }

    /// Google sign-in via the hosted OAuth flow (web). Requires the Google
    /// provider to be configured on the Supabase project.
    func signInWithGoogle() async {
        await perform { try await $0.auth.signInWithOAuth(provider: .google) }
    }

    // MARK: Session lifecycle

    func signOut() async {
        await perform { try await $0.auth.signOut() }
        clearLocalData()
    }

    /// Deletes the user's account: removes the auth identity (cascading to their
    /// rows) via a security-definer RPC, then clears local data (Requirement 2).
    func deleteAccount() async {
        guard let client else { return }
        do {
            try await client.rpc("delete_current_user").execute()
            clearLocalData()
            try? await client.auth.signOut()
        } catch {
            errorMessage = "Could not delete your account. Please try again."
        }
    }

    // MARK: Helpers

    /// Runs an auth operation, surfacing errors without crashing.
    private func perform(_ operation: (SupabaseClient) async throws -> Void) async {
        guard let client else {
            errorMessage = "Backend is not configured."
            return
        }
        errorMessage = nil
        do {
            try await operation(client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Removes all locally cached records for the previous user (Requirement 1.6).
    private func clearLocalData() {
        let context = modelContainer.mainContext
        try? context.delete(model: Interaction.self)
        try? context.delete(model: Person.self)
        try? context.save()
    }
}
