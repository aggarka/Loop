//
//  DomainEnums.swift
//  Loop
//
//  Domain enumerations shared by the SwiftData models. Stored on the models as
//  raw strings for forward compatibility and exposed through typed computed
//  properties.
//

import Foundation

/// How a `Person` record entered the app.
enum PersonSource: String, Codable, CaseIterable, Sendable {
    case manual
    case businessCard
    case contactsImport
}

/// The kind of interaction that was logged.
enum InteractionType: String, Codable, CaseIterable, Sendable {
    case coffeeChat
    case event
    case phoneCall
    case email
    case videoCall

    var displayName: String {
        switch self {
        case .coffeeChat: return "Coffee Chat"
        case .event: return "Event"
        case .phoneCall: return "Phone Call"
        case .email: return "Email"
        case .videoCall: return "Video Call"
        }
    }
}

/// Lifecycle of a follow-up attached to an interaction. `overdue` is *not*
/// stored; it is derived by comparing `followUpDate` to the current date.
enum FollowUpStatus: String, Codable, CaseIterable, Sendable {
    case none
    case pending
    case done
}
