//
//  TestSupport.swift
//  LoopTests
//
//  Shared helpers for building an in-memory SwiftData stack in tests.
//

import Foundation
import SwiftData
@testable import Loop

enum TestSupport {
    static let ownerId = "test-user"

    /// Builds an isolated in-memory model context. The container is retained by
    /// the returned context for the lifetime of the test.
    @MainActor
    static func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Person.self, Interaction.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @MainActor
    static func makeRepositories(
        _ context: ModelContext
    ) -> (people: PersonRepository, interactions: InteractionRepository) {
        let people = PersonRepository(context: context, ownerUserId: ownerId)
        let interactions = InteractionRepository(
            context: context,
            ownerUserId: ownerId,
            personRepository: people
        )
        return (people, interactions)
    }
}
