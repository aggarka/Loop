//
//  BusinessCardParser.swift
//  Loop
//
//  Heuristically maps lines of text recognized from a business card into a
//  `PersonDraft`. Pure and testable; the on-device OCR that produces the lines
//  lives in `CardScannerView`.
//

import Foundation

enum BusinessCardParser {
    private static let titleKeywords = [
        "engineer", "developer", "manager", "director", "president", "ceo", "cto",
        "cfo", "coo", "founder", "partner", "lead", "head", "officer", "analyst",
        "designer", "consultant", "vp", "vice president", "recruiter", "associate",
    ]

    private static let companySuffixes = [
        "inc", "inc.", "llc", "ltd", "ltd.", "co", "co.", "corp", "corp.",
        "gmbh", "company", "labs", "ventures", "capital", "partners", "group",
    ]

    /// Parses recognized lines into a draft. Emails and phones are matched by
    /// pattern; the first remaining line is treated as the name, a line matching
    /// a role keyword as the title, and a company-suffix line as the company.
    static func parse(lines rawLines: [String]) -> PersonDraft {
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var email: String?
        var phone: String?
        var title: String?
        var company: String?
        var remaining: [String] = []

        for line in lines {
            if email == nil, let found = firstEmail(in: line) {
                email = found
                continue
            }
            if phone == nil, let found = firstPhone(in: line) {
                phone = found
                continue
            }
            if isURL(line) {
                continue
            }
            if title == nil, matchesTitle(line) {
                title = line
                continue
            }
            if company == nil, matchesCompany(line) {
                company = line
                continue
            }
            remaining.append(line)
        }

        // The first leftover line is the most likely name; any others fall back
        // to company if we didn't find one.
        let name = remaining.first ?? ""
        if company == nil, remaining.count > 1 {
            company = remaining[1]
        }

        return PersonDraft(
            name: name,
            company: company,
            title: title,
            email: email,
            phone: phone,
            source: .businessCard
        )
    }

    // MARK: Matching helpers

    private static func firstEmail(in text: String) -> String? {
        let pattern = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r = Range(match.range, in: text) else { return nil }
        return String(text[r])
    }

    private static func firstPhone(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = detector.firstMatch(in: text, range: range) else { return nil }
        return match.phoneNumber
    }

    private static func isURL(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
            || lower.hasPrefix("www.") || lower.contains(".com/")
    }

    private static func matchesTitle(_ line: String) -> Bool {
        let lower = line.lowercased()
        return titleKeywords.contains { lower.contains($0) }
    }

    private static func matchesCompany(_ line: String) -> Bool {
        let tokens = line.lowercased().split(whereSeparator: { $0 == " " }).map(String.init)
        return tokens.contains { companySuffixes.contains($0) }
    }
}
