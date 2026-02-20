//
//  TaskEditingProtocol.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-07.
//

import Foundation

/// Protocol for view models that support task editing operations.
/// Allows TaskDetailsDrawer to work with both TaskListViewModel and FocusTabViewModel.
@MainActor
protocol TaskEditingViewModel: ObservableObject {
    /// Subtask storage keyed by parent task ID
    var subtasksMap: [UUID: [FocusTask]] { get }

    /// Find a task by its ID
    func findTask(byId id: UUID) -> FocusTask?

    /// Get subtasks for a parent task
    func getSubtasks(for taskId: UUID) -> [FocusTask]

    /// Update a task's title
    func updateTask(_ task: FocusTask, newTitle: String) async

    /// Delete a parent task
    func deleteTask(_ task: FocusTask) async

    /// Delete a subtask
    func deleteSubtask(_ subtask: FocusTask, parentId: UUID) async

    /// Toggle subtask completion
    func toggleSubtaskCompletion(_ subtask: FocusTask, parentId: UUID) async

    /// Create a new subtask
    func createSubtask(title: String, parentId: UUID) async

    /// Refresh subtasks for a parent task from the database
    func refreshSubtasks(for parentId: UUID) async

    /// Move a task to a different category
    func moveTaskToCategory(_ task: FocusTask, categoryId: UUID?) async

    /// Create a new category and move the task to it
    func createCategoryAndMove(name: String, task: FocusTask) async
}

// Default empty implementations for category operations.
// ViewModels that don't support categories (e.g. FocusTabViewModel) get these for free.
extension TaskEditingViewModel {
    func refreshSubtasks(for parentId: UUID) async {}
    func moveTaskToCategory(_ task: FocusTask, categoryId: UUID?) async {}
    func createCategoryAndMove(name: String, task: FocusTask) async {}

    /// Get uncompleted subtasks sorted by sortOrder
    func getUncompletedSubtasks(for taskId: UUID) -> [FocusTask] {
        (subtasksMap[taskId] ?? []).filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Get completed subtasks sorted by sortOrder
    func getCompletedSubtasks(for taskId: UUID) -> [FocusTask] {
        (subtasksMap[taskId] ?? []).filter { $0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }
}
