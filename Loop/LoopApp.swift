//
//  LoopApp.swift
//  Loop
//
//  Created by Aggarwal, Kamal on 7/22/26.
//

import SwiftUI
import SwiftData

@main
struct LoopApp: App {
    /// The shared SwiftData container. SwiftData is the local-first source of
    /// truth; the sync engine reconciles it with Supabase.
    let sharedModelContainer: ModelContainer

    /// App-wide session; its ownerUserId is driven by `AuthService`.
    @State private var session: AppSession

    /// Manages authentication state and drives the session.
    @State private var authService: AuthService

    /// Routes follow-up notification taps into navigation.
    @State private var notificationRouter = NotificationRouter()

    /// Bidirectional local <-> Supabase sync.
    @State private var syncEngine: SyncEngine

    /// AI summaries / action items / drafts (with on-device PII redaction).
    @State private var aiService: AIService

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let schema = Schema([Person.self, Interaction.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        sharedModelContainer = container

        let session = AppSession()
        let supabase = SupabaseService()
        _session = State(initialValue: session)
        _authService = State(
            initialValue: AuthService(
                client: supabase.client,
                session: session,
                modelContainer: container
            )
        )
        _syncEngine = State(
            initialValue: SyncEngine(
                client: supabase.client,
                session: session,
                modelContainer: container
            )
        )
        let aiBackend: AIBackend? = supabase.client.map(SupabaseAIBackend.init)
        _aiService = State(initialValue: AIService(backend: aiBackend))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(authService)
                .environment(notificationRouter)
                .environment(syncEngine)
                .environment(aiService)
                .task { notificationRouter.register() }
                .task { await authService.bootstrap() }
                // Sync when the user becomes authenticated.
                .onChange(of: authService.state) { _, newState in
                    if newState == .signedIn {
                        Task { await syncEngine.sync() }
                    }
                }
                // Sync when returning to the foreground.
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active, authService.state == .signedIn {
                        Task { await syncEngine.sync() }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
