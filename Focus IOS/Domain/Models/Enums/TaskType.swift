//
//  TaskType.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation

/// Represents the type of a task entity
enum TaskType: String, Codable, CaseIterable {
    case task = "task"
    case project = "project"
    case list = "list"

    var displayName: String {
        switch self {
        case .task: return "Task"
        case .project: return "Project"
        case .list: return "List"
        }
    }
}
