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

// MARK: - Flat Display Item

enum FlatDisplayItem: Identifiable {
    case task(FocusTask)
    case addSubtaskRow(parentId: UUID)
    case priorityHeader(Priority)

    var id: String {
        switch self {
        case .task(let task): return task.id.uuidString
        case .addSubtaskRow(let parentId): return "add-\(parentId.uuidString)"
        case .priorityHeader(let priority): return "priority-\(priority.rawValue)"
        }
    }
}

@MainActor
class TaskListViewModel: ObservableObject, TaskEditingViewModel, LogFilterable {
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

    // Tasks section collapse state
    @Published var isTasksSectionCollapsed: Bool = false

    // Priority section collapse states
    @Published var collapsedPriorities: Set<Priority> = []

    // Search
    @Published var searchText: String = ""

    // Category filter
    @Published var categories: [Category] = []
    @Published var selectedCategoryId: UUID? = nil

    // Commitment filter
    @Published var commitmentFilter: CommitmentFilter? = nil
    @Published var committedTaskIds: Set<UUID> = []

    // Edit mode
    @Published var isEditMode: Bool = false
    @Published var selectedTaskIds: Set<UUID> = []

    // Batch operation triggers
    @Published var showBatchDeleteConfirmation: Bool = false
    @Published var showBatchMovePicker: Bool = false
    @Published var showBatchCommitSheet: Bool = false

    private let repository: TaskRepository
    let commitmentRepository: CommitmentRepository
    private let categoryRepository: CategoryRepository
    private let authService: AuthService
    private var cancellables = Set<AnyCancellable>()

    init(repository: TaskRepository = TaskRepository(),
         commitmentRepository: CommitmentRepository = CommitmentRepository(),
         categoryRepository: CategoryRepository = CategoryRepository(),
         authService: AuthService) {
        self.repository = repository
        self.commitmentRepository = commitmentRepository
        self.categoryRepository = categoryRepository
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

        // Refresh subtasks from DB if parent's subtasks were changed
        if let subtasksChanged = userInfo[TaskNotificationKeys.subtasksChanged] as? Bool,
           subtasksChanged {
            _Concurrency.Task { @MainActor in
                if let refreshed = try? await self.repository.fetchSubtasks(parentId: taskId),
                   !refreshed.isEmpty {
                    self.subtasksMap[taskId] = refreshed
                }
            }
        }
    }

    private func postTaskCompletionNotification(taskId: UUID, isCompleted: Bool, completedDate: Date?, subtasksChanged: Bool = false) {
        NotificationCenter.default.post(
            name: .taskCompletionChanged,
            object: nil,
            userInfo: [
                TaskNotificationKeys.taskId: taskId,
                TaskNotificationKeys.isCompleted: isCompleted,
                TaskNotificationKeys.completedDate: completedDate as Any,
                TaskNotificationKeys.source: TaskNotificationSource.log.rawValue,
                TaskNotificationKeys.subtasksChanged: subtasksChanged
            ]
        )
    }

    // MARK: - LogFilterable Conformance

    var showingAddItem: Bool {
        get { showingAddTask }
        set { showingAddTask = newValue }
    }

    var selectedItemIds: Set<UUID> {
        get { selectedTaskIds }
        set { selectedTaskIds = newValue }
    }

    var selectedItems: [FocusTask] {
        tasks.filter { selectedTaskIds.contains($0.id) }
    }

    // MARK: - Computed Properties

