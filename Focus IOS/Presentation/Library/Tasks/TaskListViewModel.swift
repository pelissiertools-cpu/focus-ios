//
//  TaskListViewModel.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import Foundation
import Combine
import SwiftUI
import Auth

@MainActor
class TaskListViewModel: ObservableObject, TaskEditingViewModel {
    @Published var tasks: [FocusTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingAddTask = false
    @Published var selectedTaskForDetails: FocusTask?

    // Subtask state management
    @Published var subtasksMap: [UUID: [FocusTask]] = [:]
    @Published var expandedTasks: Set<UUID> = []
    @Published var isLoadingSubtasks: Set<UUID> = []

    // Done subsection state
    @Published var isDoneSubsectionCollapsed: Bool = true  // Closed by default

    private let repository: TaskRepository
    private let commitmentRepository: CommitmentRepository
    private let authService: AuthService
    private var cancellables = Set<AnyCancellable>()

    init(repository: TaskRepository = TaskRepository(),
         commitmentRepository: CommitmentRepository = CommitmentRepository(),
         authService: AuthService) {
        self.repository = repository
        self.commitmentRepository = commitmentRepository
        self.authService = authService
        setupNotificationObserver()
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.publisher(for: .taskCompletionChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleTaskCompletionNotification(notification)
            }
            .store(in: &cancellables)
    }

    private func handleTaskCompletionNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let taskId = userInfo[TaskNotificationKeys.taskId] as? UUID,
              let isCompleted = userInfo[TaskNotificationKeys.isCompleted] as? Bool,
              let source = userInfo[TaskNotificationKeys.source] as? String,
              source == TaskNotificationSource.focus.rawValue else {
            return
        }

        let completedDate = userInfo[TaskNotificationKeys.completedDate] as? Date

        // Update tasks array if this task exists
        if let index = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[index].isCompleted = isCompleted
            tasks[index].completedDate = completedDate
        }

