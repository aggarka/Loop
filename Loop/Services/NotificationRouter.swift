//
//  NotificationRouter.swift
//  Loop
//
//  Bridges notification taps into SwiftUI navigation. The delegate records the
//  tapped person's id on the router; the UI observes it and navigates to that
//  person's detail (Requirement 8.4).
//

import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationRouter {
    /// Set when the user taps a follow-up notification; the UI consumes and
    /// clears it to navigate to the person.
    var pendingPersonID: String?

    /// Retains the delegate for the app's lifetime.
    @ObservationIgnored private var delegate: NotificationDelegate?

    /// Installs the notification-center delegate. Call once at launch.
    func register() {
        let delegate = NotificationDelegate(router: self)
        self.delegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
    }
}

/// `UNUserNotificationCenter` delegate that forwards taps to a `NotificationRouter`.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let router: NotificationRouter

    init(router: NotificationRouter) {
        self.router = router
    }

    /// Show banners even while the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Record the tapped person so the UI can navigate to them.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let personID = userInfo[NotificationService.personIDKey] as? String else { return }
        await MainActor.run {
            router.pendingPersonID = personID
        }
    }
}
