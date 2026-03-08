//
//  SupabaseConfig.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation

/// Configuration for Supabase connection
/// Reads credentials from Info.plist, which pulls from Secrets.xcconfig at build time.
/// See Secrets.xcconfig.template for setup instructions.
enum SupabaseConfig {
    static let supabaseURL: String = {
        guard let value = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String, !value.isEmpty else {
            fatalError("SUPABASE_URL not set. Copy Secrets.xcconfig.template to Secrets.xcconfig and fill in your credentials.")
        }
        return value
    }()

    static let supabaseAnonKey: String = {
        guard let value = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String, !value.isEmpty else {
            fatalError("SUPABASE_ANON_KEY not set. Copy Secrets.xcconfig.template to Secrets.xcconfig and fill in your credentials.")
        }
        return value
    }()
}
