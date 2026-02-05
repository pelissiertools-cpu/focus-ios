//
//  SupabaseConfig.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation

/// Configuration for Supabase connection
/// IMPORTANT: In production, use .xcconfig files or environment variables
/// Never commit credentials to git
enum SupabaseConfig {
    static let supabaseURL = "https://ajsjtgnwbmdynwcrwdqb.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFqc2p0Z253Ym1keW53Y3J3ZHFiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzMjQwMDAsImV4cCI6MjA4NTkwMDAwMH0.GSnfe6ykbmkeRzGZV9gN5xU9E0RZrlKsIiOlny39PFw"
}
