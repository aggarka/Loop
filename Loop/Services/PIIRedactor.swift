//
//  PIIRedactor.swift
//  Loop
//
//  On-device tokenization of personally identifiable information before any text
//  is sent to the AI backend, and rehydration of the model's response. This is
//  what keeps identifiable data away from the third-party LLM vendor
//  (Requirement 9.4, 9.5). Detection combines known values from the related
//  person with `NaturalLanguage` name/org recognition and `NSDataDetector` /
//  regex for emails and phone numbers. Best-effort by design; documented as such.
//

import Foundation
import NaturalLanguage

/// Known identifiers for a piece of text, seeded from the related person so that
/// detection is reliable even when NER misses free-text mentions.
struct RedactionContext {
    var names: [String]
    var organizations: [String]
    var emails: [String]
    var phones: [String]

    init(names: [String] = [], organizations: [String] = [], emails: [String] = [], phones: [String] = []) {
        self.names = names
        self.organizations = organizations
        self.emails = emails
        self.phones = phones
    }

    init(person: Person) {
        self.init(
            names: [person.name],
            organizations: [person.company].compactMap { $0 },
            emails: [person.email].compactMap { $0 },
            phones: [person.phone].compactMap { $0 }
        )
    }
}

struct RedactionResult: Equatable {
    /// Text with PII replaced by placeholders.
    let text: String
    /// Placeholder -> original value, kept on-device for rehydration.
    let tokenMap: [String: String]
}

enum PIIRedactor {
    private enum Category: String {
        case email = "EMAIL"
        case phone = "PHONE"
        case org = "ORG"
        case person = "PERSON"
    }

    /// Replaces detected PII with stable placeholders (e.g. `[[PERSON_1]]`).
    /// Identical values map to the same placeholder within a single call.
    static func redact(_ text: String, context: RedactionContext = RedactionContext()) -> RedactionResult {
        // Gather (value, category) candidates from the context and detectors.
        var candidates: [(value: String, category: Category)] = []

        func add(_ values: [String], _ category: Category) {
            for value in values {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                candidates.append((trimmed, category))
            }
        }

        add(context.emails, .email)
        add(detectEmails(in: text), .email)
        add(context.phones, .phone)
        add(detectPhones(in: text), .phone)

        let (detectedNames, detectedOrgs) = detectNamesAndOrgs(in: text)
        add(context.organizations, .org)
        add(detectedOrgs, .org)
        add(context.names, .person)
        add(detectedNames, .person)

        // De-duplicate values, keeping the first category seen, and replace the
        // longest values first so full names are handled before first names.
        var seen = Set<String>()
        let unique = candidates
            .filter { seen.insert($0.value.lowercased()).inserted }
            .sorted { $0.value.count > $1.value.count }

        var result = text
        var tokenMap: [String: String] = [:]
        var counters: [Category: Int] = [:]
        // Reverse lookup so the same value reuses its placeholder.
        var valueToToken: [String: String] = [:]

        for candidate in unique {
            guard result.localizedCaseInsensitiveContains(candidate.value) else { continue }

            let token: String
            if let existing = valueToToken[candidate.value.lowercased()] {
                token = existing
            } else {
                let next = (counters[candidate.category] ?? 0) + 1
                counters[candidate.category] = next
                token = "[[\(candidate.category.rawValue)_\(next)]]"
                valueToToken[candidate.value.lowercased()] = token
                tokenMap[token] = candidate.value
            }

            result = result.replacingOccurrences(
                of: candidate.value,
                with: token,
                options: [.caseInsensitive]
            )
        }

        return RedactionResult(text: result, tokenMap: tokenMap)
    }

    /// Restores original values by swapping placeholders back. Longer
    /// placeholders are replaced first so `[[PERSON_1]]` doesn't clobber
    /// `[[PERSON_10]]`.
    static func rehydrate(_ text: String, tokenMap: [String: String]) -> String {
        var result = text
        for token in tokenMap.keys.sorted(by: { $0.count > $1.count }) {
            guard let original = tokenMap[token] else { continue }
            result = result.replacingOccurrences(of: token, with: original)
        }
        return result
    }

    // MARK: Detection

    private static func detectEmails(in text: String) -> [String] {
        let pattern = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func detectPhones(in text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func detectNamesAndOrgs(in text: String) -> (names: [String], orgs: [String]) {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names: [String] = []
        var orgs: [String] = []

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            guard let tag else { return true }
            let value = String(text[range])
            switch tag {
            case .personalName: names.append(value)
            case .organizationName: orgs.append(value)
            default: break
            }
            return true
        }
        return (names, orgs)
    }
}
