//
//  SupabaseConfig.swift
//  Loop
//
//  Holds the Supabase connection settings used by the auth and sync layers
//  (added in later tasks). Values are loaded from an optional, git-ignored
//  `Supabase-Info.plist` bundled with the app, so the anon key never has to be
//  committed to source control. The anon key is a public client key protected by
//  Row Level Security; the service-role key lives only in Edge Functions.
//

import Foundation

struct SupabaseConfig {
    let url: URL
    let anonKey: String

    /// Loads configuration from `Supabase-Info.plist` if present.
    /// Returns `nil` when the app has not yet been configured, allowing the app
    /// to run in a local-only mode during early development.
    static func loadFromBundle(_ bundle: Bundle = .main) -> SupabaseConfig? {
        guard
            let path = bundle.url(forResource: "Supabase-Info", withExtension: "plist"),
            let data = try? Data(contentsOf: path),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as? [String: Any],
            let urlString = plist["SUPABASE_URL"] as? String,
            let url = URL(string: urlString),
            let anonKey = plist["SUPABASE_ANON_KEY"] as? String,
            !anonKey.isEmpty
        else {
            return nil
        }
        return SupabaseConfig(url: url, anonKey: anonKey)
    }
}
