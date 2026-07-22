//
//  PersonEditView.swift
//  Loop
//
//  Form for adding a new person or editing an existing one. Reused by the
//  People List (add) and Person Detail (edit) screens.
//

import SwiftUI
import SwiftData

struct PersonEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.dismiss) private var dismiss

    /// The person being edited, or nil when adding a new one.
    private let existing: Person?
    /// Source applied to a newly created person (e.g. `.businessCard` when
    /// prefilled from a scan).
    private let newSource: PersonSource

    @State private var name: String
    @State private var company: String
    @State private var title: String
    @State private var email: String
    @State private var phone: String
    @State private var tags: [String]
    @State private var errorMessage: String?

    init(person: Person? = nil) {
        self.existing = person
        self.newSource = .manual
        _name = State(initialValue: person?.name ?? "")
        _company = State(initialValue: person?.company ?? "")
        _title = State(initialValue: person?.title ?? "")
        _email = State(initialValue: person?.email ?? "")
        _phone = State(initialValue: person?.phone ?? "")
        _tags = State(initialValue: person?.tags ?? [])
    }

    /// Creates a new person prefilled from a parsed draft (e.g. a scanned card
    /// or an imported contact), preserving the draft's source.
    init(prefill draft: PersonDraft) {
        self.existing = nil
        self.newSource = draft.source
        _name = State(initialValue: draft.name)
        _company = State(initialValue: draft.company ?? "")
        _title = State(initialValue: draft.title ?? "")
        _email = State(initialValue: draft.email ?? "")
        _phone = State(initialValue: draft.phone ?? "")
        _tags = State(initialValue: draft.tags)
    }

    private var isEditing: Bool { existing != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Company", text: $company)
                    TextField("Title", text: $title)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }

                Section("Tags") {
                    TagEditor(tags: $tags)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Person" : "Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let repository = PersonRepository(
            context: modelContext,
            ownerUserId: session.ownerUserId
        )
        let draft = PersonDraft(
            name: name,
            company: company,
            title: title,
            email: email,
            phone: phone,
            tags: tags,
            source: existing?.source ?? newSource
        )

        do {
            if let existing {
                try repository.update(existing, with: draft)
            } else {
                _ = try repository.create(draft)
            }
            Task { await syncEngine.sync() }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not save this person."
        }
    }
}
