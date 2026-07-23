//
//  SyncResolver.swift
//  Loop
//
//  Pure conflict-resolution decision for the sync engine: given the local state
//  of a record and an incoming remote version, decide what to do. Kept free of
//  SwiftData/network so it can be unit-tested in isolation.
//

import Foundation

/// What the sync engine should do with an incoming remote record.
enum SyncMergeDecision: Equatable {
    /// No local copy exists and the remote is live: insert it.
    case insertRemote
    /// No local copy exists and the remote is a tombstone: nothing to do.
    case skip
    /// A newer, unsynced local edit exists: keep local, ignore remote.
    case keepLocal
    /// Remote is a tombstone and should win: delete the local copy.
    case deleteLocal
    /// Remote wins: overwrite the local copy with remote fields.
    case applyRemote
}

enum SyncResolver {
    /// Resolves a remote change against local state using last-writer-wins by
    /// `updatedAt`. Local unsynced (`dirty`) edits win only when they are at
    /// least as new as the remote; otherwise the remote wins. Tombstones
    /// propagate as deletes.
    static func decide(
        localExists: Bool,
        localDirty: Bool,
        localUpdatedAt: Date?,
        remoteUpdatedAt: Date,
        remoteTombstoned: Bool
    ) -> SyncMergeDecision {
        guard localExists else {
            return remoteTombstoned ? .skip : .insertRemote
        }

        // A dirty local edit that is newer than (or equal to) the remote wins,
        // so we don't clobber changes that haven't been pushed yet.
        if localDirty, let localUpdatedAt, localUpdatedAt >= remoteUpdatedAt {
            return .keepLocal
        }

        return remoteTombstoned ? .deleteLocal : .applyRemote
    }
}
