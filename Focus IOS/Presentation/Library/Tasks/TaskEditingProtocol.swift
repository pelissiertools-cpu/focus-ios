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
}
