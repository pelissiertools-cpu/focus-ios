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

    /// Label for "Push to Next" context menu action
    var nextTimeframeLabel: String {
        switch self {
        case .daily: return "Tomorrow"
        case .weekly: return "Next Week"
        case .monthly: return "Next Month"
        case .yearly: return "Next Year"
        }
    }

    /// Label for "Remove from" context menu action
    var removeLabel: String {
        switch self {
        case .daily: return "Remove from today"
        case .weekly: return "Remove from this week"
        case .monthly: return "Remove from this month"
        case .yearly: return "Remove from this year"
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

    /// Urgency index: lower = more urgent (daily=0, weekly=1, monthly=2, yearly=3)
    var urgencyIndex: Int {
        switch self {
        case .daily: return 0
        case .weekly: return 1
        case .monthly: return 2
        case .yearly: return 3
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
