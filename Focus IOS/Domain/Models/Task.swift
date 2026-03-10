//
//  Task.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation

/// Represents a task, project, or list in the Focus app
/// Maps to the tasks table in Supabase
struct FocusTask: Codable, Identifiable, Hashable, Equatable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: UUID
    let userId: UUID
    var title: String
    var description: String?
    var type: TaskType
    var isCompleted: Bool
    var completedDate: Date?
    let createdDate: Date
    var modifiedDate: Date
    var sortOrder: Int
    var isInLibrary: Bool
    var previousCompletionState: [Bool]?
    var priority: Priority
    var isSection: Bool
    var isCleared: Bool
    var isPinned: Bool

    // Due date
    var dueDate: Date?

    // Notification
    var notificationEnabled: Bool
    var notificationDate: Date?

    // Foreign keys
    var categoryId: UUID?
    var projectId: UUID?
    var parentTaskId: UUID?

    // Coding keys to match Supabase snake_case
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case description
        case type
        case isCompleted = "is_completed"
        case completedDate = "completed_date"
        case createdDate = "created_date"
        case modifiedDate = "modified_date"
        case sortOrder = "sort_order"
        case isInLibrary = "is_in_library"
        case previousCompletionState = "previous_completion_state"
        case priority
        case isSection = "is_section"
        case isCleared = "is_cleared"
        case isPinned = "is_pinned"
        case dueDate = "due_date"
        case notificationEnabled = "notification_enabled"
        case notificationDate = "notification_date"
        case categoryId = "category_id"
        case projectId = "project_id"
        case parentTaskId = "parent_task_id"
    }

    /// Initializer for creating new tasks
    init(
        id: UUID = UUID(),
        userId: UUID,
        title: String,
        description: String? = nil,
        type: TaskType = .task,
        isCompleted: Bool = false,
        completedDate: Date? = nil,
        createdDate: Date = Date(),
        modifiedDate: Date = Date(),
        sortOrder: Int = 0,
        isInLibrary: Bool = true,
        previousCompletionState: [Bool]? = nil,
        priority: Priority = .low,
        isSection: Bool = false,
        isCleared: Bool = false,
        isPinned: Bool = false,
        dueDate: Date? = nil,
        notificationEnabled: Bool = false,
        notificationDate: Date? = nil,
        categoryId: UUID? = nil,
        projectId: UUID? = nil,
        parentTaskId: UUID? = nil
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.description = description
        self.type = type
        self.isCompleted = isCompleted
        self.completedDate = completedDate
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.sortOrder = sortOrder
        self.isInLibrary = isInLibrary
        self.previousCompletionState = previousCompletionState
        self.priority = priority
        self.isSection = isSection
        self.isCleared = isCleared
        self.isPinned = isPinned
        self.dueDate = dueDate
        self.notificationEnabled = notificationEnabled
        self.notificationDate = notificationDate
        self.categoryId = categoryId
        self.projectId = projectId
        self.parentTaskId = parentTaskId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(type, forKey: .type)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(completedDate, forKey: .completedDate)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(modifiedDate, forKey: .modifiedDate)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(isInLibrary, forKey: .isInLibrary)
        try container.encode(previousCompletionState, forKey: .previousCompletionState)
        try container.encode(priority, forKey: .priority)
        try container.encode(isSection, forKey: .isSection)
        try container.encode(isCleared, forKey: .isCleared)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(notificationEnabled, forKey: .notificationEnabled)
        try container.encode(notificationDate, forKey: .notificationDate)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(parentTaskId, forKey: .parentTaskId)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        type = try container.decode(TaskType.self, forKey: .type)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        completedDate = try container.decodeIfPresent(Date.self, forKey: .completedDate)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        modifiedDate = try container.decode(Date.self, forKey: .modifiedDate)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isInLibrary = try container.decode(Bool.self, forKey: .isInLibrary)
        previousCompletionState = try container.decodeIfPresent([Bool].self, forKey: .previousCompletionState)
        priority = try container.decode(Priority.self, forKey: .priority)
        isSection = try container.decode(Bool.self, forKey: .isSection)
        isCleared = try container.decodeIfPresent(Bool.self, forKey: .isCleared) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        notificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationEnabled) ?? false
        notificationDate = try container.decodeIfPresent(Date.self, forKey: .notificationDate)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
        parentTaskId = try container.decodeIfPresent(UUID.self, forKey: .parentTaskId)
    }
}
