//
//  Section.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation

/// Represents the section where a task is committed (Focus or To-Do)
enum Section: String, Codable, CaseIterable {
    case focus = "target"
    case todo = "todo"

    var displayName: String {
        switch self {
        case .focus: return "Focus"
        case .todo: return "To-Do"
        }
    }

    /// Maximum number of tasks allowed in this section
    /// Focus has limits, To-Do is unlimited
    func maxTasks(for timeframe: Timeframe) -> Int? {
        switch self {
        case .focus:
            switch timeframe {
            case .daily: return 3
            case .yearly: return 10
            default: return 5
            }
        case .todo:
            return nil // Unlimited
        }
    }
}
