//
//  NextActionsView.swift
//  Loop
//
//  Home screen: a single feed of pending follow-ups split into Overdue and
//  Upcoming, with a swipe action to complete a follow-up and navigation to the
//  related person.
//

import SwiftUI
import SwiftData

struct NextActionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var syncEngine
    @Query private var allInteractions: [Interaction]

    private var feed: [NextActionItem] {
        NextActionsBuilder.build(
            from: allInteractions,
            ownerUserId: session.ownerUserId,
            asOf: Date()
        )
    }

    private var overdue: [NextActionItem] { feed.filter(\.isOverdue) }
    private var upcoming: [NextActionItem] { feed.filter { !$0.isOverdue } }

    var body: some View {
        NavigationStack {
            Group {
                if feed.isEmpty {
                    ContentUnavailableView {
                        Label("All Caught Up", systemImage: "checkmark.circle")
                    } description: {
                        Text("Follow-ups you schedule will show up here.")
                    }
                } else {
                    List {
                        section(title: "Overdue", items: overdue)
                        section(title: "Upcoming", items: upcoming)
                    }
                }
            }
            .navigationTitle("Next Actions")
        }
    }

    @ViewBuilder
    private func section(title: String, items: [NextActionItem]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    NavigationLink {
                        PersonDetailView(person: item.person)
                    } label: {
                        NextActionRow(item: item)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            complete(item.interaction)
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .tint(.green)
                    }
                }
            }
        }
    }

    private func complete(_ interaction: Interaction) {
        let people = PersonRepository(context: modelContext, ownerUserId: session.ownerUserId)
        let interactions = InteractionRepository(
            context: modelContext,
            ownerUserId: session.ownerUserId,
            personRepository: people
        )
        try? interactions.markFollowUpDone(interaction)
        // Completed follow-ups drop out of scheduling.
        Task { await NotificationService().sync(interaction) }
        Task { await syncEngine.sync() }
    }
}

private struct NextActionRow: View {
    let item: NextActionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.person.name).font(.headline)
            HStack(spacing: 4) {
                Image(systemName: item.isOverdue ? "exclamationmark.circle" : "bell")
                Text(dueText)
            }
            .font(.caption)
            .foregroundStyle(item.isOverdue ? .red : .secondary)
        }
    }

    private var dueText: String {
        let dateText = item.followUpDate.formatted(date: .abbreviated, time: .omitted)
        return item.isOverdue ? "Overdue since \(dateText)" : "Due \(dateText)"
    }
}
