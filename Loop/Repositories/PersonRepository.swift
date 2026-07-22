//
//  PersonRepository.swift
//  Loop
//
//  Owns all persistence and derived-data logic for `Person`. Views and view
//  models go through this type rather than touching `ModelContext` directly, so
//  derived fields (`lastContactedDate`) and sync bookkeeping (`dirty`,
//  `updatedAt`) stay consistent.
//

import Foundation
import SwiftData

@MainActor
protocol PersonRepositoryProtocol {
    func create(_ draft: PersonDraft) throws -> Person
    func update(_ person: Person, with draft: PersonDraft) throws
    func touch(_ person: Person) throws
    func delete(_ person: Person) throws
    func search(query: String, tags: [String]) -> [Person]
    func all() -> [Person]
    func refreshLastContacted(for person: Person)
}

@MainActor
final class PersonRepository: PersonRepositoryProtocol {
    private let context: ModelContext
    private let ownerUserId: String

    init(context: ModelContext, ownerUserId: String) {
        self.context = context
        self.ownerUserId = ownerUserId
    }

    // MARK: Create / Update

    func create(_ draft: PersonDraft) throws -> Person {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DomainError.nameRequired }

        let person = Person(
            ownerUserId: ownerUserId,
            name: name,
            company: draft.company.normalized,
            title: draft.title.normalized,
            email: draft.email.normalized,
            phone: draft.phone.normalized,
            tags: draft.tags,
            source: draft.source
        )
        context.insert(person)
        try save()
        return person
    }

    /// Applies edited fields to an existing person and marks it dirty.
    func update(_ person: Person, with draft: PersonDraft) throws {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DomainError.nameRequired }

        person.name = name
        person.company = draft.company.normalized
        person.title = draft.title.normalized
        person.email = draft.email.normalized
        person.phone = draft.phone.normalized
        person.tags = draft.tags
        person.source = draft.source
        stampModified(person)
        try save()
    }

    /// Marks a person as modified without changing fields (e.g., after a tag
    /// toggle mutated in place by a view model).
    func touch(_ person: Person) throws {
        stampModified(person)
        try save()
    }

    // MARK: Delete (soft / tombstone)

    func delete(_ person: Person) throws {
        let now = Date()
        person.isTombstoned = true
        person.dirty = true
        person.updatedAt = now
        // Cascade tombstones so the person's interactions also propagate as
        // deleted through sync.
        for interaction in person.interactions where !interaction.isTombstoned {
            interaction.isTombstoned = true
            interaction.dirty = true
            interaction.updatedAt = now
        }
        try save()
    }

    // MARK: Queries

    func all() -> [Person] {
        let owner = ownerUserId
        let descriptor = FetchDescriptor<Person>(
            predicate: #Predicate { $0.ownerUserId == owner && $0.isTombstoned == false },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Matches `query` against name, company, and title (case-insensitive) and
    /// requires the person to carry all of the selected `tags`. Matching logic
    /// is shared with the People List view via `PersonFilter`.
    func search(query: String, tags: [String]) -> [Person] {
        all().filter { PersonFilter.matches($0, query: query, tags: tags) }
    }

    // MARK: Derived data

    /// Recomputes `lastContactedDate` as the newest non-deleted interaction date
    /// (or nil). Only marks the record dirty when the value actually changes.
    func refreshLastContacted(for person: Person) {
        let newValue = person.interactions
            .filter { !$0.isTombstoned }
            .map(\.date)
            .max()

        if person.lastContactedDate != newValue {
            person.lastContactedDate = newValue
            stampModified(person)
            try? save()
        }
    }

    // MARK: Helpers

    private func stampModified(_ person: Person) {
        person.updatedAt = Date()
        person.dirty = true
    }

    private func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }
}

private extension Optional where Wrapped == String {
    /// Trims whitespace and collapses empty strings to nil so optional text
    /// fields stay clean.
    var normalized: String? {
        guard let self else { return nil }
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
