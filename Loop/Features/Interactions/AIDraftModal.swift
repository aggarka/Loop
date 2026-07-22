//
//  AIDraftModal.swift
//  Loop
//
//  Presents an AI-generated follow-up draft for review. The draft is transient —
//  it is never persisted (Requirement 9.3, 14.5) — and can be copied or dismissed.
//

import SwiftUI

struct AIDraftModal: View {
    let draft: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(draft)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Follow-up Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = draft
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}
