//
//  Task.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation

/// Represents a task, project, or list in the Focus app
/// Maps to the tasks table in Supabase
struct FocusTask: Codable, Identifiable {
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
        self.categoryId = categoryId
        self.projectId = projectId
        self.parentTaskId = parentTaskId
    }
}
