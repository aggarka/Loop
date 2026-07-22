//
//  SettingsView.swift
//  Loop
//
//  Account actions (sign out, delete account) and privacy explanations of how
//  data is stored and how AI handles PII (Requirements 2, 13).
//

import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var authService

    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy") {
                    privacyRow(
                        icon: "iphone",
                        title: "Local-first",
                        detail: "Your people and interactions are stored on your device and work fully offline."
                    )
                    privacyRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Synced to your account",
                        detail: "Your data syncs privately across your devices and is only ever visible to you."
                    )
                    privacyRow(
                        icon: "lock.shield",
                        title: "AI keeps names private",
                        detail: "Before notes are summarized, names, companies, emails, and phone numbers are removed on your device — the AI service never sees who your contacts are."
                    )
                }

                Section("Account") {
                    Button("Sign Out") {
                        Task { await authService.signOut() }
                    }
                    Button("Delete Account", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }

                if let errorMessage = authService.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task { await authService.deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and all of your people and interactions. This cannot be undone.")
            }
        }
    }

    private func privacyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
