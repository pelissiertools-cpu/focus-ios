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
    static let projectListChanged = Notification.Name("projectListChanged")
    static let schedulesChanged = Notification.Name("schedulesChanged")
    static let sessionRefreshed = Notification.Name("sessionRefreshed")
    static let realtimeTasksChanged = Notification.Name("realtimeTasksChanged")
}

/// Keys for task sync notification userInfo
enum TaskNotificationKeys {
    static let taskId = "taskId"
    static let isCompleted = "isCompleted"
    static let completedDate = "completedDate"
    static let source = "source"
    static let subtasksChanged = "subtasksChanged"
}

/// Source identifiers to prevent notification echo
enum TaskNotificationSource: String {
    case focus = "focus"
    case log = "log"
    case realtime = "realtime"
}

/// Tracks when any ViewModel last performed a local mutation.
/// Used to suppress Realtime echo notifications (object == nil) that arrive
/// shortly after the user's own change, preventing redundant re-fetches and UI flashes.
@MainActor
enum LocalMutationTracker {
    static var lastMutationDate: Date?

    static func markMutation() {
        lastMutationDate = Date()
    }

    static func isRecentlyMutated(within seconds: TimeInterval = 2.0) -> Bool {
        guard let last = lastMutationDate else { return false }
        return Date().timeIntervalSince(last) < seconds
    }
}
