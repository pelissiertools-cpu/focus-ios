//
//  Section.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation

/// Represents the section where a task is committed (Focus or Extra)
enum Section: String, Codable, CaseIterable {
    case focus = "focus"
    case extra = "extra"

    var displayName: String {
        switch self {
        case .focus: return "Focus"
        case .extra: return "Extra"
        }
    }

    /// Maximum number of tasks allowed in this section
    /// Focus has limits, Extra is unlimited
    func maxTasks(for timeframe: Timeframe) -> Int? {
        switch self {
        case .focus:
            return timeframe == .yearly ? 10 : 3
        case .extra:
            return nil // Unlimited
        }
    }
}
