//
//  SyncResolverTests.swift
//  LoopTests
//

import Foundation
import Testing
@testable import Loop

struct SyncResolverTests {
    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    // MARK: No local copy

    @Test func insertsRemoteWhenNoLocalAndLive() {
        let decision = SyncResolver.decide(
            localExists: false, localDirty: false, localUpdatedAt: nil,
            remoteUpdatedAt: newer, remoteTombstoned: false
        )
        #expect(decision == .insertRemote)
    }

    @Test func skipsRemoteTombstoneWhenNoLocal() {
        let decision = SyncResolver.decide(
            localExists: false, localDirty: false, localUpdatedAt: nil,
            remoteUpdatedAt: newer, remoteTombstoned: true
        )
        #expect(decision == .skip)
    }

    // MARK: Last-writer-wins

    @Test func remoteWinsWhenLocalIsClean() {
        // Even if local timestamp is newer, a clean (already-synced) local record
        // yields to the remote.
        let decision = SyncResolver.decide(
            localExists: true, localDirty: false, localUpdatedAt: newer,
            remoteUpdatedAt: older, remoteTombstoned: false
        )
        #expect(decision == .applyRemote)
    }

    @Test func localWinsWhenDirtyAndNewer() {
        let decision = SyncResolver.decide(
            localExists: true, localDirty: true, localUpdatedAt: newer,
            remoteUpdatedAt: older, remoteTombstoned: false
        )
        #expect(decision == .keepLocal)
    }

    @Test func remoteWinsWhenDirtyButOlderThanRemote() {
        let decision = SyncResolver.decide(
            localExists: true, localDirty: true, localUpdatedAt: older,
            remoteUpdatedAt: newer, remoteTombstoned: false
        )
        #expect(decision == .applyRemote)
    }

    @Test func localWinsWhenDirtyAndEqualTimestamp() {
        // Tie goes to the local dirty edit so unpushed changes aren't lost.
        let decision = SyncResolver.decide(
            localExists: true, localDirty: true, localUpdatedAt: newer,
            remoteUpdatedAt: newer, remoteTombstoned: false
        )
        #expect(decision == .keepLocal)
    }

    // MARK: Tombstones

    @Test func remoteTombstoneDeletesLocalWhenLocalNotNewer() {
        let decision = SyncResolver.decide(
            localExists: true, localDirty: false, localUpdatedAt: older,
            remoteUpdatedAt: newer, remoteTombstoned: true
        )
        #expect(decision == .deleteLocal)
    }

    @Test func dirtyNewerLocalIsNotDeletedByStaleTombstone() {
        // A tombstone that is older than a newer local dirty edit must not win.
        let decision = SyncResolver.decide(
            localExists: true, localDirty: true, localUpdatedAt: newer,
            remoteUpdatedAt: older, remoteTombstoned: true
        )
        #expect(decision == .keepLocal)
    }
}
