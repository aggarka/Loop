//
//  PeopleListView.swift
//  Loop
//
//  Lists the user's people with search and tag filtering, and an entry point to
//  add a new person. Uses @Query for live updates and the shared `PersonFilter`
//  for matching so it stays consistent with `PersonRepository.search`.
//

import SwiftUI
import SwiftData

struct PeopleListView: View {
    @Environment(AppSession.self) private var session
    @Environment(NotificationRouter.self) private var router
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var searchText = ""
    @State private var selectedTags: Set<String> = []
    @State private var isAdding = false
    @State private var isScanning = false
    @State private var isImporting = false
    /// Selected person drives the detail column on iPad and push navigation on
    /// iPhone (NavigationSplitView collapses to a stack on compact width).
    @State private var selectedPerson: Person?

    /// People owned by the current user that are not tombstoned.
    private var ownedPeople: [Person] {
        allPeople.filter { !$0.isTombstoned && $0.ownerUserId == session.ownerUserId }
    }

    private var filteredPeople: [Person] {
        ownedPeople.filter {
            PersonFilter.matches($0, query: searchText, tags: Array(selectedTags))
        }
    }

    /// Preset tags plus any custom tags currently in use, for the filter bar.
    private var availableTags: [String] {
        let used = Set(ownedPeople.flatMap(\.tags))
        let extras = used.subtracting(PersonTag.presets).sorted()
        return PersonTag.presets + extras
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("People")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                isAdding = true
                            } label: {
                                Label("Add Manually", systemImage: "square.and.pencil")
                            }
                            Button {
                                isScanning = true
                            } label: {
                                Label("Scan Business Card", systemImage: "camera")
                            }
                            Button {
                                isImporting = true
                            } label: {
                                Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
                            }
                        } label: {
                            Label("Add Person", systemImage: "plus")
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search name, company, title")
                .sheet(isPresented: $isAdding) {
                    PersonEditView()
                }
                .sheet(isPresented: $isScanning) {
                    BusinessCardScanView()
                }
                .sheet(isPresented: $isImporting) {
                    ContactsImportView()
                }
        } detail: {
            if let person = selectedPerson, !person.isTombstoned {
                PersonDetailView(person: person)
            } else {
                ContentUnavailableView {
                    Label("Select a Person", systemImage: "person.crop.circle")
                } description: {
                    Text("Choose someone to see their details and timeline.")
                }
            }
        }
        .onChange(of: router.pendingPersonID) { _, newValue in
            navigateToPendingPerson(newValue)
        }
        .onAppear { navigateToPendingPerson(router.pendingPersonID) }
        // Clear selection once a person is deleted so the detail column resets.
        .onChange(of: selectedPerson?.isTombstoned) { _, tombstoned in
            if tombstoned == true { selectedPerson = nil }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if ownedPeople.isEmpty {
            ContentUnavailableView {
                Label("No People Yet", systemImage: "person.2")
            } description: {
                Text("Add someone from your network to get started.")
            } actions: {
                Button("Add Person") { isAdding = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("addPersonEmptyState")
            }
        } else if filteredPeople.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List(selection: $selectedPerson) {
                if !availableTags.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(availableTags, id: \.self) { tag in
                                    FilterChip(
                                        title: tag,
                                        isSelected: selectedTags.contains(tag)
                                    ) { toggleTag(tag) }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                }

                Section {
                    ForEach(filteredPeople) { person in
                        PersonRow(person: person).tag(person)
                    }
                }
            }
        }
    }

    /// Selects the person referenced by a tapped notification, then clears the
    /// router so it isn't re-consumed.
    private func navigateToPendingPerson(_ personID: String?) {
        guard let personID,
              let person = ownedPeople.first(where: { $0.id.uuidString == personID })
        else { return }
        selectedPerson = person
        router.pendingPersonID = nil
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

private struct PersonRow: View {
    let person: Person

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(person.name).font(.headline)
            if let subtitle = person.subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
