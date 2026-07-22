//
//  InteractionRepositoryTests.swift
//  LoopTests
//

import Foundation
import Testing
import SwiftData
@testable import Loop

@MainActor
struct InteractionRepositoryTests {

    @Test func timelineIsReverseChronological() throws {
        let context = try TestSupport.makeContext()
        let (people, interactions) = TestSupport.makeRepositories(context)
        let person = try people.create(PersonDraft(name: "Katherine Johnson"))

        let t1 = Date(timeIntervalSince1970: 100)
        let t2 = Date(timeIntervalSince1970: 200)
        let t3 = Date(timeIntervalSince1970: 300)
        _ = try interactions.create(InteractionDraft(date: t2, type: .email), for: person)
        _ = try interactions.create(InteractionDraft(date: t1, type: .event), for: person)
        _ = try interactions.create(InteractionDraft(date: t3, type: .coffeeChat), for: person)

        let dates = interactions.timeline(for: person).map(\.date)
        #expect(dates == [t3, t2, t1])
    }

    @Test func createSetsFollowUpStatusFromDate() throws {
        let context = try TestSupport.makeContext()
        let (people, interactions) = TestSupport.makeRepositories(context)
        let person = try people.create(PersonDraft(name: "Person A"))

        let withFollowUp = try interactions.create(
            InteractionDraft(type: .coffeeChat, followUpDate: Date()), for: person
        )
        let withoutFollowUp = try interactions.create(
            InteractionDraft(type: .coffeeChat), for: person
        )

        #expect(withFollowUp.followUpStatus == .pending)
        #expect(withoutFollowUp.followUpStatus == .none)
    }

    @Test func deleteRecomputesLastContacted() throws {
        let context = try TestSupport.makeContext()
        let (people, interactions) = TestSupport.makeRepositories(context)
        let person = try people.create(PersonDraft(name: "Person B"))

        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        _ = try interactions.create(InteractionDraft(date: older, type: .email), for: person)
        let latest = try interactions.create(InteractionDraft(date: newer, type: .email), for: person)

        #expect(person.lastContactedDate == newer)
        try interactions.delete(latest)
        #expect(person.lastContactedDate == older)
    }

    @Test func nextActionsOrdersOverdueBeforeUpcomingBySoonest() throws {
        let context = try TestSupport.makeContext()
        let (people, interactions) = TestSupport.makeRepositories(context)
        let person = try people.create(PersonDraft(name: "Person C"))

        let now = Date(timeIntervalSince1970: 10_000)
        let overdueOld = now.addingTimeInterval(-5_000)
        let overdueRecent = now.addingTimeInterval(-1_000)
        let upcomingSoon = now.addingTimeInterval(1_000)
        let upcomingLater = now.addingTimeInterval(5_000)

        _ = try interactions.create(InteractionDraft(type: .email, followUpDate: upcomingLater), for: person)
        _ = try interactions.create(InteractionDraft(type: .email, followUpDate: overdueRecent), for: person)
        _ = try interactions.create(InteractionDraft(type: .email, followUpDate: upcomingSoon), for: person)
        _ = try interactions.create(InteractionDraft(type: .email, followUpDate: overdueOld), for: person)

        let feed = interactions.nextActions(asOf: now)
        #expect(feed.map(\.followUpDate) == [overdueOld, overdueRecent, upcomingSoon, upcomingLater])
        #expect(feed.map(\.isOverdue) == [true, true, false, false])
    }

    @Test func markingFollowUpDoneRemovesItFromNextActions() throws {
        let context = try TestSupport.makeContext()
        let (people, interactions) = TestSupport.makeRepositories(context)
        let person = try people.create(PersonDraft(name: "Person D"))

        let now = Date(timeIntervalSince1970: 10_000)
        let interaction = try interactions.create(
            InteractionDraft(type: .email, followUpDate: now.addingTimeInterval(-100)),
            for: person
        )
        #expect(interactions.nextActions(asOf: now).count == 1)

        try interactions.markFollowUpDone(interaction)
        #expect(interactions.nextActions(asOf: now).isEmpty)
        #expect(interaction.followUpStatus == .done)
    }
}
