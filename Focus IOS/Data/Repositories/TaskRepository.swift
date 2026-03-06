//
//  TaskRepository.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation
import Supabase

/// Repository for managing tasks in Supabase
class TaskRepository {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseClientManager.shared.client) {
        self.supabase = supabase
    }

    /// Helper struct for task updates
    private struct TaskUpdate: Encodable {
        let isCompleted: Bool
        let completedDate: Date?
        let modifiedDate: Date

        enum CodingKeys: String, CodingKey {
            case isCompleted = "is_completed"
            case completedDate = "completed_date"
            case modifiedDate = "modified_date"
        }
    }

    /// Helper struct for clearing tasks (soft-delete)
    private struct ClearUpdate: Encodable {
        let isCleared: Bool
        let modifiedDate: Date

        enum CodingKeys: String, CodingKey {
            case isCleared = "is_cleared"
            case modifiedDate = "modified_date"
        }
    }

    /// Helper struct for sort order updates
    private struct SortOrderUpdate: Encodable {
        let sortOrder: Int
        let modifiedDate: Date

        enum CodingKeys: String, CodingKey {
            case sortOrder = "sort_order"
            case modifiedDate = "modified_date"
        }
    }

    /// Helper struct for assigning a task to a project/list
    private struct ProjectAssignmentUpdate: Encodable {
        let projectId: UUID
        let sortOrder: Int
        let modifiedDate: Date

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case sortOrder = "sort_order"
            case modifiedDate = "modified_date"
        }
    }

    /// Helper struct for assigning a task as a list item (sets parent_task_id)
    private struct ListItemAssignmentUpdate: Encodable {
        let parentTaskId: UUID
        let sortOrder: Int
        let modifiedDate: Date

        enum CodingKeys: String, CodingKey {
            case parentTaskId = "parent_task_id"
            case sortOrder = "sort_order"
            case modifiedDate = "modified_date"
        }
    }

    /// Fetch all tasks for the current user
    func fetchTasks() async throws -> [FocusTask] {
        let tasks: [FocusTask] = try await supabase
            .from("tasks")
            .select()
            .order("sort_order", ascending: true)
            .order("created_date", ascending: false)
            .execute()
            .value

        return tasks
    }

    /// Fetch completed top-level tasks for archive display
    func fetchCompletedTopLevelTasks() async throws -> [FocusTask] {
        let tasks: [FocusTask] = try await supabase
            .from("tasks")
            .select()
            .eq("is_completed", value: true)
            .eq("is_section", value: false)
            .is("parent_task_id", value: nil)
            .order("completed_date", ascending: false)
            .execute()
            .value

        return tasks
    }

    /// Fetch specific tasks by their IDs
    func fetchTasksByIds(_ ids: [UUID]) async throws -> [FocusTask] {
        guard !ids.isEmpty else { return [] }
        let idStrings = ids.map { $0.uuidString }
        let tasks: [FocusTask] = try await supabase
            .from("tasks")
            .select()
            .in("id", values: idStrings)
            .execute()
            .value

        return tasks
    }

    /// Fetch tasks by type with optional server-side filters
    func fetchTasks(ofType type: TaskType, isCleared: Bool? = nil, isCompleted: Bool? = nil, topLevelOnly: Bool = false) async throws -> [FocusTask] {
        var query = supabase
            .from("tasks")
            .select()
            .eq("type", value: type.rawValue)

        if let isCleared {
            query = query.eq("is_cleared", value: isCleared)
        }
        if let isCompleted {
            query = query.eq("is_completed", value: isCompleted)
        }
        if topLevelOnly {
            query = query.is("parent_task_id", value: nil)
        }

        let tasks: [FocusTask] = try await query
            .order("sort_order", ascending: true)
            .order("created_date", ascending: false)
            .execute()
            .value

        return tasks
    }

    /// Fetch subtasks for a parent task
    func fetchSubtasks(parentId: UUID) async throws -> [FocusTask] {
        let tasks: [FocusTask] = try await supabase
            .from("tasks")
            .select()
            .eq("parent_task_id", value: parentId.uuidString)
            .order("sort_order", ascending: true)
            .execute()
            .value

        return tasks
    }

    /// Create a new task
    func createTask(_ task: FocusTask) async throws -> FocusTask {
        let createdTask: FocusTask = try await supabase
            .from("tasks")
            .insert(task)
            .select()
            .single()
            .execute()
            .value

        return createdTask
    }

    /// Update an existing task
    func updateTask(_ task: FocusTask) async throws {
        try await supabase
            .from("tasks")
            .update(task)
            .eq("id", value: task.id.uuidString)
            .execute()
    }

    /// Delete a task
    func deleteTask(id: UUID) async throws {
        try await supabase
            .from("tasks")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Delete multiple tasks in a single query
    func deleteTasks(ids: Set<UUID>) async throws {
        guard !ids.isEmpty else { return }
        try await supabase
            .from("tasks")
            .delete()
            .in("id", values: ids.map { $0.uuidString })
            .execute()
    }

    /// Mark tasks as cleared (soft-delete — stays in Archive, hidden from local views)
    func clearTasks(ids: Set<UUID>) async throws {
        guard !ids.isEmpty else { return }
        let update = ClearUpdate(isCleared: true, modifiedDate: Date())
        try await supabase
            .from("tasks")
            .update(update)
            .in("id", values: ids.map { $0.uuidString })
            .execute()
    }

    /// Complete a task
    func completeTask(id: UUID) async throws {
        let update = TaskUpdate(
            isCompleted: true,
            completedDate: Date(),
            modifiedDate: Date()
        )

        try await supabase
            .from("tasks")
            .update(update)
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Uncomplete a task
    func uncompleteTask(id: UUID) async throws {
        let update = TaskUpdate(
            isCompleted: false,
            completedDate: nil,
            modifiedDate: Date()
        )

        try await supabase
            .from("tasks")
            .update(update)
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Subtask Operations

    /// Create a subtask under a parent task
    func createSubtask(title: String, parentTaskId: UUID, userId: UUID, projectId: UUID? = nil) async throws -> FocusTask {
        let existingSubtasks = try await fetchSubtasks(parentId: parentTaskId)
        let nextSortOrder = (existingSubtasks.map { $0.sortOrder }.max() ?? -1) + 1

        let subtask = FocusTask(
            userId: userId,
            title: title,
            type: .task,
            isCompleted: false,
            sortOrder: nextSortOrder,
            projectId: projectId,
            parentTaskId: parentTaskId
        )

        return try await createTask(subtask)
    }

    /// Complete all subtasks of a parent task
    func completeSubtasks(parentId: UUID) async throws {
        let update = TaskUpdate(
            isCompleted: true,
            completedDate: Date(),
            modifiedDate: Date()
        )

        try await supabase
            .from("tasks")
            .update(update)
            .eq("parent_task_id", value: parentId.uuidString)
            .execute()
    }

    /// Unlink all tasks from a project (sets project_id to null)
    func unlinkProjectTasks(projectId: UUID) async throws {
        struct ProjectNullUpdate: Encodable {
            let modifiedDate: Date

            enum CodingKeys: String, CodingKey {
                case projectId = "project_id"
                case modifiedDate = "modified_date"
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeNil(forKey: .projectId)
                try container.encode(modifiedDate, forKey: .modifiedDate)
            }
        }

        let update = ProjectNullUpdate(modifiedDate: Date())
        try await supabase
            .from("tasks")
            .update(update)
            .eq("project_id", value: projectId.uuidString)
            .execute()
    }

    /// Assign a task to a project/list (sets project_id only, not parent_task_id)
    func assignToProject(taskId: UUID, projectId: UUID, sortOrder: Int) async throws {
        let update = ProjectAssignmentUpdate(
            projectId: projectId,
            sortOrder: sortOrder,
            modifiedDate: Date()
        )
        try await supabase
            .from("tasks")
            .update(update)
            .eq("id", value: taskId.uuidString)
            .execute()
    }

    /// Assign a task as a list item (sets parent_task_id)
    func assignToList(taskId: UUID, listId: UUID, sortOrder: Int) async throws {
        let update = ListItemAssignmentUpdate(
            parentTaskId: listId,
            sortOrder: sortOrder,
            modifiedDate: Date()
        )
        try await supabase
            .from("tasks")
            .update(update)
            .eq("id", value: taskId.uuidString)
            .execute()
    }

    /// Update sort orders for multiple tasks
    func updateSortOrders(_ updates: [(id: UUID, sortOrder: Int)]) async throws {
        let now = Date()
        for update in updates {
            let sortUpdate = SortOrderUpdate(sortOrder: update.sortOrder, modifiedDate: now)
            try await supabase
                .from("tasks")
                .update(sortUpdate)
                .eq("id", value: update.id.uuidString)
                .execute()
        }
    }

    // MARK: - Project Operations

    /// Fetch all projects for the current user with optional server-side filters
    func fetchProjects(isCleared: Bool? = nil, isCompleted: Bool? = nil) async throws -> [FocusTask] {
        var query = supabase
            .from("tasks")
            .select()
            .eq("type", value: TaskType.project.rawValue)

        if let isCleared {
            query = query.eq("is_cleared", value: isCleared)
        }
        if let isCompleted {
            query = query.eq("is_completed", value: isCompleted)
        }

        let projects: [FocusTask] = try await query
            .order("sort_order", ascending: true)
            .order("created_date", ascending: false)
            .execute()
            .value

        return projects
    }

    /// Fetch tasks belonging to a specific project
    func fetchProjectTasks(projectId: UUID) async throws -> [FocusTask] {
        let tasks: [FocusTask] = try await supabase
            .from("tasks")
            .select()
            .eq("project_id", value: projectId.uuidString)
            .order("sort_order", ascending: true)
            .execute()
            .value

        return tasks
    }

    /// Create a new project
    func createProject(title: String, userId: UUID, categoryId: UUID? = nil, priority: Priority = .low) async throws -> FocusTask {
        let existingProjects = try await fetchProjects()
        let nextSortOrder = (existingProjects.map { $0.sortOrder }.max() ?? -1) + 1

        let project = FocusTask(
            userId: userId,
            title: title,
            type: .project,
            sortOrder: nextSortOrder,
            priority: priority,
            categoryId: categoryId
        )

        return try await createTask(project)
    }

    /// Create a task under a project
    func createProjectTask(title: String, projectId: UUID, userId: UUID, sortOrder: Int? = nil) async throws -> FocusTask {
        let order: Int
        if let sortOrder = sortOrder {
            order = sortOrder
        } else {
            let existingTasks = try await fetchProjectTasks(projectId: projectId)
            order = (existingTasks.map { $0.sortOrder }.max() ?? -1) + 1
        }

        let task = FocusTask(
            userId: userId,
            title: title,
            type: .task,
            sortOrder: order,
            projectId: projectId
        )

        return try await createTask(task)
    }

    /// Create a section header under a project
    func createProjectSection(title: String, projectId: UUID, userId: UUID, sortOrder: Int? = nil) async throws -> FocusTask {
        let order: Int
        if let sortOrder = sortOrder {
            order = sortOrder
        } else {
            let existingTasks = try await fetchProjectTasks(projectId: projectId)
            order = (existingTasks.map { $0.sortOrder }.max() ?? -1) + 1
        }

        let section = FocusTask(
            userId: userId,
            title: title,
            type: .task,
            sortOrder: order,
            isInLibrary: false,
            isSection: true,
            projectId: projectId
        )

        return try await createTask(section)
    }

    /// Create a top-level section header for projects or lists pages
    func createTopLevelSection(title: String, type: TaskType, userId: UUID) async throws -> FocusTask {
        let existingItems: [FocusTask]
        if type == .project {
            existingItems = try await fetchProjects()
        } else {
            existingItems = try await fetchTasks(ofType: type)
        }
        let nextOrder = (existingItems.map { $0.sortOrder }.max() ?? -1) + 1

        let section = FocusTask(
            userId: userId,
            title: title,
            type: type,
            sortOrder: nextOrder,
            isInLibrary: false,
            isSection: true
        )

        return try await createTask(section)
    }

    /// Nullify category_id for all tasks in a given category
    func nullifyCategoryId(categoryId: UUID) async throws {
        struct CategoryNullUpdate: Encodable {
            let categoryId: UUID?
            let modifiedDate: Date

            enum CodingKeys: String, CodingKey {
                case categoryId = "category_id"
                case modifiedDate = "modified_date"
            }
        }

        let update = CategoryNullUpdate(categoryId: nil, modifiedDate: Date())
        try await supabase
            .from("tasks")
            .update(update)
            .eq("category_id", value: categoryId.uuidString)
            .execute()
    }

    /// Reassign all tasks from one category to another
    func reassignCategory(from sourceCategoryId: UUID, to targetCategoryId: UUID) async throws {
        struct CategoryReassignUpdate: Encodable {
            let categoryId: UUID
            let modifiedDate: Date

            enum CodingKeys: String, CodingKey {
                case categoryId = "category_id"
                case modifiedDate = "modified_date"
            }
        }

        let update = CategoryReassignUpdate(categoryId: targetCategoryId, modifiedDate: Date())
        try await supabase
            .from("tasks")
            .update(update)
            .eq("category_id", value: sourceCategoryId.uuidString)
            .execute()
    }

    /// Restore subtasks to specific completion states
    func restoreSubtaskStates(parentId: UUID, completionStates: [Bool]) async throws {
        let subtasks = try await fetchSubtasks(parentId: parentId)

        for (index, subtask) in subtasks.enumerated() where index < completionStates.count {
            let shouldBeCompleted = completionStates[index]
            if subtask.isCompleted != shouldBeCompleted {
                if shouldBeCompleted {
                    try await completeTask(id: subtask.id)
                } else {
                    try await uncompleteTask(id: subtask.id)
                }
            }
        }
    }
}
