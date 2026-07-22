//
//  AIServiceTests.swift
//  LoopTests
//

import Foundation
import Testing
@testable import Loop

/// Captures the text the backend receives and returns a canned response that
/// echoes placeholders, so we can assert redaction-out and rehydration-in.
final class FakeAIBackend: AIBackend {
    var response: String = ""
    private(set) var receivedText: String?
    var shouldThrow = false

    struct BackendError: Error {}

    func invoke(action: String, redactedText: String) async throws -> String {
        receivedText = redactedText
        if shouldThrow { throw BackendError() }
        return response
    }
}

@MainActor
struct AIServiceTests {

    private func makePerson() throws -> Person {
        let context = try TestSupport.makeContext()
        let (people, _) = TestSupport.makeRepositories(context)
        return try people.create(
            PersonDraft(name: "Ada Lovelace", company: "Analytical Engines", email: "ada@analytical.co")
        )
    }

    @Test func redactsPIIBeforeSendingToBackend() async throws {
        let person = try makePerson()
        let fake = FakeAIBackend()
        fake.response = "ok"
        let service = AIService(backend: fake)

        _ = try await service.summarize(
            notes: "Talked with Ada Lovelace from Analytical Engines about roles.",
            person: person
        )

        let sent = try #require(fake.receivedText)
        #expect(!sent.contains("Ada Lovelace"))
        #expect(!sent.contains("Analytical Engines"))
        #expect(sent.contains("[[PERSON_1]]"))
        #expect(sent.contains("[[ORG_1]]"))
    }

    @Test func rehydratesPlaceholdersInResponse() async throws {
        let person = try makePerson()
        let fake = FakeAIBackend()
        // Backend echoes a placeholder as an LLM would when told to preserve them.
        fake.response = "Follow up with [[PERSON_1]] about the role."
        let service = AIService(backend: fake)

        let summary = try await service.summarize(
            notes: "Met Ada Lovelace today.",
            person: person
        )

        #expect(summary == "Follow up with Ada Lovelace about the role.")
    }

    @Test func extractActionItemsSplitsLines() async throws {
        let fake = FakeAIBackend()
        fake.response = "Send thank-you note\nSchedule coffee\n"
        let service = AIService(backend: fake)

        let items = try await service.extractActionItems(notes: "notes", person: nil)

        #expect(items == ["Send thank-you note", "Schedule coffee"])
    }

    @Test func throwsUnavailableWhenBackendFails() async throws {
        let fake = FakeAIBackend()
        fake.shouldThrow = true
        let service = AIService(backend: fake)

        await #expect(throws: AIError.self) {
            _ = try await service.summarize(notes: "notes", person: nil)
        }
    }

    @Test func throwsUnavailableWhenNoBackend() async throws {
        let service = AIService(backend: nil)
        await #expect(throws: AIError.self) {
            _ = try await service.draftFollowUp(notes: "notes", person: nil)
        }
    }
}
