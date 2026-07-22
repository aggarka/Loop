//
//  ContactsImportView.swift
//  Loop
//
//  Presents the system contact picker and creates a person from the selected
//  contact (source = contactsImport). The picker runs out-of-process, so no
//  contacts permission prompt is needed for import.
//

import SwiftUI
import ContactsUI

struct ContactsImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ContactPicker(
            onSelect: { contact in
                let repository = PersonRepository(
                    context: modelContext,
                    ownerUserId: session.ownerUserId
                )
                _ = try? repository.create(ContactMapper.draft(from: contact))
                Task { await syncEngine.sync() }
                dismiss()
            },
            onCancel: { dismiss() }
        )
        .ignoresSafeArea()
    }
}

/// Wraps `CNContactPickerViewController`.
private struct ContactPicker: UIViewControllerRepresentable {
    var onSelect: (CNContact) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onCancel: onCancel)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (CNContact) -> Void
        let onCancel: () -> Void

        init(onSelect: @escaping (CNContact) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect(contact)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}
