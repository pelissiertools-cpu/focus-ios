//
//  Timeframe.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation

/// Represents the different timeframes for task commitments
enum Timeframe: String, Codable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case yearly = "yearly"

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    /// The next lower timeframe for trickle-down breakdown
    var childTimeframe: Timeframe? {
        switch self {
        case .yearly: return .monthly
        case .monthly: return .weekly
        case .weekly: return .daily
        case .daily: return nil
        }
    }

    /// All timeframes this can break down to (not just the immediate child)
    var availableBreakdownTimeframes: [Timeframe] {
        switch self {
        case .yearly: return [.monthly, .weekly, .daily]
        case .monthly: return [.weekly, .daily]
        case .weekly: return [.daily]
        case .daily: return []
        }
    }
}
