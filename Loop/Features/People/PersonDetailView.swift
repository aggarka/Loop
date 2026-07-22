//
//  PersonDetailView.swift
//  Loop
//
//  Shows a person's details, tags, last-contacted date, and interaction
//  timeline. Supports editing and deleting.
//

import SwiftUI
import SwiftData

struct PersonDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.dismiss) private var dismiss

    @Bindable var person: Person

    @State private var isEditing = false
    @State private var showDeleteConfirmation = false
    @State private var isLoggingInteraction = false
    @State private var editingInteraction: Interaction?
    @State private var exportMessage: String?
    @State private var showExportResult = false

    private var timeline: [Interaction] {
        person.interactions
            .filter { !$0.isTombstoned }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name).font(.title2).bold()
                    if let subtitle = person.subtitle {
                        Text(subtitle).foregroundStyle(.secondary)
                    }
                }
                if let email = person.email { LabeledContent("Email", value: email) }
                if let phone = person.phone { LabeledContent("Phone", value: phone) }
                LabeledContent("Last contacted") {
                    Text(lastContactedText)
                }
            }

            if !person.tags.isEmpty {
                Section("Tags") {
                    FlowLayout(spacing: 8) {
                        ForEach(person.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color(.secondarySystemBackground)))
                        }
                    }
                }
            }

            Section {
                Button {
                    isLoggingInteraction = true
                } label: {
                    Label("Log Interaction", systemImage: "square.and.pencil")
                }
            }

            Section("Timeline") {
                if timeline.isEmpty {
                    Text("No interactions logged yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(timeline) { interaction in
                        Button {
                            editingInteraction = interaction
                        } label: {
                            InteractionRow(interaction: interaction)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit") { isEditing = true }
                    Button {
                        Task { await exportToContacts() }
                    } label: {
                        Label("Export to Contacts", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Delete Person", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            PersonEditView(person: person)
        }
        .sheet(isPresented: $isLoggingInteraction) {
            LogInteractionView(person: person)
        }
        .sheet(item: $editingInteraction) { interaction in
            LogInteractionView(person: person, interaction: interaction)
        }
        .confirmationDialog(
            "Delete \(person.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deletePerson)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also removes all logged interactions for this person.")
        }
        .alert("Export to Contacts", isPresented: $showExportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportMessage ?? "")
        }
    }

    private func exportToContacts() async {
        do {
            try await ContactsService().export(person)
            exportMessage = "\(person.name) was added to your contacts."
        } catch {
            exportMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not export this person."
        }
        showExportResult = true
    }

    private var lastContactedText: String {
        guard let date = person.lastContactedDate else { return "Never" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func deletePerson() {
        let repository = PersonRepository(
            context: modelContext,
            ownerUserId: session.ownerUserId
        )
        // Cancel any pending follow-up reminders for this person's interactions.
        let notifications = NotificationService()
        for interaction in person.interactions {
            notifications.cancel(interactionID: interaction.id)
        }
        try? repository.delete(person)
        Task { await syncEngine.sync() }
        dismiss()
    }
}

struct InteractionRow: View {
    let interaction: Interaction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(interaction.type.displayName).font(.headline)
                Spacer()
                Text(interaction.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !interaction.notes.isEmpty {
                Text(interaction.notes)
                    .font(.subheadline)
                    .lineLimit(3)
            }
            if let followUpDate = interaction.followUpDate,
               interaction.followUpStatus != .none {
                Label(
                    followUpText(followUpDate),
                    systemImage: interaction.followUpStatus == .done ? "checkmark.circle" : "bell"
                )
                .font(.caption)
                .foregroundStyle(interaction.followUpStatus == .done ? .green : .orange)
            }
        }
        .padding(.vertical, 2)
    }

    private func followUpText(_ date: Date) -> String {
        let dateText = date.formatted(date: .abbreviated, time: .omitted)
        switch interaction.followUpStatus {
        case .done: return "Followed up"
        case .pending: return "Follow up \(dateText)"
        case .none: return dateText
        }
    }
}
