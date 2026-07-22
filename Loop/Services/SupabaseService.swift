//
//  SupabaseService.swift
//  Loop
//
//  Provides the shared Supabase client, configured from `Supabase-Info.plist`.
//  When no configuration is present the client is nil and the app runs in a
//  local-only mode (no auth / sync).
//

import Foundation
import Supabase

@MainActor
final class SupabaseService {
    let client: SupabaseClient?

    init(config: SupabaseConfig? = SupabaseConfig.loadFromBundle()) {
        if let config {
            client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey)
        } else {
            client = nil
        }
    }

    var isConfigured: Bool { client != nil }
}
