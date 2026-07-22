//
//  NotificationServiceTests.swift
//  LoopTests
//

import Foundation
import Testing
import UserNotifications
@testable import Loop

/// Records scheduling calls instead of touching the system notification center.
final class FakeScheduler: NotificationScheduling {
    var status: UNAuthorizationStatus = .authorized
    var requestResult = true
    private(set) var requestCount = 0
    private(set) var scheduledIDs: [String] = []
    private(set) var cancelledIDs: [String] = []

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async -> Bool {
        requestCount += 1
        return requestResult
    }

    func schedule(id: String, title: String, body: String, fireDate: Date, userInfo: [String: String]) async {
        scheduledIDs.append(id)
    }

    func cancel(ids: [String]) {
        cancelledIDs.append(contentsOf: ids)
    }
}

@MainActor
struct NotificationServiceTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func makeInteraction(
        followUpDate: Date?,
        done: Bool = false,
        tombstoned: Bool = false
    ) throws -> Interaction {
        let context = try TestSupport.makeContext()
        let (people, interactions) = TestSupport.makeRepositories(context)
        let person = try people.create(PersonDraft(name: "Test Person"))
        let interaction = try interactions.create(
            InteractionDraft(type: .coffeeChat, followUpDate: followUpDate),
            for: person
        )
        if done { try interactions.markFollowUpDone(interaction) }
        if tombstoned { try interactions.delete(interaction) }
        return interaction
    }

    // MARK: Planner

    @Test func plannerSchedulesFuturePendingFollowUp() throws {
        let interaction = try makeInteraction(followUpDate: now.addingTimeInterval(1_000))
        let plan = FollowUpNotificationPlanner.plan(for: interaction, asOf: now)
        if case .schedule(let id, _, _, _) = plan {
            #expect(id == interaction.id.uuidString)
        } else {
            Issue.record("Expected .schedule, got \(plan)")
        }
    }

    @Test func plannerCancelsOverduePendingFollowUp() throws {
        let interaction = try makeInteraction(followUpDate: now.addingTimeInterval(-1_000))
        #expect(FollowUpNotificationPlanner.plan(for: interaction, asOf: now) == .cancel(id: interaction.id.uuidString))
    }

    @Test func plannerCancelsWhenNoFollowUpOrDone() throws {
        let none = try makeInteraction(followUpDate: nil)
        #expect(FollowUpNotificationPlanner.plan(for: none, asOf: now) == .cancel(id: none.id.uuidString))

        let done = try makeInteraction(followUpDate: now.addingTimeInterval(1_000), done: true)
        #expect(FollowUpNotificationPlanner.plan(for: done, asOf: now) == .cancel(id: done.id.uuidString))
    }

    @Test func plannerCancelsWhenTombstoned() throws {
        let interaction = try makeInteraction(followUpDate: now.addingTimeInterval(1_000), tombstoned: true)
        #expect(FollowUpNotificationPlanner.plan(for: interaction, asOf: now) == .cancel(id: interaction.id.uuidString))
    }

    // MARK: Service

    @Test func syncSchedulesWhenAuthorized() async throws {
        let fake = FakeScheduler()
        fake.status = .authorized
        let service = NotificationService(scheduler: fake)
        let interaction = try makeInteraction(followUpDate: now.addingTimeInterval(1_000))

        await service.sync(interaction, asOf: now)

        #expect(fake.scheduledIDs == [interaction.id.uuidString])
        #expect(fake.cancelledIDs.isEmpty)
    }

    @Test func syncDoesNotScheduleWhenDeniedAndDoesNotReprompt() async throws {
        let fake = FakeScheduler()
        fake.status = .denied
        let service = NotificationService(scheduler: fake)
        let interaction = try makeInteraction(followUpDate: now.addingTimeInterval(1_000))

        await service.sync(interaction, asOf: now)

        #expect(fake.scheduledIDs.isEmpty)
        #expect(fake.requestCount == 0, "denied users must not be re-prompted")
    }

    @Test func syncRequestsAuthorizationWhenUndetermined() async throws {
        let fake = FakeScheduler()
        fake.status = .notDetermined
        fake.requestResult = true
        let service = NotificationService(scheduler: fake)
        let interaction = try makeInteraction(followUpDate: now.addingTimeInterval(1_000))

        await service.sync(interaction, asOf: now)

        #expect(fake.requestCount == 1)
        #expect(fake.scheduledIDs == [interaction.id.uuidString])
    }

    @Test func syncCancelsForCompletedFollowUp() async throws {
        let fake = FakeScheduler()
        let service = NotificationService(scheduler: fake)
        let interaction = try makeInteraction(followUpDate: now.addingTimeInterval(1_000), done: true)

        await service.sync(interaction, asOf: now)

        #expect(fake.scheduledIDs.isEmpty)
        #expect(fake.cancelledIDs == [interaction.id.uuidString])
    }
}
