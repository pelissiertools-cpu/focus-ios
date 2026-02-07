//
//  TaskListViewModel.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation
import Combine
import Auth

@MainActor
class TaskListViewModel: ObservableObject {
    @Published var tasks: [FocusTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingAddTask = false
    @Published var selectedTaskForDetails: FocusTask?

    // Subtask state management
    @Published var subtasksMap: [UUID: [FocusTask]] = [:]
    @Published var expandedTasks: Set<UUID> = []
    @Published var isLoadingSubtasks: Set<UUID> = []

    private let repository: TaskRepository
    private let authService: AuthService

    init(repository: TaskRepository = TaskRepository(), authService: AuthService) {
        self.repository = repository
        self.authService = authService
    }

    // MARK: - Subtask Expansion

    /// Toggle expansion state for a task
    func toggleExpanded(_ taskId: UUID) async {
        if expandedTasks.contains(taskId) {
            expandedTasks.remove(taskId)
        } else {
            expandedTasks.insert(taskId)
            if subtasksMap[taskId] == nil {
                await fetchSubtasks(for: taskId)
            }
        }
    }

    /// Check if task is expanded
    func isExpanded(_ taskId: UUID) -> Bool {
        expandedTasks.contains(taskId)
    }

    /// Get subtasks for a task (sorted: uncompleted first)
    func getSubtasks(for taskId: UUID) -> [FocusTask] {
        let subtasks = subtasksMap[taskId] ?? []
        return subtasks.sorted { !$0.isCompleted && $1.isCompleted }
    }

    /// Check if task has subtasks loaded
    func hasSubtasks(_ taskId: UUID) -> Bool {
        if let subtasks = subtasksMap[taskId] {
            return !subtasks.isEmpty
        }
        return false
    }

    /// Fetch subtasks for a specific parent task
    func fetchSubtasks(for parentId: UUID) async {
        guard !isLoadingSubtasks.contains(parentId) else { return }
        isLoadingSubtasks.insert(parentId)

        do {
            let subtasks = try await repository.fetchSubtasks(parentId: parentId)
            subtasksMap[parentId] = subtasks
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingSubtasks.remove(parentId)
    }

    /// Fetch all top-level tasks (no parent)
    func fetchTasks() async {
        isLoading = true
        errorMessage = nil

        do {
            let allTasks = try await repository.fetchTasks(ofType: .task)
            // Filter to only top-level tasks (no parent)
            self.tasks = allTasks.filter { $0.parentTaskId == nil }
            isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    /// Create a new task
    func createTask(title: String) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }

        errorMessage = nil

        do {
            let newTask = FocusTask(
                userId: userId,
                title: title,
                type: .task,
                isCompleted: false
            )

            let createdTask = try await repository.createTask(newTask)
            tasks.insert(createdTask, at: 0)
            showingAddTask = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle parent task completion with cascade to subtasks
    func toggleCompletion(_ task: FocusTask) async {
        do {
            if task.isCompleted {
                // Uncompleting parent - restore previous subtask states
                try await repository.uncompleteTask(id: task.id)

                // Restore subtasks to previous states if available
                if let previousStates = task.previousCompletionState {
                    try await repository.restoreSubtaskStates(parentId: task.id, completionStates: previousStates)
                    // Refresh subtasks from DB
                    await fetchSubtasks(for: task.id)
                }
            } else {
                // Completing parent - save subtask states and complete all
                let subtasks = subtasksMap[task.id] ?? []
                let previousStates = subtasks.map { $0.isCompleted }

                // Save previous states to parent task
                if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[index].previousCompletionState = previousStates
                    var updatedTask = tasks[index]
                    updatedTask.previousCompletionState = previousStates
                    try await repository.updateTask(updatedTask)
                }

                // Complete parent and all subtasks
                try await repository.completeTask(id: task.id)
                if !subtasks.isEmpty {
                    try await repository.completeSubtasks(parentId: task.id)
                    // Update local subtask states
                    if var localSubtasks = subtasksMap[task.id] {
                        for i in localSubtasks.indices {
                            localSubtasks[i].isCompleted = true
                            localSubtasks[i].completedDate = Date()
                        }
                        subtasksMap[task.id] = localSubtasks
                    }
                }
            }

            // Update local parent task state
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].isCompleted.toggle()
                if tasks[index].isCompleted {
                    tasks[index].completedDate = Date()
                } else {
                    tasks[index].completedDate = nil
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle subtask completion - auto-completes parent when all done
    func toggleSubtaskCompletion(_ subtask: FocusTask, parentId: UUID) async {
        do {
            if subtask.isCompleted {
                try await repository.uncompleteTask(id: subtask.id)
            } else {
                try await repository.completeTask(id: subtask.id)
            }

            // Update local subtask state
            if var subtasks = subtasksMap[parentId],
               let index = subtasks.firstIndex(where: { $0.id == subtask.id }) {
                subtasks[index].isCompleted.toggle()
                if subtasks[index].isCompleted {
                    subtasks[index].completedDate = Date()
                } else {
                    subtasks[index].completedDate = nil
                }
                subtasksMap[parentId] = subtasks

                // Check if ALL subtasks are now complete - auto-complete parent
                let allComplete = subtasks.allSatisfy { $0.isCompleted }
                if allComplete && !subtasks.isEmpty {
                    if let parentIndex = tasks.firstIndex(where: { $0.id == parentId }),
                       !tasks[parentIndex].isCompleted {
                        // Save current states before auto-completing
                        tasks[parentIndex].previousCompletionState = subtasks.map { $0.isCompleted }
                        try await repository.completeTask(id: parentId)
                        tasks[parentIndex].isCompleted = true
                        tasks[parentIndex].completedDate = Date()
                    }
                } else if !allComplete {
                    // If not all complete and parent is completed, uncomplete parent
                    // WITHOUT restoring previous states - subtasks stay as-is
                    if let parentIndex = tasks.firstIndex(where: { $0.id == parentId }),
                       tasks[parentIndex].isCompleted {
                        try await repository.uncompleteTask(id: parentId)
                        tasks[parentIndex].isCompleted = false
                        tasks[parentIndex].completedDate = nil
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete a task
    func deleteTask(_ task: FocusTask) async {
        do {
            try await repository.deleteTask(id: task.id)
            tasks.removeAll { $0.id == task.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Update task title
    func updateTask(_ task: FocusTask, newTitle: String) async {
        guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Task title cannot be empty"
            return
        }

        do {
            var updatedTask = task
            updatedTask.title = newTitle
            updatedTask.modifiedDate = Date()

            try await repository.updateTask(updatedTask)

            // Update local state - check both tasks and subtasks
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].title = newTitle
                tasks[index].modifiedDate = Date()
            }

            // Also check subtasks if this is a subtask
            if let parentId = task.parentTaskId,
               var subtasks = subtasksMap[parentId],
               let index = subtasks.firstIndex(where: { $0.id == task.id }) {
                subtasks[index].title = newTitle
                subtasks[index].modifiedDate = Date()
                subtasksMap[parentId] = subtasks
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Subtask CRUD

    /// Create a new subtask
    func createSubtask(title: String, parentId: UUID) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }

        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }

        do {
            let newSubtask = try await repository.createSubtask(
                title: title,
                parentTaskId: parentId,
                userId: userId
            )

            // Update local state
            if var subtasks = subtasksMap[parentId] {
                subtasks.append(newSubtask)
                subtasksMap[parentId] = subtasks
            } else {
                subtasksMap[parentId] = [newSubtask]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete a subtask
    func deleteSubtask(_ subtask: FocusTask, parentId: UUID) async {
        do {
            try await repository.deleteTask(id: subtask.id)

            // Update local state
            if var subtasks = subtasksMap[parentId] {
                subtasks.removeAll { $0.id == subtask.id }
                subtasksMap[parentId] = subtasks
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
