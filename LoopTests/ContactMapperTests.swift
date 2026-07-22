//
//  ContactMapperTests.swift
//  LoopTests
//

import Foundation
import Testing
import Contacts
@testable import Loop

@MainActor
struct ContactMapperTests {

    @Test func mapsContactToDraft() {
        let contact = CNMutableContact()
        contact.givenName = "Ada"
        contact.familyName = "Lovelace"
        contact.organizationName = "Analytical Engines"
        contact.jobTitle = "Engineer"
        contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "ada@analytical.co")]
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: "+14155550100"))]

        let draft = ContactMapper.draft(from: contact)

        #expect(draft.name == "Ada Lovelace")
        #expect(draft.company == "Analytical Engines")
        #expect(draft.title == "Engineer")
        #expect(draft.email == "ada@analytical.co")
        #expect(draft.phone == "+14155550100")
        #expect(draft.source == .contactsImport)
    }

    @Test func mapsPersonToContactSplittingName() throws {
        let context = try TestSupport.makeContext()
        let (people, _) = TestSupport.makeRepositories(context)
        let person = try people.create(
            PersonDraft(name: "Grace Hopper", company: "Navy", title: "Rear Admiral", email: "grace@navy.mil")
        )

        let contact = ContactMapper.mutableContact(from: person)

        #expect(contact.givenName == "Grace")
        #expect(contact.familyName == "Hopper")
        #expect(contact.organizationName == "Navy")
        #expect(contact.jobTitle == "Rear Admiral")
        #expect(contact.emailAddresses.first.map { String($0.value) } == "grace@navy.mil")
    }

    @Test func mapsSingleWordNameToGivenName() throws {
        let context = try TestSupport.makeContext()
        let (people, _) = TestSupport.makeRepositories(context)
        let person = try people.create(PersonDraft(name: "Prince"))

        let contact = ContactMapper.mutableContact(from: person)

        #expect(contact.givenName == "Prince")
        #expect(contact.familyName == "")
    }
}