    /// Uncompleted top-level tasks sorted by sortOrder, filtered by category, commitment status, and search text
    var uncompletedTasks: [FocusTask] {
        var filtered = tasks.filter { !$0.isCompleted }
        if let categoryId = selectedCategoryId {
            filtered = filtered.filter { $0.categoryId == categoryId }
        }
        if let commitmentFilter = commitmentFilter {
            switch commitmentFilter {
            case .committed:
                filtered = filtered.filter { committedTaskIds.contains($0.id) }
            case .uncommitted:
                filtered = filtered.filter { !committedTaskIds.contains($0.id) }
            }
        }
        let searched = searchText.isEmpty ? filtered : filtered.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
        return searched.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Completed top-level tasks, filtered by category, commitment status, and search text
    var completedTasks: [FocusTask] {
        var filtered = tasks.filter { $0.isCompleted }
        if let categoryId = selectedCategoryId {
            filtered = filtered.filter { $0.categoryId == categoryId }
        }
        if let commitmentFilter = commitmentFilter {
            switch commitmentFilter {
            case .committed:
                filtered = filtered.filter { committedTaskIds.contains($0.id) }
            case .uncommitted:
                filtered = filtered.filter { !committedTaskIds.contains($0.id) }
            }
        }
        return searchText.isEmpty ? filtered : filtered.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Tasks grouped by priority for count display
    func uncompletedTasks(for priority: Priority) -> [FocusTask] {
        uncompletedTasks.filter { $0.priority == priority }
    }

    /// Flat display array: priority headers → parents → expanded subtasks + add rows.
    /// Fed to a single ForEach so every item is a top-level list citizen.
    var flattenedDisplayItems: [FlatDisplayItem] {
        var result: [FlatDisplayItem] = []
        for priority in Priority.allCases {
            let tasksForPriority = uncompletedTasks.filter { $0.priority == priority }
            guard !tasksForPriority.isEmpty else { continue }

            result.append(.priorityHeader(priority))

            if !collapsedPriorities.contains(priority) {
                for task in tasksForPriority {
                    result.append(.task(task))
                    if expandedTasks.contains(task.id) {
                        for subtask in getUncompletedSubtasks(for: task.id) {
                            result.append(.task(subtask))
                        }
                        for subtask in getCompletedSubtasks(for: task.id) {
                            result.append(.task(subtask))
                        }
                        result.append(.addSubtaskRow(parentId: task.id))
                    }
                }
            }
        }
        return result
    }

    /// Toggle priority section collapse state
    func togglePriorityCollapsed(_ priority: Priority) {
        if collapsedPriorities.contains(priority) {
            collapsedPriorities.remove(priority)
        } else {
            collapsedPriorities.insert(priority)
        }
    }

    /// Check if priority section is collapsed
    func isPriorityCollapsed(_ priority: Priority) -> Bool {
        collapsedPriorities.contains(priority)
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

    /// Refresh subtasks for a parent task (protocol conformance)
    func refreshSubtasks(for parentId: UUID) async {
        await fetchSubtasks(for: parentId)
    }

    /// Fetch subtasks for a specific parent task
    func fetchSubtasks(for parentId: UUID) async {
        guard !isLoadingSubtasks.contains(parentId) else { return }
        isLoadingSubtasks.insert(parentId)

        do {
            let subtasks = try await repository.fetchSubtasks(parentId: parentId)
            subtasksMap[parentId] = subtasks
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }

        isLoadingSubtasks.remove(parentId)
    }

    /// Fetch all top-level tasks (no parent)
    func fetchTasks() async {
        if tasks.isEmpty { isLoading = true }
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
            if !Task.isCancelled { self.errorMessage = error.localizedDescription }
            self.isLoading = false
        }
    }

    /// Create a new task (inserted at the top with sortOrder 0)
    @discardableResult
    func createTask(title: String, categoryId: UUID? = nil) async -> UUID? {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return nil
        }

        errorMessage = nil

        do {
            let newTask = FocusTask(
                userId: userId,
                title: title,
                type: .task,
                isCompleted: false,
                sortOrder: 0,
                categoryId: categoryId
            )

            let createdTask = try await repository.createTask(newTask)
            tasks.insert(createdTask, at: 0)
            subtasksMap[createdTask.id] = []

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

            return createdTask.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Toggle parent task completion with cascade to subtasks
    func toggleCompletion(_ task: FocusTask) async {
        do {
            var didRestoreSubtasks = false

            if task.isCompleted {
                // Uncompleting parent - restore previous subtask states
                try await repository.uncompleteTask(id: task.id)

                // Restore subtasks to previous states if available
                let currentTask = tasks.first(where: { $0.id == task.id })
                if let previousStates = currentTask?.previousCompletionState {
                    try await repository.restoreSubtaskStates(parentId: task.id, completionStates: previousStates)
                    // Refresh subtasks from DB
                    await fetchSubtasks(for: task.id)
                    didRestoreSubtasks = true
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
                    didRestoreSubtasks = true
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
                    completedDate: tasks[index].completedDate,
                    subtasksChanged: didRestoreSubtasks
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle subtask completion - auto-completes parent when all done
    func toggleSubtaskCompletion(_ subtask: FocusTask, parentId: UUID) async {
        // Capture BEFORE toggle for potential parent auto-complete restore
        let preToggleStates = (subtasksMap[parentId] ?? []).map { $0.isCompleted }
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
                        // Save pre-toggle states for restore on parent uncomplete
                        tasks[parentIndex].previousCompletionState = preToggleStates
                        let parentToSave = tasks[parentIndex]
                        try await repository.updateTask(parentToSave)
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

    /// Delete a task (hard delete from Log - also cleans up all commitments)
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

    /// Clear all completed tasks from the log
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

    /// Update task priority
    func updateTaskPriority(_ task: FocusTask, priority: Priority) async {
        do {
            var updatedTask = task
            updatedTask.priority = priority
            updatedTask.modifiedDate = Date()

            try await repository.updateTask(updatedTask)

            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].priority = priority
                tasks[index].modifiedDate = Date()
            }
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

    /// Persist sort order changes to Supabase
    private func persistSortOrders(_ updates: [(id: UUID, sortOrder: Int)]) async {
        do {
            try await repository.updateSortOrders(updates)
        } catch {
            errorMessage = "Failed to save order: \(error.localizedDescription)"
        }
    }

    // MARK: - Flat List Move Handler

    /// Determine which priority section contains the given destination index
    private func resolveDestinationPriority(flat: [FlatDisplayItem], destination: Int) -> Priority {
        let lookupIndex = max(0, min(destination - 1, flat.count - 1))
        for i in stride(from: lookupIndex, through: 0, by: -1) {
            if case .priorityHeader(let priority) = flat[i] {
                return priority
            }
        }
        return .medium // fallback
    }

    /// Handle .onMove from the flat ForEach.
    /// Uses Array.move(fromOffsets:toOffset:) to match SwiftUI's visual move exactly,
    /// preventing the snap/overlap glitch that occurs with droppedId/targetId mapping.
    func handleFlatMove(from source: IndexSet, to destination: Int) {
        let flat = flattenedDisplayItems
        guard let fromIdx = source.first else { return }

        // Only task items can be moved
        guard case .task(let movedTask) = flat[fromIdx],
              !movedTask.isCompleted else { return }

        if movedTask.parentTaskId == nil {
            // --- Parent task moved ---
            let sourcePriority = movedTask.priority
            let destinationPriority = resolveDestinationPriority(flat: flat, destination: destination)

            if destinationPriority == sourcePriority {
                // Same-section reorder
                let parentIndices = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, task: FocusTask)? in
                    if case .task(let t) = item, t.parentTaskId == nil, !t.isCompleted, t.priority == sourcePriority { return (i, t) }
                    return nil
                }

                guard let parentFrom = parentIndices.firstIndex(where: { $0.task.id == movedTask.id }) else { return }

                var parentTo = parentIndices.count
                for (pi, entry) in parentIndices.enumerated() {
                    if destination <= entry.flatIdx {
                        parentTo = pi
                        break
                    }
                }
                if parentTo > parentFrom { parentTo = min(parentTo, parentIndices.count) }

                guard parentFrom != parentTo && parentFrom + 1 != parentTo else { return }

                var samePriorityTasks = uncompletedTasks.filter { $0.priority == sourcePriority }
                samePriorityTasks.move(fromOffsets: IndexSet(integer: parentFrom), toOffset: parentTo)

                var updates: [(id: UUID, sortOrder: Int)] = []
                for (index, task) in samePriorityTasks.enumerated() {
                    if let taskIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                        tasks[taskIndex].sortOrder = index
                    }
                    updates.append((id: task.id, sortOrder: index))
                }
                _Concurrency.Task { await persistSortOrders(updates) }
            } else {
                // Cross-section move: change priority and insert into destination section

                // Find insertion position within destination priority section
                let destParents = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, task: FocusTask)? in
                    if case .task(let t) = item, t.parentTaskId == nil, !t.isCompleted, t.priority == destinationPriority { return (i, t) }
                    return nil
                }

                var insertIndex = destParents.count // default: append at end
                for (pi, entry) in destParents.enumerated() {
                    if destination <= entry.flatIdx {
                        insertIndex = pi
                        break
                    }
                }

                // Update priority locally
                if let taskIndex = tasks.firstIndex(where: { $0.id == movedTask.id }) {
                    tasks[taskIndex].priority = destinationPriority
                    tasks[taskIndex].modifiedDate = Date()
                }

                // Build destination section task list (excluding moved task, then insert it)
                var destTasks = uncompletedTasks
                    .filter { $0.priority == destinationPriority && $0.id != movedTask.id }
                let clampedIndex = min(insertIndex, destTasks.count)
                if let updatedTask = tasks.first(where: { $0.id == movedTask.id }) {
                    destTasks.insert(updatedTask, at: clampedIndex)
                }

                // Reassign sort orders in destination section
                var updates: [(id: UUID, sortOrder: Int)] = []
                for (index, task) in destTasks.enumerated() {
                    if let taskIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                        tasks[taskIndex].sortOrder = index
                    }
                    updates.append((id: task.id, sortOrder: index))
                }

                // Reassign sort orders in source section (task was removed)
                let sourceTasks = uncompletedTasks
                    .filter { $0.priority == sourcePriority }
                for (index, task) in sourceTasks.enumerated() {
                    if let taskIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                        tasks[taskIndex].sortOrder = index
                    }
                    updates.append((id: task.id, sortOrder: index))
                }

                // Persist priority change + sort orders
                _Concurrency.Task {
                    // Save the moved task with new priority
                    if let updatedTask = self.tasks.first(where: { $0.id == movedTask.id }) {
                        do {
                            try await self.repository.updateTask(updatedTask)
                        } catch {
                            self.errorMessage = "Failed to update priority: \(error.localizedDescription)"
                        }
                    }
                    // Save sort orders for all other affected tasks
                    let otherUpdates = updates.filter { $0.id != movedTask.id }
                    await self.persistSortOrders(otherUpdates)
                }
            }

        } else {
            // --- Subtask moved ---
            let parentId = movedTask.parentTaskId!

            // Find parent's section bounds to validate the move
            guard let parentFlatIdx = flat.firstIndex(where: {
                if case .task(let t) = $0 { return t.id == parentId }
                return false
            }) else { return }

            let sectionEnd = flat[(parentFlatIdx + 1)...].firstIndex(where: {
                if case .task(let t) = $0 { return t.parentTaskId == nil }
                return false
            }) ?? flat.count

            // Reject cross-parent moves
            guard destination > parentFlatIdx && destination <= sectionEnd else { return }

            // Map flat indices to sibling-only indices
            let siblingIndices = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, task: FocusTask)? in
                if case .task(let t) = item, t.parentTaskId == parentId, !t.isCompleted { return (i, t) }
                return nil
            }

            guard let siblingFrom = siblingIndices.firstIndex(where: { $0.task.id == movedTask.id }) else { return }

            // Map flat destination to sibling-only destination
            var siblingTo = siblingIndices.count
            for (si, entry) in siblingIndices.enumerated() {
                if destination <= entry.flatIdx {
                    siblingTo = si
                    break
                }
            }
            if siblingTo > siblingFrom { siblingTo = min(siblingTo, siblingIndices.count) }

            guard siblingFrom != siblingTo && siblingFrom + 1 != siblingTo else { return }

            // Apply move on uncompleted subtasks
            guard var allChildren = subtasksMap[parentId] else { return }
            var uncompleted = allChildren.filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }

