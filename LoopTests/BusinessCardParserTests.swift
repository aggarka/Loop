//
//  BusinessCardParserTests.swift
//  LoopTests
//

import Foundation
import Testing
@testable import Loop

struct BusinessCardParserTests {

    @Test func parsesTypicalCard() {
        let lines = [
            "Ada Lovelace",
            "Senior Engineer",
            "Analytical Engines Inc",
            "ada@analytical.co",
            "+1 (415) 555-0100",
            "www.analytical.co",
        ]

        let draft = BusinessCardParser.parse(lines: lines)

        #expect(draft.name == "Ada Lovelace")
        #expect(draft.title == "Senior Engineer")
        #expect(draft.company == "Analytical Engines Inc")
        #expect(draft.email == "ada@analytical.co")
        #expect(draft.phone != nil)
        #expect(draft.source == .businessCard)
    }

    @Test func ignoresBlankLinesAndURLs() {
        let lines = ["", "  ", "Grace Hopper", "https://example.com", "grace@example.com"]

        let draft = BusinessCardParser.parse(lines: lines)

        #expect(draft.name == "Grace Hopper")
        #expect(draft.email == "grace@example.com")
    }

    @Test func handlesMinimalCardWithNameOnly() {
        let draft = BusinessCardParser.parse(lines: ["Katherine Johnson"])

        #expect(draft.name == "Katherine Johnson")
        #expect(draft.email == nil)
        #expect(draft.company == nil)
        #expect(draft.source == .businessCard)
    }
}
