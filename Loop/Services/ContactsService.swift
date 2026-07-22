//
//  ContactsService.swift
//  Loop
//
//  Exports a person to the device's contacts. Import uses the out-of-process
//  `CNContactPickerViewController` (no permission prompt required); export writes
//  to the store and therefore requires contacts access.
//

import Foundation
import Contacts

@MainActor
final class ContactsService {
    enum ContactsError: LocalizedError {
        case accessDenied

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Loop needs access to Contacts to export this person."
            }
        }
    }

    private let store = CNContactStore()

    /// Writes the person to the device contacts, requesting write access first.
    func export(_ person: Person) async throws {
        guard try await requestWriteAccess() else { throw ContactsError.accessDenied }

        let contact = ContactMapper.mutableContact(from: person)
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)
    }

    private func requestWriteAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
