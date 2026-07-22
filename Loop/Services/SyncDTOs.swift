//
//  SyncDTOs.swift
//  Loop
//
//  Codable transfer objects mapping SwiftData models to the Supabase Postgres
//  columns (snake_case), plus conversion helpers.
//

import Foundation

struct PersonDTO: Codable {
    let id: UUID
    let owner_user_id: UUID
    var name: String
    var company: String?
    var title: String?
    var email: String?
    var phone: String?
    var tags: [String]
    var source: String
    var last_contacted_date: Date?
    var created_at: Date
    var updated_at: Date
    var is_tombstoned: Bool

    init?(_ person: Person) {
        guard let owner = UUID(uuidString: person.ownerUserId) else { return nil }
        id = person.id
        owner_user_id = owner
        name = person.name
        company = person.company
        title = person.title
        email = person.email
        phone = person.phone
        tags = person.tags
        source = person.sourceRaw
        last_contacted_date = person.lastContactedDate
        created_at = person.createdAt
        updated_at = person.updatedAt
        is_tombstoned = person.isTombstoned
    }
}

struct InteractionDTO: Codable {
    let id: UUID
    let owner_user_id: UUID
    let person_id: UUID
    var date: Date
    var type: String
    var notes: String
    var outcomes: String?
    var ai_summary: String?
    var follow_up_date: Date?
    var follow_up_status: String
    var created_at: Date
    var updated_at: Date
    var is_tombstoned: Bool

    init?(_ interaction: Interaction) {
        guard
            let owner = UUID(uuidString: interaction.ownerUserId),
            let personID = interaction.person?.id
        else { return nil }
        id = interaction.id
        owner_user_id = owner
        person_id = personID
        date = interaction.date
        type = interaction.typeRaw
        notes = interaction.notes
        outcomes = interaction.outcomes
        ai_summary = interaction.aiSummary
        follow_up_date = interaction.followUpDate
        follow_up_status = interaction.followUpStatusRaw
        created_at = interaction.createdAt
        updated_at = interaction.updatedAt
        is_tombstoned = interaction.isTombstoned
    }
}
