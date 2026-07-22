//
//  DomainTypes.swift
//  Loop
//
//  Value types used to create/update domain models and to present derived
//  views, plus domain-level errors.
//

import Foundation

/// Input for creating or editing a `Person`.
struct PersonDraft {
    var name: String
    var company: String?
    var title: String?
    var email: String?
    var phone: String?
    var tags: [String]
    var source: PersonSource

    init(
        name: String,
        company: String? = nil,
        title: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        tags: [String] = [],
        source: PersonSource = .manual
    ) {
        self.name = name
        self.company = company
        self.title = title
        self.email = email
        self.phone = phone
        self.tags = tags
        self.source = source
    }
}

/// Input for creating an `Interaction` for a given person.
struct InteractionDraft {
    var date: Date
    var type: InteractionType
    var notes: String
    var outcomes: String?
    var followUpDate: Date?

    init(
        date: Date = Date(),
        type: InteractionType,
        notes: String = "",
        outcomes: String? = nil,
        followUpDate: Date? = nil
    ) {
        self.date = date
        self.type = type
        self.notes = notes
        self.outcomes = outcomes
        self.followUpDate = followUpDate
    }
}

/// A derived entry in the Next Actions feed. Not persisted.
struct NextActionItem: Identifiable {
    let id: UUID
    let interaction: Interaction
    let person: Person
    let followUpDate: Date
    let isOverdue: Bool
}

/// Errors surfaced by the domain/repository layer.
enum DomainError: LocalizedError, Equatable {
    case nameRequired

    var errorDescription: String? {
        switch self {
        case .nameRequired:
            return "A name is required to create a person."
        }
    }
}
