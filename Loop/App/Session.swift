//
//  Session.swift
//  Loop
//
//  Holds the currently authenticated user's identity for the app. Until the
//  auth layer (a later task) is wired up, it defaults to a local placeholder so
//  the app is usable during development. Repositories are scoped by
//  `ownerUserId`.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSession {
    /// Identifier used to scope all local records. Set to the authenticated
    /// user's id by `AuthService`; falls back to a local placeholder before sign-in.
    var ownerUserId: String

    init(ownerUserId: String = AppSession.localPlaceholderUserId) {
        self.ownerUserId = ownerUserId
    }

    /// Placeholder owner used before authentication exists.
    static let localPlaceholderUserId = "local-user"
}
