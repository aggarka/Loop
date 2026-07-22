//
//  LogInteractionView.swift
//  Loop
//
//  Form for logging a new interaction with a person (or editing an existing
//  one): date, type, notes, outcomes, and an optional follow-up date.
//

import SwiftUI
import SwiftData

struct LogInteractionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(AIService.self) private var aiService
    @Environment(\.dismiss) private var dismiss

    private let person: Person
    private let existing: Interaction?

    @State private var date: Date
    @State private var type: InteractionType
    @State private var notes: String
    @State private var outcomes: String
    @State private var hasFollowUp: Bool
    @State private var followUpDate: Date

    // AI state
    @State private var aiSummary: String?
    @State private var actionItems: [String] = []
    @State private var draftText: String?
    @State private var isRunningAI = false
    @State private var aiError: String?

    init(person: Person, interaction: Interaction? = nil) {
        self.person = person
        self.existing = interaction
        _date = State(initialValue: interaction?.date ?? Date())
        _type = State(initialValue: interaction?.type ?? .coffeeChat)
        _notes = State(initialValue: interaction?.notes ?? "")
        _outcomes = State(initialValue: interaction?.outcomes ?? "")
        _hasFollowUp = State(initialValue: interaction?.followUpDate != nil)
        _followUpDate = State(
            initialValue: interaction?.followUpDate
                ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())
                ?? Date()
        )
        _aiSummary = State(initialValue: interaction?.aiSummary)
    }

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Type", selection: $type) {
                        ForEach(InteractionType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                Section("Outcomes / Commitments") {
                    TextField("What did you commit to?", text: $outcomes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Follow-up") {
                    Toggle("Set a follow-up", isOn: $hasFollowUp.animation())
                    if hasFollowUp {
                        DatePicker(
                            "Follow-up date",
                            selection: $followUpDate,
                            displayedComponents: .date
                        )
                    }
                }

                aiSection
            }
            .navigationTitle(isEditing ? "Edit Interaction" : "Log Interaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .sheet(item: Binding(
                get: { draftText.map { DraftBox(text: $0) } },
                set: { draftText = $0?.text }
            )) { box in
                AIDraftModal(draft: box.text)
            }
        }
    }

    // MARK: AI section

    @ViewBuilder
    private var aiSection: some View {
        Section("AI Assistance") {
            if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Add some notes to use AI.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await summarize() }
                } label: {
                    Label("Summarize Notes", systemImage: "text.append")
                }
                Button {
                    Task { await extractActions() }
                } label: {
                    Label("Extract Action Items", systemImage: "checklist")
                }
                Button {
                    Task { await draftFollowUp() }
                } label: {
                    Label("Draft Follow-up", systemImage: "envelope")
                }
            }

            if isRunningAI {
                HStack { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }
            }
            if let aiSummary {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary").font(.caption).foregroundStyle(.secondary)
                    Text(aiSummary).font(.subheadline)
                }
            }
            if !actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Action Items").font(.caption).foregroundStyle(.secondary)
                    ForEach(actionItems, id: \.self) { item in
                        Label(item, systemImage: "circle").font(.subheadline)
                    }
                    Button("Add to Outcomes") {
                        let joined = actionItems.map { "• \($0)" }.joined(separator: "\n")
                        outcomes = outcomes.isEmpty ? joined : outcomes + "\n" + joined
                    }
                    .font(.footnote)
                }
            }
            if let aiError {
                Text(aiError).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func summarize() async {
        await runAI { aiSummary = try await aiService.summarize(notes: notes, person: person) }
    }

    private func extractActions() async {
        await runAI { actionItems = try await aiService.extractActionItems(notes: notes, person: person) }
    }

    private func draftFollowUp() async {
        await runAI { draftText = try await aiService.draftFollowUp(notes: notes, person: person) }
    }

    private func runAI(_ operation: () async throws -> Void) async {
        aiError = nil
        isRunningAI = true
        defer { isRunningAI = false }
        do {
            try await operation()
        } catch {
            aiError = (error as? LocalizedError)?.errorDescription ?? "AI request failed."
        }
    }

    private func save() {
        let people = PersonRepository(context: modelContext, ownerUserId: session.ownerUserId)
        let interactions = InteractionRepository(
            context: modelContext,
            ownerUserId: session.ownerUserId,
            personRepository: people
        )

        let draft = InteractionDraft(
            date: date,
            type: type,
            notes: notes,
            outcomes: outcomes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : outcomes,
            followUpDate: hasFollowUp ? followUpDate : nil
        )

        do {
            let saved: Interaction
            if let existing {
                try interactions.update(existing, with: draft)
                saved = existing
            } else {
                saved = try interactions.create(draft, for: person)
            }
            // Persist an AI summary if one was generated.
            if let aiSummary, saved.aiSummary != aiSummary {
                saved.aiSummary = aiSummary
                saved.updatedAt = Date()
                saved.dirty = true
                try? modelContext.save()
            }
            // Schedule / update / cancel the follow-up reminder to match state.
            Task { await NotificationService().sync(saved) }
            Task { await syncEngine.sync() }
            dismiss()
        } catch {
            // Creation/update only throws on persistence errors; nothing the user
            // can act on here, so dismiss and let the sync layer retry.
            dismiss()
        }
    }
}

/// Wraps the transient draft string so it can drive `.sheet(item:)`.
private struct DraftBox: Identifiable {
    let text: String
    var id: String { text }
}
