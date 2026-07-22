//
//  ContentView.swift
//  Loop
//
//  Created by Aggarwal, Kamal on 7/22/26.
//

import SwiftUI
import SwiftData

/// Root view. Gates on authentication state, then presents the primary tabs
/// with Next Actions as the entry point.
struct ContentView: View {
    @Environment(AuthService.self) private var authService
    @Environment(NotificationRouter.self) private var router
    @State private var selection = Tabs.nextActions

    private enum Tabs: Hashable { case nextActions, people, settings }

    var body: some View {
        switch authService.state {
        case .loading:
            ProgressView()
        case .signedOut:
            AuthView()
        case .signedIn:
            mainTabs
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selection) {
            Tab("Next Actions", systemImage: "checklist", value: Tabs.nextActions) {
                NextActionsView()
            }
            Tab("People", systemImage: "person.2", value: Tabs.people) {
                PeopleListView()
            }
            Tab("Settings", systemImage: "gearshape", value: Tabs.settings) {
                SettingsView()
            }
        }
        // When a follow-up notification is tapped, jump to the People tab; the
        // list navigates to the person and clears the router.
        .onChange(of: router.pendingPersonID) { _, newValue in
            if newValue != nil { selection = .people }
        }
    }
}
