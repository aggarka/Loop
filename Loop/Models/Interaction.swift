//
//  Interaction.swift
//  Loop
//
//  A logged conversation with a person. Local-first SwiftData model carrying the
//  same sync metadata as `Person`.
//

import Foundation
import SwiftData

@Model
final class Interaction {
    /// Client-generated identifier. See `Person.id` for why no `.unique`
    /// constraint is used.
    var id: UUID
    var ownerUserId: String

    /// The person this interaction belongs to. Optional so SwiftData can manage
    /// the inverse relationship and cascade deletes.
    var person: Person?

    var date: Date

    /// Backing storage for `InteractionType` (see `type`).
    var typeRaw: String

    var notes: String
    var outcomes: String?

    /// AI-generated summary of the notes. Persisted (unlike drafts, which are
    /// transient). Nil until the user requests summarization.
    var aiSummary: String?

    var followUpDate: Date?

    /// Backing storage for `FollowUpStatus` (see `followUpStatus`).
    var followUpStatusRaw: String

    var createdAt: Date
    var updatedAt: Date

    // MARK: Sync metadata
    /// Sync tombstone. Named `isTombstoned` to avoid colliding with Core Data's
    /// `NSManagedObject.isDeleted`.
    var isTombstoned: Bool
    var syncedAt: Date?
    var dirty: Bool

    init(
        id: UUID = UUID(),
        ownerUserId: String,
        person: Person? = nil,
        date: Date = Date(),
        type: InteractionType,
        notes: String = "",
        outcomes: String? = nil,
        aiSummary: String? = nil,
        followUpDate: Date? = nil,
        followUpStatus: FollowUpStatus = .none,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isTombstoned: Bool = false,
        syncedAt: Date? = nil,
        dirty: Bool = true
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.person = person
        self.date = date
        self.typeRaw = type.rawValue
        self.notes = notes
        self.outcomes = outcomes
        self.aiSummary = aiSummary
        self.followUpDate = followUpDate
        self.followUpStatusRaw = followUpStatus.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isTombstoned = isTombstoned
        self.syncedAt = syncedAt
        self.dirty = dirty
    }

    /// Typed accessor for the stored `typeRaw` value.
    var type: InteractionType {
        get { InteractionType(rawValue: typeRaw) ?? .coffeeChat }
        set { typeRaw = newValue.rawValue }
    }

    /// Typed accessor for the stored `followUpStatusRaw` value.
    var followUpStatus: FollowUpStatus {
        get { FollowUpStatus(rawValue: followUpStatusRaw) ?? .none }
        set { followUpStatusRaw = newValue.rawValue }
    }

    /// True when this interaction has a pending follow-up whose date has passed.
    /// Derived, not stored.
    func isOverdue(asOf now: Date = Date()) -> Bool {
        guard followUpStatus == .pending, let followUpDate else { return false }
        return followUpDate < now
    }
}
