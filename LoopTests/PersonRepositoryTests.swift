//
//  PersonRepositoryTests.swift
//  LoopTests
//

import Foundation
import Testing
import SwiftData
@testable import Loop

@MainActor
struct PersonRepositoryTests {

    @Test func createPersistsPersonWithSource() throws {
        let context = try TestSupport.makeContext()
        let (people, _) = TestSupport.makeRepositories(context)

        let person = try people.create(
            PersonDraft(name: "Ada Lovelace", company: "Analytical", source: .manual)
        )

        #expect(person.name == "Ada Lovelace")
        #expect(person.source == .manual)
        #expect(people.all().count == 1)
    }

    @Test func createTrimsAndRejectsBlankName() throws {
        let context = try TestSupport.makeContext()
        let (people, _) = TestSupport.makeRepositories(context)

        #expect(throws: DomainError.nameRequired) {
            _ = try people.create(PersonDraft(name: "   "))
        }
        #expect(people.all().isEmpty)
    }

    @Test func softDeleteHidesPersonAndTombstonesInteractions() throws {
        let context = try TestSupport.makeContext()
        let (people, interactions) = TestSupport.makeRepositories(context)

        let person = try people.create(PersonDraft(name: "Grace Hopper"))
        _ = try interactions.create(InteractionDraft(type: .coffeeChat), for: person)

        try people.delete(person)

        #expect(people.all().isEmpty)
        #expect(person.isTombstoned)
        #expect(person.interactions.allSatisfy { $0.isTombstoned })
    }

    @Test func lastContactedReflectsNewestInteraction() throws {
        let context = try TestSupport.makeContext()
        let (people, interactions) = TestSupport.makeRepositories(context)

        let person = try people.create(PersonDraft(name: "Alan Turing"))
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        _ = try interactions.create(InteractionDraft(date: older, type: .email), for: person)
        _ = try interactions.create(InteractionDraft(date: newer, type: .phoneCall), for: person)

        #expect(person.lastContactedDate == newer)
    }

    @Test func searchMatchesNameCompanyAndTitle() throws {
        let context = try TestSupport.makeContext()
        let (people, _) = TestSupport.makeRepositories(context)

        _ = try people.create(PersonDraft(name: "Ada Lovelace", company: "Analytical Engines"))
        _ = try people.create(PersonDraft(name: "Bob Stone", title: "Analytical Lead"))
        _ = try people.create(PersonDraft(name: "Carol King", company: "Music Co"))

        #expect(people.search(query: "analytical", tags: []).count == 2)
        #expect(people.search(query: "carol", tags: []).count == 1)
        #expect(people.search(query: "", tags: []).count == 3)
    }

    @Test func tagFilterRequiresAllSelectedTags() throws {
        let context = try TestSupport.makeContext()
        let (people, _) = TestSupport.makeRepositories(context)

        _ = try people.create(PersonDraft(name: "VC Alum", tags: ["VC", "alum"]))
        _ = try people.create(PersonDraft(name: "Just VC", tags: ["VC"]))

        #expect(people.search(query: "", tags: ["VC"]).count == 2)
        #expect(people.search(query: "", tags: ["VC", "alum"]).count == 1)
        #expect(people.search(query: "", tags: ["recruiter"]).isEmpty)
    }
}
