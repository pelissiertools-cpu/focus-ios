//
//  TaskSyncNotification.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-07.
//

import Foundation

/// Notification for syncing task completion state between views
extension Notification.Name {
    static let taskCompletionChanged = Notification.Name("taskCompletionChanged")
}

/// Keys for task sync notification userInfo
enum TaskNotificationKeys {
    static let taskId = "taskId"
    static let isCompleted = "isCompleted"
    static let completedDate = "completedDate"
    static let source = "source"
}

/// Source identifiers to prevent notification echo
enum TaskNotificationSource: String {
    case focus = "focus"
    case library = "library"
}
