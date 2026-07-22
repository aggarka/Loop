//
//  Person.swift
//  Loop
//
//  A person in the user's network. Local-first SwiftData model that also carries
//  sync metadata used by the Supabase sync engine (added in a later task).
//

import Foundation
import SwiftData

@Model
final class Person {
    /// Client-generated identifier so records can be created offline and
    /// reconciled with the server without a round-trip. Uniqueness is guaranteed
    /// by UUID generation and enforced during sync; we intentionally avoid a
    /// SwiftData `.unique` constraint, whose find-or-merge-on-insert semantics
    /// orphan in-memory instances from the relationship graph.
    var id: UUID

    /// The authenticated user who owns this record. Scopes all local queries and
    /// maps to the `owner_user_id` column enforced by Row Level Security.
    var ownerUserId: String

    var name: String
    var company: String?
    var title: String?
    var email: String?
    var phone: String?
    var tags: [String]

    /// Backing storage for `PersonSource` (see `source`).
    var sourceRaw: String

    /// Derived from the most recent non-deleted interaction. Maintained by
    /// `PersonRepository`; never set directly by views.
    var lastContactedDate: Date?

    var createdAt: Date
    var updatedAt: Date

    // MARK: Sync metadata

    /// Soft-delete tombstone so deletes propagate through sync rather than being
    /// resurrected by a stale update from another device. Named `isTombstoned`
    /// (not `isDeleted`) to avoid colliding with Core Data's built-in
    /// `NSManagedObject.isDeleted`, which SwiftData sits on top of.
    var isTombstoned: Bool

    /// Last time this record was reconciled with the server.
    var syncedAt: Date?

    /// Whether there are local changes pending upload.
    var dirty: Bool

    @Relationship(deleteRule: .cascade, inverse: \Interaction.person)
    var interactions: [Interaction]

    init(
        id: UUID = UUID(),
        ownerUserId: String,
        name: String,
        company: String? = nil,
        title: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        tags: [String] = [],
        source: PersonSource = .manual,
        lastContactedDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isTombstoned: Bool = false,
        syncedAt: Date? = nil,
        dirty: Bool = true,
        interactions: [Interaction] = []
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.name = name
        self.company = company
        self.title = title
        self.email = email
        self.phone = phone
        self.tags = tags
        self.sourceRaw = source.rawValue
        self.lastContactedDate = lastContactedDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isTombstoned = isTombstoned
        self.syncedAt = syncedAt
        self.dirty = dirty
        self.interactions = interactions
    }

    /// Typed accessor for the stored `sourceRaw` value.
    var source: PersonSource {
        get { PersonSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    /// A short "Title at Company" line for list rows, omitting missing pieces.
    var subtitle: String? {
        switch (title, company) {
        case let (title?, company?): return "\(title) at \(company)"
        case let (title?, nil): return title
        case let (nil, company?): return company
        case (nil, nil): return nil
        }
    }
}