            uncompleted.move(fromOffsets: IndexSet(integer: siblingFrom), toOffset: siblingTo)

            // Write sort orders back into full children array
            var updates: [(id: UUID, sortOrder: Int)] = []
            for (index, child) in uncompleted.enumerated() {
                if let mapIndex = allChildren.firstIndex(where: { $0.id == child.id }) {
                    allChildren[mapIndex].sortOrder = index
                }
                updates.append((id: child.id, sortOrder: index))
            }
            subtasksMap[parentId] = allChildren
            _Concurrency.Task { await persistSortOrders(updates) }
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

    // MARK: - Atomic Task Creation (with subtasks + commitments)

    /// Create a task with optional subtasks, category, and commitments atomically
    @discardableResult
    func createTaskWithCommitments(
        title: String,
        categoryId: UUID?,
        subtaskTitles: [String],
        commitAfterCreate: Bool,
        selectedTimeframe: Timeframe,
        selectedSection: Section,
        selectedDates: Set<Date>,
        hasScheduledTime: Bool,
        scheduledTime: Date?
    ) async -> UUID? {
        // 1. Create the task
        guard let parentId = await createTask(title: title, categoryId: categoryId) else {
            return nil
        }

        // 2. Create subtasks
        for subtaskTitle in subtaskTitles {
            await createSubtask(title: subtaskTitle, parentId: parentId)
        }

        // 3. Create commitments if enabled
        if commitAfterCreate && !selectedDates.isEmpty {
            guard let userId = authService.currentUser?.id else { return parentId }
            for date in selectedDates {
                let commitment = Commitment(
                    userId: userId,
                    taskId: parentId,
                    timeframe: selectedTimeframe,
                    section: selectedSection,
                    commitmentDate: date,
                    sortOrder: 0,
                    scheduledTime: hasScheduledTime ? scheduledTime : nil,
                    durationMinutes: hasScheduledTime ? 30 : nil
                )
                _ = try? await commitmentRepository.createCommitment(commitment)
            }
            await fetchCommittedTaskIds()
        }

        return parentId
    }

