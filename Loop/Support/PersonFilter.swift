//
//  PersonFilter.swift
//  Loop
//
//  Shared matching logic for people search + tag filtering, used by both
//  `PersonRepository.search` and the People List view so the two never diverge.
//

import Foundation

enum PersonFilter {
    /// Matches `query` against name, company, and title (case-insensitive) and
    /// requires the person to carry all of the selected `tags`. An empty query
    /// matches everything; an empty tag set imposes no tag constraint.
    static func matches(_ person: Person, query: String, tags: [String]) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let matchesQuery: Bool
        if needle.isEmpty {
            matchesQuery = true
        } else {
            matchesQuery =
                person.name.lowercased().contains(needle)
                || (person.company?.lowercased().contains(needle) ?? false)
                || (person.title?.lowercased().contains(needle) ?? false)
        }

        let matchesTags = tags.allSatisfy { person.tags.contains($0) }
        return matchesQuery && matchesTags
    }
}

/// Preset relationship tags offered in the tagging UI. Users may also add
/// custom tags.
enum PersonTag {
    static let presets = ["VC", "recruiter", "alum", "friend-of-friend"]
}