        // Update subtasksMap if this task is a subtask
        for (parentId, var subtasks) in subtasksMap {
            if let index = subtasks.firstIndex(where: { $0.id == taskId }) {
                subtasks[index].isCompleted = isCompleted
                subtasks[index].completedDate = completedDate
                subtasksMap[parentId] = subtasks
                break
            }
        }
    }

    private func postTaskCompletionNotification(taskId: UUID, isCompleted: Bool, completedDate: Date?) {
        NotificationCenter.default.post(
            name: .taskCompletionChanged,
            object: nil,
            userInfo: [
                TaskNotificationKeys.taskId: taskId,
                TaskNotificationKeys.isCompleted: isCompleted,
                TaskNotificationKeys.completedDate: completedDate as Any,
                TaskNotificationKeys.source: TaskNotificationSource.library.rawValue
            ]
        )
    }

    // MARK: - Computed Properties

    /// Uncompleted top-level tasks sorted by sortOrder
    var uncompletedTasks: [FocusTask] {
        tasks.filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Completed top-level tasks
    var completedTasks: [FocusTask] {
        tasks.filter { $0.isCompleted }
    }

    // MARK: - Subtask Expansion

    /// Toggle expansion state for a task
    func toggleExpanded(_ taskId: UUID) async {
        if expandedTasks.contains(taskId) {
            expandedTasks.remove(taskId)
        } else {
            expandedTasks.insert(taskId)
            if subtasksMap[taskId] == nil {
                subtasksMap[taskId] = []
                await fetchSubtasks(for: taskId)
            }
        }
    }

    /// Check if task is expanded
    func isExpanded(_ taskId: UUID) -> Bool {
        expandedTasks.contains(taskId)
    }

    /// Toggle Done subsection collapsed state
    func toggleDoneSubsectionCollapsed() {
        isDoneSubsectionCollapsed.toggle()
    }

    /// Get subtasks for a task (uncompleted first, each group sorted by sortOrder)
    func getSubtasks(for taskId: UUID) -> [FocusTask] {
        let subtasks = subtasksMap[taskId] ?? []
        let uncompleted = subtasks.filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
        let completed = subtasks.filter { $0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
        return uncompleted + completed
    }

    /// Get uncompleted subtasks sorted by sortOrder
    func getUncompletedSubtasks(for taskId: UUID) -> [FocusTask] {
        (subtasksMap[taskId] ?? []).filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Get completed subtasks sorted by sortOrder
    func getCompletedSubtasks(for taskId: UUID) -> [FocusTask] {
        (subtasksMap[taskId] ?? []).filter { $0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Find a task by ID (searches both tasks and subtasks)
    func findTask(byId id: UUID) -> FocusTask? {
        if let task = tasks.first(where: { $0.id == id }) {
            return task
        }
        for subtasks in subtasksMap.values {
            if let subtask = subtasks.first(where: { $0.id == id }) {
                return subtask
            }
        }
        return nil
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

            // Pre-populate subtasksMap from already-fetched data
            var newSubtasksMap: [UUID: [FocusTask]] = [:]
            for task in allTasks where task.parentTaskId != nil {
                newSubtasksMap[task.parentTaskId!, default: []].append(task)
            }
            for task in self.tasks {
                if newSubtasksMap[task.id] == nil {
                    newSubtasksMap[task.id] = []
                }
            }
            self.subtasksMap = newSubtasksMap

            isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    /// Create a new task (inserted at the top with sortOrder 0)
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
                isCompleted: false,
                sortOrder: 0
            )

            let createdTask = try await repository.createTask(newTask)
            tasks.insert(createdTask, at: 0)

            // Reassign sort orders so the new task is at 0 and others shift up
            let uncompleted = tasks.filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
            var updates: [(id: UUID, sortOrder: Int)] = []
            for (index, task) in uncompleted.enumerated() {
                if let tasksIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[tasksIndex].sortOrder = index
                }
                updates.append((id: task.id, sortOrder: index))
            }
            await persistSortOrders(updates)

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
                // Notify other views
                postTaskCompletionNotification(
                    taskId: task.id,
                    isCompleted: tasks[index].isCompleted,
                    completedDate: tasks[index].completedDate
                )
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

                // Notify other views about subtask change
                postTaskCompletionNotification(
                    taskId: subtask.id,
                    isCompleted: subtasks[index].isCompleted,
                    completedDate: subtasks[index].completedDate
                )

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
                        // Notify other views about parent auto-complete
                        postTaskCompletionNotification(
                            taskId: parentId,
                            isCompleted: true,
                            completedDate: tasks[parentIndex].completedDate
                        )
                    }
                } else if !allComplete {
                    // If not all complete and parent is completed, uncomplete parent
                    // WITHOUT restoring previous states - subtasks stay as-is
                    if let parentIndex = tasks.firstIndex(where: { $0.id == parentId }),
                       tasks[parentIndex].isCompleted {
                        try await repository.uncompleteTask(id: parentId)
                        tasks[parentIndex].isCompleted = false
                        tasks[parentIndex].completedDate = nil
                        // Notify other views about parent uncomplete
                        postTaskCompletionNotification(
                            taskId: parentId,
                            isCompleted: false,
                            completedDate: nil
                        )
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete a task (hard delete from Library - also cleans up all commitments)
    func deleteTask(_ task: FocusTask) async {
        do {
            // Clean up all commitments for this task first
            try await commitmentRepository.deleteCommitments(forTask: task.id)

            // Delete the task
            try await repository.deleteTask(id: task.id)
            tasks.removeAll { $0.id == task.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clear all completed tasks from the library
    func clearCompletedTasks() async {
        let completedTaskIds = tasks.filter { $0.isCompleted }.map { $0.id }

        do {
            // Delete commitments and tasks for each completed task
            for taskId in completedTaskIds {
                try await commitmentRepository.deleteCommitments(forTask: taskId)
                try await repository.deleteTask(id: taskId)
            }

            // Remove from local array
            tasks.removeAll { $0.isCompleted }
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

    // MARK: - Reordering

    /// Reorder a task by placing the dragged task at the target task's position
    func reorderTask(droppedId: UUID, targetId: UUID) {
        var uncompleted = tasks.filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }

        guard let fromIndex = uncompleted.firstIndex(where: { $0.id == droppedId }),
              let toIndex = uncompleted.firstIndex(where: { $0.id == targetId }),
              fromIndex != toIndex else { return }

        let moved = uncompleted.remove(at: fromIndex)
        uncompleted.insert(moved, at: toIndex)

        // Reassign sort orders in the main tasks array
        for (index, task) in uncompleted.enumerated() {
            if let tasksIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[tasksIndex].sortOrder = index
            }
        }

        // Persist in background
        let updates = uncompleted.enumerated().map { (index, task) in
            (id: task.id, sortOrder: index)
        }
        Task {
            await persistSortOrders(updates)
        }
    }

    /// Reorder a subtask by placing the dragged subtask at the target subtask's position
    func reorderSubtask(droppedId: UUID, targetId: UUID, parentId: UUID) {
        guard var allSubtasks = subtasksMap[parentId] else { return }
        var uncompleted = allSubtasks.filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }

        guard let fromIndex = uncompleted.firstIndex(where: { $0.id == droppedId }),
              let toIndex = uncompleted.firstIndex(where: { $0.id == targetId }),
              fromIndex != toIndex else { return }

        let moved = uncompleted.remove(at: fromIndex)
        uncompleted.insert(moved, at: toIndex)

        // Reassign sort orders
        for (index, subtask) in uncompleted.enumerated() {
            if let mapIndex = allSubtasks.firstIndex(where: { $0.id == subtask.id }) {
                allSubtasks[mapIndex].sortOrder = index
            }
        }
        subtasksMap[parentId] = allSubtasks

        // Persist in background
        let updates = uncompleted.enumerated().map { (index, subtask) in
            (id: subtask.id, sortOrder: index)
        }
        Task {
            await persistSortOrders(updates)
        }
    }

    /// Persist sort order changes to Supabase
    private func persistSortOrders(_ updates: [(id: UUID, sortOrder: Int)]) async {
        do {
            try await repository.updateSortOrders(updates)
        } catch {
            errorMessage = "Failed to save order: \(error.localizedDescription)"
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
