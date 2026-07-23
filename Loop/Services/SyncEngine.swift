//
//  SyncEngine.swift
//  Loop
//
//  Bidirectional sync between the local SwiftData store and Supabase Postgres.
//  Push uploads locally-changed (dirty) records; pull applies remote changes
//  since the last watermark. Conflicts resolve last-writer-wins by updated_at,
//  and deletes propagate as tombstones. All work is local-first: the app is
//  fully usable offline and syncs when connectivity returns.
//

import Foundation
import Observation
import Network
import SwiftData
import Supabase

@MainActor
@Observable
final class SyncEngine {
    enum Status: Equatable {
        case idle
        case syncing
        case offline
        case error(String)
    }

    private(set) var status: Status = .idle

    private let client: SupabaseClient?
    private let session: AppSession
    private let modelContainer: ModelContainer

    private let monitor = NWPathMonitor()
    private var isOnline = true
    private var isSyncing = false

    // Realtime
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeSubscriptions: [RealtimeSubscription] = []
    private var realtimeOwnerId: String?

    init(client: SupabaseClient?, session: AppSession, modelContainer: ModelContainer) {
        self.client = client
        self.session = session
        self.modelContainer = modelContainer
        startMonitoring()
    }

    // MARK: Connectivity (Requirement 12.3)

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let online = path.status == .satisfied
                let wasOffline = !self.isOnline
                self.isOnline = online
                if !online {
                    self.status = .offline
                } else if wasOffline {
                    // Back online: flush pending local changes.
                    await self.sync()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "loop.sync.monitor"))
    }

    // MARK: Realtime (Requirement 12.2 — live propagation)

    /// Subscribes to postgres changes on the user's rows so edits from other
    /// devices are pulled in live. Idempotent per owner; safe to call repeatedly.
    func startRealtime() async {
        guard let client else { return }
        let owner = session.ownerUserId
        guard UUID(uuidString: owner) != nil else { return }
        if realtimeChannel != nil, realtimeOwnerId == owner { return }

        await stopRealtime()
        realtimeOwnerId = owner

        let channel = client.channel("loop-sync-\(owner)")
        let ownerFilter = RealtimePostgresFilter.eq("owner_user_id", value: owner)
        let onChange: @Sendable (AnyAction) -> Void = { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }

        for table in ["persons", "interactions"] {
            let subscription = channel.onPostgresChange(
                AnyAction.self,
                schema: "public",
                table: table,
                filter: ownerFilter,
                callback: onChange
            )
            realtimeSubscriptions.append(subscription)
        }

        await channel.subscribe()
        realtimeChannel = channel
    }

    /// Tears down the realtime subscription (e.g. on sign-out).
    func stopRealtime() async {
        for subscription in realtimeSubscriptions { subscription.cancel() }
        realtimeSubscriptions.removeAll()
        if let channel = realtimeChannel {
            await client?.removeChannel(channel)
        }
        realtimeChannel = nil
        realtimeOwnerId = nil
    }

    // MARK: Full sync

    /// Pushes local changes then pulls remote changes. No-op when unconfigured,
    /// signed out, offline, or already syncing.
    func sync() async {
        guard let client else { return }
        guard isOnline else { status = .offline; return }
        guard UUID(uuidString: session.ownerUserId) != nil else { return } // signed in
        guard !isSyncing else { return }

        isSyncing = true
        status = .syncing
        defer { isSyncing = false }

        do {
            try await push(client)
            try await pull(client)
            status = .idle
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: Push (local -> remote)

    private func push(_ client: SupabaseClient) async throws {
        let context = modelContainer.mainContext

        // Persons first to satisfy the interactions FK.
        let dirtyPersons = try context.fetch(
            FetchDescriptor<Person>(predicate: #Predicate { $0.dirty == true })
        )
        if !dirtyPersons.isEmpty {
            let dtos = dirtyPersons.compactMap(PersonDTO.init)
            try await client.from("persons").upsert(dtos, onConflict: "id").execute()
            let now = Date()
            for person in dirtyPersons {
                person.dirty = false
                person.syncedAt = now
            }
        }

        let dirtyInteractions = try context.fetch(
            FetchDescriptor<Interaction>(predicate: #Predicate { $0.dirty == true })
        )
        if !dirtyInteractions.isEmpty {
            let dtos = dirtyInteractions.compactMap(InteractionDTO.init)
            try await client.from("interactions").upsert(dtos, onConflict: "id").execute()
            let now = Date()
            for interaction in dirtyInteractions {
                interaction.dirty = false
                interaction.syncedAt = now
            }
        }

        try context.save()
    }

    // MARK: Pull (remote -> local)

    private func pull(_ client: SupabaseClient) async throws {
        let context = modelContainer.mainContext
        let watermark = lastPullDate

        // Persons before interactions so relationships can be linked.
        let remotePersons: [PersonDTO] = try await client
            .from("persons")
            .select()
            .gt("updated_at", value: iso(watermark))
            .execute()
            .value
        for dto in remotePersons {
            try mergePerson(dto, into: context)
        }

        let remoteInteractions: [InteractionDTO] = try await client
            .from("interactions")
            .select()
            .gt("updated_at", value: iso(watermark))
            .execute()
            .value
        for dto in remoteInteractions {
            try mergeInteraction(dto, into: context)
        }

        try context.save()
        lastPullDate = Date()
    }

    // MARK: Merge helpers (last-writer-wins by updated_at)

    private func mergePerson(_ dto: PersonDTO, into context: ModelContext) throws {
        let id = dto.id
        let existing = try context.fetch(
            FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })
        ).first

        let decision = SyncResolver.decide(
            localExists: existing != nil,
            localDirty: existing?.dirty ?? false,
            localUpdatedAt: existing?.updatedAt,
            remoteUpdatedAt: dto.updated_at,
            remoteTombstoned: dto.is_tombstoned
        )

        switch decision {
        case .skip, .keepLocal:
            return
        case .deleteLocal:
            if let existing { context.delete(existing) }
        case .applyRemote:
            if let existing { apply(dto, to: existing) }
        case .insertRemote:
            let person = Person(
                id: dto.id,
                ownerUserId: dto.owner_user_id.uuidString,
                name: dto.name,
                dirty: false
            )
            apply(dto, to: person)
            context.insert(person)
        }
    }

    private func apply(_ dto: PersonDTO, to person: Person) {
        person.ownerUserId = dto.owner_user_id.uuidString
        person.name = dto.name
        person.company = dto.company
        person.title = dto.title
        person.email = dto.email
        person.phone = dto.phone
        person.tags = dto.tags
        person.sourceRaw = dto.source
        person.lastContactedDate = dto.last_contacted_date
        person.createdAt = dto.created_at
        person.updatedAt = dto.updated_at
        person.isTombstoned = dto.is_tombstoned
        person.dirty = false
        person.syncedAt = Date()
    }

    private func mergeInteraction(_ dto: InteractionDTO, into context: ModelContext) throws {
        let id = dto.id
        let existing = try context.fetch(
            FetchDescriptor<Interaction>(predicate: #Predicate { $0.id == id })
        ).first

        let decision = SyncResolver.decide(
            localExists: existing != nil,
            localDirty: existing?.dirty ?? false,
            localUpdatedAt: existing?.updatedAt,
            remoteUpdatedAt: dto.updated_at,
            remoteTombstoned: dto.is_tombstoned
        )

        switch decision {
        case .skip, .keepLocal:
            return
        case .deleteLocal:
            if let existing { context.delete(existing) }
        case .applyRemote:
            if let existing { apply(dto, to: existing, in: context) }
        case .insertRemote:
            let interaction = Interaction(
                id: dto.id,
                ownerUserId: dto.owner_user_id.uuidString,
                date: dto.date,
                type: InteractionType(rawValue: dto.type) ?? .coffeeChat,
                dirty: false
            )
            apply(dto, to: interaction, in: context)
            context.insert(interaction)
        }
    }

    private func apply(_ dto: InteractionDTO, to interaction: Interaction, in context: ModelContext) {
        let personID = dto.person_id
        interaction.person = try? context.fetch(
            FetchDescriptor<Person>(predicate: #Predicate { $0.id == personID })
        ).first
        interaction.ownerUserId = dto.owner_user_id.uuidString
        interaction.date = dto.date
        interaction.typeRaw = dto.type
        interaction.notes = dto.notes
        interaction.outcomes = dto.outcomes
        interaction.aiSummary = dto.ai_summary
        interaction.followUpDate = dto.follow_up_date
        interaction.followUpStatusRaw = dto.follow_up_status
        interaction.createdAt = dto.created_at
        interaction.updatedAt = dto.updated_at
        interaction.isTombstoned = dto.is_tombstoned
        interaction.dirty = false
        interaction.syncedAt = Date()
    }

    // MARK: Watermark persistence

    private var watermarkKey: String { "loop.sync.lastPull.\(session.ownerUserId)" }

    private var lastPullDate: Date {
        get {
            let value = UserDefaults.standard.double(forKey: watermarkKey)
            return value > 0 ? Date(timeIntervalSince1970: value) : Date(timeIntervalSince1970: 0)
        }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: watermarkKey) }
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