    // MARK: - Categories

    func fetchCategories() async {
        do {
            self.categories = try await categoryRepository.fetchCategories()
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    func createCategory(name: String) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        do {
            let newCategory = Category(
                userId: userId,
                name: trimmed,
                sortOrder: categories.count
            )
            let created = try await categoryRepository.createCategory(newCategory)
            categories.append(created)
            selectedCategoryId = created.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Commitment Filter

    func moveTaskToCategory(_ task: FocusTask, categoryId: UUID?) async {
        do {
            var updated = task
            updated.categoryId = categoryId
            updated.modifiedDate = Date()
            try await repository.updateTask(updated)

            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].categoryId = categoryId
                tasks[index].modifiedDate = Date()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Edit Mode

    var selectedCount: Int { selectedTaskIds.count }

    var allUncompletedSelected: Bool {
        let uncompletedIds = Set(uncompletedTasks.map { $0.id })
        return !uncompletedIds.isEmpty && uncompletedIds.isSubset(of: selectedTaskIds)
    }

    var selectedTasks: [FocusTask] {
        tasks.filter { selectedTaskIds.contains($0.id) }
    }

    func enterEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditMode = true
            selectedTaskIds = []
            expandedTasks.removeAll()
        }
    }

    func exitEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditMode = false
            selectedTaskIds = []
        }
    }

