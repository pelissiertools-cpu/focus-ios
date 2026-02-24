//
//  Section.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation

/// Represents the section where a task is committed (Targets or To-Do)
enum Section: String, Codable, CaseIterable {
    case target = "target"
    case todo = "todo"

    var displayName: String {
        switch self {
        case .target: return "Targets"
        case .todo: return "To-Do"
        }
    }

    /// Maximum number of tasks allowed in this section
    /// Targets has limits, To-Do is unlimited
    func maxTasks(for timeframe: Timeframe) -> Int? {
        switch self {
        case .target:
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
