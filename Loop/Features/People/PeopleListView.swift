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
    @State private var path: [Person] = []

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
        NavigationStack(path: $path) {
            Group {
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
                    peopleList
                }
            }
            .navigationTitle("People")
            .navigationDestination(for: Person.self) { person in
                PersonDetailView(person: person)
            }
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
        }
        .onChange(of: router.pendingPersonID) { _, newValue in
            navigateToPendingPerson(newValue)
        }
        .onAppear { navigateToPendingPerson(router.pendingPersonID) }
    }

    /// Pushes the person referenced by a tapped notification, then clears the
    /// router so it isn't re-consumed.
    private func navigateToPendingPerson(_ personID: String?) {
        guard let personID,
              let person = ownedPeople.first(where: { $0.id.uuidString == personID })
        else { return }
        path = [person]
        router.pendingPersonID = nil
    }

    private var peopleList: some View {
        List {
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
                    NavigationLink(value: person) {
                        PersonRow(person: person)
                    }
                }
            }
        }
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
