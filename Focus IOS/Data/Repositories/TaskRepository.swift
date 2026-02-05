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

    /// Fetch all tasks for the current user
    func fetchTasks() async throws -> [FocusTask] {
        let tasks: [FocusTask] = try await supabase
            .from("tasks")
            .select()
            .order("created_date", ascending: false)
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
}
