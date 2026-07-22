//
//  PIIRedactorTests.swift
//  LoopTests
//

import Foundation
import Testing
@testable import Loop

struct PIIRedactorTests {

    @Test func redactsKnownNameCompanyEmailAndPhone() {
        let context = RedactionContext(
            names: ["Ada Lovelace"],
            organizations: ["Analytical Engines"],
            emails: ["ada@analytical.co"],
            phones: ["+1 (415) 555-0100"]
        )
        let text = "Met Ada Lovelace from Analytical Engines. Email ada@analytical.co or call +1 (415) 555-0100."

        let result = PIIRedactor.redact(text, context: context)

        #expect(!result.text.contains("Ada Lovelace"))
        #expect(!result.text.contains("Analytical Engines"))
        #expect(!result.text.contains("ada@analytical.co"))
        #expect(!result.text.contains("555-0100"))
        #expect(result.text.contains("[[PERSON_1]]"))
        #expect(result.text.contains("[[ORG_1]]"))
        #expect(result.text.contains("[[EMAIL_1]]"))
        #expect(result.text.contains("[[PHONE_1]]"))
    }

    @Test func roundTripRestoresOriginalText() {
        let context = RedactionContext(names: ["Grace Hopper"], organizations: ["Navy"])
        let text = "Grace Hopper at Navy shared advice."

        let result = PIIRedactor.redact(text, context: context)
        let restored = PIIRedactor.rehydrate(result.text, tokenMap: result.tokenMap)

        #expect(restored == text)
    }

    @Test func identicalValueReusesSamePlaceholder() {
        let context = RedactionContext(names: ["Ada"])
        let text = "Ada said hi. Later, Ada followed up."

        let result = PIIRedactor.redact(text, context: context)

        // Only one token minted for the repeated name.
        #expect(result.tokenMap.values.filter { $0 == "Ada" }.count == 1)
        // And it appears twice in the redacted text.
        let occurrences = result.text.components(separatedBy: "[[PERSON_1]]").count - 1
        #expect(occurrences == 2)
    }

    @Test func rehydrateDoesNotConfuseSimilarPlaceholders() {
        // Simulate a token map where one placeholder is a prefix of another.
        var tokenMap: [String: String] = [:]
        for i in 1...12 { tokenMap["[[PERSON_\(i)]]"] = "Name\(i)" }
        let text = "[[PERSON_1]] and [[PERSON_12]] talked."

        let restored = PIIRedactor.rehydrate(text, tokenMap: tokenMap)

        #expect(restored == "Name1 and Name12 talked.")
    }

    @Test func emailDetectedWithoutContext() {
        let result = PIIRedactor.redact("Reach me at test.user@example.com please")
        #expect(result.text.contains("[[EMAIL_1]]"))
        #expect(!result.text.contains("test.user@example.com"))
    }
}
