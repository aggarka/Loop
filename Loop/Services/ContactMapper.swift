//
//  ContactMapper.swift
//  Loop
//
//  Pure mapping between the Contacts framework's `CNContact` and Loop's domain
//  types. Kept separate from I/O so it can be unit-tested.
//

import Foundation
import Contacts

enum ContactMapper {
    /// Maps a device contact to a `PersonDraft` for import.
    static func draft(from contact: CNContact) -> PersonDraft {
        let fullName = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let organization = contact.organizationName.isEmpty ? nil : contact.organizationName
        let email = contact.emailAddresses.first.map { String($0.value) }
        let phone = contact.phoneNumbers.first?.value.stringValue

        return PersonDraft(
            name: fullName.isEmpty ? (organization ?? "") : fullName,
            company: fullName.isEmpty ? nil : organization,
            title: contact.jobTitle.isEmpty ? nil : contact.jobTitle,
            email: email,
            phone: phone,
            source: .contactsImport
        )
    }

    /// Builds a mutable contact from a person for export. Splits the name into
    /// given/family on the first space.
    static func mutableContact(from person: Person) -> CNMutableContact {
        let contact = CNMutableContact()

        let parts = person.name.split(separator: " ", maxSplits: 1).map(String.init)
        contact.givenName = parts.first ?? person.name
        contact.familyName = parts.count > 1 ? parts[1] : ""

        if let company = person.company { contact.organizationName = company }
        if let title = person.title { contact.jobTitle = title }
        if let email = person.email {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
        }
        if let phone = person.phone {
            contact.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))
            ]
        }
        return contact
    }
}
