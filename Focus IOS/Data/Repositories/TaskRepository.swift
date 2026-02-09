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

    /// Helper struct for sort order updates
    private struct SortOrderUpdate: Encodable {
        let sortOrder: Int
        let modifiedDate: Date

        enum CodingKeys: String, CodingKey {
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

    /// Fetch tasks by type (task, project, list)
    func fetchTasks(ofType type: TaskType) async throws -> [FocusTask] {
        let tasks: [FocusTask] = try await supabase
            .from("tasks")
            .select()
            .eq("type", value: type.rawValue)
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

    /// Uncomplete all subtasks of a parent task
    func uncompleteSubtasks(parentId: UUID) async throws {
        let update = TaskUpdate(
            isCompleted: false,
            completedDate: nil,
            modifiedDate: Date()
        )

        try await supabase
            .from("tasks")
            .update(update)
            .eq("parent_task_id", value: parentId.uuidString)
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

    /// Fetch all projects for the current user
    func fetchProjects() async throws -> [FocusTask] {
        let projects: [FocusTask] = try await supabase
            .from("tasks")
            .select()
            .eq("type", value: TaskType.project.rawValue)
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
    func createProject(title: String, userId: UUID, categoryId: UUID? = nil) async throws -> FocusTask {
        let existingProjects = try await fetchProjects()
        let nextSortOrder = (existingProjects.map { $0.sortOrder }.max() ?? -1) + 1

        let project = FocusTask(
            userId: userId,
            title: title,
            type: .project,
            sortOrder: nextSortOrder,
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