    func toggleTaskSelection(_ taskId: UUID) {
        if selectedTaskIds.contains(taskId) {
            selectedTaskIds.remove(taskId)
        } else {
            selectedTaskIds.insert(taskId)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func selectAllUncompleted() {
        selectedTaskIds = Set(uncompletedTasks.map { $0.id })
    }

    func deselectAll() {
        selectedTaskIds = []
    }

    func batchDeleteTasks() async {
        let idsToDelete = selectedTaskIds

        do {
            for taskId in idsToDelete {
                try await commitmentRepository.deleteCommitments(forTask: taskId)
                try await repository.deleteTask(id: taskId)
            }

            tasks.removeAll { idsToDelete.contains($0.id) }
            for taskId in idsToDelete {
                subtasksMap.removeValue(forKey: taskId)
            }
            exitEditMode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func batchMoveToCategory(_ categoryId: UUID?) async {
        do {
            for taskId in selectedTaskIds {
                if let index = tasks.firstIndex(where: { $0.id == taskId }) {
                    var updated = tasks[index]
                    updated.categoryId = categoryId
                    updated.modifiedDate = Date()
                    try await repository.updateTask(updated)
                    tasks[index].categoryId = categoryId
                    tasks[index].modifiedDate = Date()
                }
            }
            exitEditMode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createProjectFromSelected(title: String) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        do {
            let projectTask = FocusTask(
                userId: userId,
                title: trimmed,
                type: .project,
                isCompleted: false,
                sortOrder: 0,
                isInLog: true
            )
            let createdProject = try await repository.createTask(projectTask)

            for (index, taskId) in selectedTaskIds.enumerated() {
                if let taskIndex = tasks.firstIndex(where: { $0.id == taskId }) {
                    var task = tasks[taskIndex]
                    task.parentTaskId = createdProject.id
                    task.sortOrder = index
                    task.modifiedDate = Date()
                    try await repository.updateTask(task)
                }
            }

            tasks.removeAll { selectedTaskIds.contains($0.id) }
            exitEditMode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createListFromSelected(title: String) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        do {
            let listTask = FocusTask(
                userId: userId,
                title: trimmed,
                type: .list,
                isCompleted: false,
                sortOrder: 0,
                isInLog: true
            )
            let createdList = try await repository.createTask(listTask)

            for (index, taskId) in selectedTaskIds.enumerated() {
                if let taskIndex = tasks.firstIndex(where: { $0.id == taskId }) {
                    var task = tasks[taskIndex]
                    task.parentTaskId = createdList.id
                    task.sortOrder = index
                    task.modifiedDate = Date()
                    try await repository.updateTask(task)
                }
            }

            tasks.removeAll { selectedTaskIds.contains($0.id) }
            exitEditMode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createCategoryAndMove(name: String, task: FocusTask) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        do {
            let newCategory = Category(
                userId: userId,
                name: trimmed,
                sortOrder: categories.count
            )
            let created = try await categoryRepository.createCategory(newCategory)
            categories.append(created)
            await moveTaskToCategory(task, categoryId: created.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
