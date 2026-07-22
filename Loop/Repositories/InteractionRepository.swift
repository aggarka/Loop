//
//  InteractionRepository.swift
//  Loop
//
//  Owns persistence for `Interaction` and the derived Next Actions feed. Keeps
//  the related person's `lastContactedDate` in sync through `PersonRepository`.
//

import Foundation
import SwiftData

@MainActor
protocol InteractionRepositoryProtocol {
    func create(_ draft: InteractionDraft, for person: Person) throws -> Interaction
    func update(_ interaction: Interaction, with draft: InteractionDraft) throws
    func delete(_ interaction: Interaction) throws
    func markFollowUpDone(_ interaction: Interaction) throws
    func timeline(for person: Person) -> [Interaction]
    func nextActions(asOf now: Date) -> [NextActionItem]
}

@MainActor
final class InteractionRepository: InteractionRepositoryProtocol {
    private let context: ModelContext
    private let ownerUserId: String
    private let personRepository: PersonRepositoryProtocol

    init(
        context: ModelContext,
        ownerUserId: String,
        personRepository: PersonRepositoryProtocol
    ) {
        self.context = context
        self.ownerUserId = ownerUserId
        self.personRepository = personRepository
    }

    // MARK: Create / Update / Delete

    func create(_ draft: InteractionDraft, for person: Person) throws -> Interaction {
        let interaction = Interaction(
            ownerUserId: ownerUserId,
            person: person,
            date: draft.date,
            type: draft.type,
            notes: draft.notes,
            outcomes: draft.outcomes,
            followUpDate: draft.followUpDate,
            followUpStatus: draft.followUpDate == nil ? .none : .pending
        )
        context.insert(interaction)
        try save()
        personRepository.refreshLastContacted(for: person)
        return interaction
    }

    func update(_ interaction: Interaction, with draft: InteractionDraft) throws {
        interaction.date = draft.date
        interaction.type = draft.type
        interaction.notes = draft.notes
        interaction.outcomes = draft.outcomes
        interaction.followUpDate = draft.followUpDate

        // Reconcile follow-up status with the presence of a date, preserving a
        // completed status if the user already marked it done.
        if draft.followUpDate == nil {
            interaction.followUpStatus = .none
        } else if interaction.followUpStatus == .none {
            interaction.followUpStatus = .pending
        }

        stampModified(interaction)
        try save()
        if let person = interaction.person {
            personRepository.refreshLastContacted(for: person)
        }
    }

    func delete(_ interaction: Interaction) throws {
        interaction.isTombstoned = true
        stampModified(interaction)
        try save()
        if let person = interaction.person {
            personRepository.refreshLastContacted(for: person)
        }
    }

    func markFollowUpDone(_ interaction: Interaction) throws {
        interaction.followUpStatus = .done
        stampModified(interaction)
        try save()
    }

    // MARK: Queries

    func timeline(for person: Person) -> [Interaction] {
        person.interactions
            .filter { !$0.isTombstoned }
            .sorted { $0.date > $1.date }
    }

    /// Derived feed of pending follow-ups: overdue first (oldest first), then
    /// upcoming ordered by soonest date.
    func nextActions(asOf now: Date = Date()) -> [NextActionItem] {
        let owner = ownerUserId
        let pendingRaw = FollowUpStatus.pending.rawValue
        let descriptor = FetchDescriptor<Interaction>(
            predicate: #Predicate {
                $0.ownerUserId == owner
                    && $0.isTombstoned == false
                    && $0.followUpStatusRaw == pendingRaw
                    && $0.followUpDate != nil
            }
        )

        let interactions = (try? context.fetch(descriptor)) ?? []
        return NextActionsBuilder.build(from: interactions, ownerUserId: owner, asOf: now)
    }

    // MARK: Helpers

    private func stampModified(_ interaction: Interaction) {
        interaction.updatedAt = Date()
        interaction.dirty = true
    }

    private func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }
}
