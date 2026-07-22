//
//  NextActionsBuilder.swift
//  Loop
//
//  Builds the derived Next Actions feed from a set of interactions. Shared by
//  `InteractionRepository.nextActions` and the Next Actions view so ordering and
//  filtering stay identical.
//

import Foundation

enum NextActionsBuilder {
    /// Produces the feed of pending follow-ups owned by `ownerUserId`: overdue
    /// first (oldest first), then upcoming ordered by soonest date.
    static func build(
        from interactions: [Interaction],
        ownerUserId: String,
        asOf now: Date
    ) -> [NextActionItem] {
        let items: [NextActionItem] = interactions.compactMap { interaction in
            guard interaction.ownerUserId == ownerUserId,
                  !interaction.isTombstoned,
                  interaction.followUpStatus == .pending,
                  let followUpDate = interaction.followUpDate,
                  let person = interaction.person,
                  !person.isTombstoned
            else { return nil }

            return NextActionItem(
                id: interaction.id,
                interaction: interaction,
                person: person,
                followUpDate: followUpDate,
                isOverdue: followUpDate < now
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.isOverdue != rhs.isOverdue {
                return lhs.isOverdue && !rhs.isOverdue
            }
            return lhs.followUpDate < rhs.followUpDate
        }
    }
}
