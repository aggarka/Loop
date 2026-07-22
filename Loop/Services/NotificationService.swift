//
//  NotificationService.swift
//  Loop
//
//  Schedules, reschedules, and cancels local notifications for follow-ups. The
//  scheduling decision is a pure function (`FollowUpNotificationPlanner`) so it
//  can be unit-tested without the system notification center.
//

import Foundation
import UserNotifications

// MARK: - Scheduling decision (pure, testable)

/// The action to take for a given interaction's follow-up notification.
enum FollowUpNotificationPlan: Equatable {
    case schedule(id: String, fireDate: Date, personName: String, personID: String)
    case cancel(id: String)
}

enum FollowUpNotificationPlanner {
    /// Decides whether an interaction should have a scheduled follow-up
    /// notification. Cancels when there is no actionable, future, pending
    /// follow-up (including overdue ones, which live in the in-app feed instead).
    static func plan(for interaction: Interaction, asOf now: Date) -> FollowUpNotificationPlan {
        let id = interaction.id.uuidString

        guard !interaction.isTombstoned,
              interaction.followUpStatus == .pending,
              let fireDate = interaction.followUpDate,
              let person = interaction.person,
              !person.isTombstoned,
              fireDate > now
        else {
            return .cancel(id: id)
        }

        return .schedule(
            id: id,
            fireDate: fireDate,
            personName: person.name,
            personID: person.id.uuidString
        )
    }
}

// MARK: - Center abstraction

/// Abstraction over the parts of `UNUserNotificationCenter` the app uses, so the
/// service can be tested with a fake.
protocol NotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func schedule(
        id: String,
        title: String,
        body: String,
        fireDate: Date,
        userInfo: [String: String]
    ) async
    func cancel(ids: [String])
}

// MARK: - Service

@MainActor
final class NotificationService {
    static let personIDKey = "personID"
    static let interactionIDKey = "interactionID"

    private let scheduler: NotificationScheduling

    init(scheduler: NotificationScheduling = SystemNotificationScheduler()) {
        self.scheduler = scheduler
    }

    /// Requests authorization only when the status is undetermined, so a user who
    /// previously denied is never re-prompted (Requirement 8.5).
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        // Skip the system permission prompt during UI tests.
        if ProcessInfo.processInfo.environment["UITESTS"] == "1" { return false }
        switch await scheduler.authorizationStatus() {
        case .notDetermined:
            return await scheduler.requestAuthorization()
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    /// Reconciles the scheduled notification for an interaction with its current
    /// state: schedules a future pending follow-up (requesting permission if
    /// needed) or cancels any existing notification otherwise.
    func sync(_ interaction: Interaction, asOf now: Date = Date()) async {
        switch FollowUpNotificationPlanner.plan(for: interaction, asOf: now) {
        case .cancel(let id):
            scheduler.cancel(ids: [id])
        case .schedule(let id, let fireDate, let personName, let personID):
            guard await requestAuthorizationIfNeeded() else {
                // Denied: rely on the in-app Next Actions feed (Requirement 8.5).
                return
            }
            await scheduler.schedule(
                id: id,
                title: "Follow up with \(personName)",
                body: "You set a reminder to follow up.",
                fireDate: fireDate,
                userInfo: [Self.personIDKey: personID, Self.interactionIDKey: id]
            )
        }
    }

    func cancel(interactionID: UUID) {
        scheduler.cancel(ids: [interactionID.uuidString])
    }
}

// MARK: - System implementation

struct SystemNotificationScheduler: NotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func schedule(
        id: String,
        title: String,
        body: String,
        fireDate: Date,
        userInfo: [String: String]
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        // Fire at 9am on the follow-up day for a friendlier reminder time.
        var components = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
        components.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        try? await center.add(request)
    }

    func cancel(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
