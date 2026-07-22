//
//  TagEditor.swift
//  Loop
//
//  Editable tag control: preset chips plus free-form custom tags.
//

import SwiftUI

struct TagEditor: View {
    @Binding var tags: [String]
    @State private var customTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8) {
                ForEach(allChips, id: \.self) { tag in
                    TagChip(
                        title: tag,
                        isSelected: tags.contains(tag),
                        action: { toggle(tag) }
                    )
                }
            }

            HStack {
                TextField("Add a tag", text: $customTag)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addCustomTag)
                Button("Add", action: addCustomTag)
                    .disabled(normalizedCustomTag.isEmpty)
            }
        }
    }

    /// Presets first, followed by any custom tags the person already has.
    private var allChips: [String] {
        let extras = tags.filter { !PersonTag.presets.contains($0) }
        return PersonTag.presets + extras
    }

    private var normalizedCustomTag: String {
        customTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggle(_ tag: String) {
        if let index = tags.firstIndex(of: tag) {
            tags.remove(at: index)
        } else {
            tags.append(tag)
        }
    }

    private func addCustomTag() {
        let tag = normalizedCustomTag
        guard !tag.isEmpty, !tags.contains(tag) else {
            customTag = ""
            return
        }
        tags.append(tag)
        customTag = ""
    }
}

private struct TagChip: View {
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
