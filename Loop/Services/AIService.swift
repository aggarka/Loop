//
//  AIService.swift
//  Loop
//
//  Summarizes notes, extracts action items, and drafts follow-ups. PII is
//  tokenized on-device before anything leaves the device and rehydrated locally
//  in the response, so the AI vendor never receives identifiable data
//  (Requirement 9). The network call is abstracted behind `AIBackend` for
//  testability; the redaction/rehydration boundary is enforced here, not by
//  callers.
//

import Foundation
import Observation
import Supabase

enum AIError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "AI features are unavailable right now. Please check your connection and try again."
        }
    }
}

/// Sends already-redacted text to the AI backend and returns its raw (still
/// redacted) result.
protocol AIBackend {
    func invoke(action: String, redactedText: String) async throws -> String
}

@MainActor
@Observable
final class AIService {
    @ObservationIgnored private let backend: AIBackend?

    init(backend: AIBackend?) {
        self.backend = backend
    }

    func summarize(notes: String, person: Person?) async throws -> String {
        try await run(action: "summarize", text: notes, person: person)
    }

    func extractActionItems(notes: String, person: Person?) async throws -> [String] {
        let result = try await run(action: "extract", text: notes, person: person)
        return result
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func draftFollowUp(notes: String, person: Person?) async throws -> String {
        try await run(action: "draft", text: notes, person: person)
    }

    /// Redact -> send -> rehydrate. The backend only ever sees tokenized text.
    private func run(action: String, text: String, person: Person?) async throws -> String {
        guard let backend else { throw AIError.unavailable }
        let context = person.map(RedactionContext.init) ?? RedactionContext()
        let redacted = PIIRedactor.redact(text, context: context)
        do {
            let raw = try await backend.invoke(action: action, redactedText: redacted.text)
            return PIIRedactor.rehydrate(raw, tokenMap: redacted.tokenMap)
        } catch {
            throw AIError.unavailable
        }
    }
}

/// Supabase Edge Function implementation of `AIBackend`.
struct SupabaseAIBackend: AIBackend {
    let client: SupabaseClient

    private struct RequestBody: Encodable {
        let action: String
        let text: String
    }

    private struct ResponseBody: Decodable {
        let result: String
    }

    func invoke(action: String, redactedText: String) async throws -> String {
        let response: ResponseBody = try await client.functions.invoke(
            "ai-proxy",
            options: FunctionInvokeOptions(body: RequestBody(action: action, text: redactedText))
        )
        return response.result
    }
}
