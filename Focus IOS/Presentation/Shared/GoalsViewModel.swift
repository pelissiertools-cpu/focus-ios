//
//  GoalsViewModel.swift
//  Focus IOS
//

import Foundation
import Combine
import SwiftUI
import Auth

// MARK: - Goal Display Item

enum GoalDisplayItem: Identifiable {
    case task(FocusTask)
    case section(FocusTask)
    case addSubtaskRow(parentId: UUID)
    case addTaskRow
    case completedHeader(count: Int)

    var id: String {
        switch self {
        case .task(let task): return "\(task.id.uuidString)-\(task.isCompleted)"
        case .section(let section): return "section-\(section.id.uuidString)"
        case .addSubtaskRow(let parentId): return "add-subtask-\(parentId.uuidString)"
        case .addTaskRow: return "add-task"
        case .completedHeader: return "completed-header"
        }
    }
}

@MainActor
class GoalsViewModel: ObservableObject, TaskEditingViewModel, LogFilterable {
    // MARK: - Published Properties
    @Published var goals: [FocusTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingAddGoal = false
    @Published var selectedGoalForDetails: FocusTask?
    @Published var selectedGoalForContent: FocusTask?
    @Published var selectedTaskForDetails: FocusTask?
    @Published var selectedTaskForSchedule: FocusTask?

    // Goal tasks state management
    @Published var goalTasksMap: [UUID: [FocusTask]] = [:]
    @Published var isLoadingGoalTasks: Set<UUID> = []

    // Subtasks for tasks within goals
    @Published var subtasksMap: [UUID: [FocusTask]] = [:]
    @Published var expandedTasks: Set<UUID> = []
    @Published var isLoadingSubtasks: Set<UUID> = []

    // Category filter
    @Published var categories: [Category] = []
    @Published var selectedCategoryId: UUID? = nil

    // Schedule filter
    @Published var scheduleFilter: ScheduleFilter? = nil
    @Published var scheduledTaskIds: Set<UUID> = []
    @Published var taskDueDates: [UUID: Date] = [:]
    @Published var taskScheduleDates: [UUID: Date] = [:]

    // Edit mode (goal list)
    @Published var isEditMode: Bool = false
    @Published var selectedGoalIds: Set<UUID> = []

    // Batch operation triggers (goal list)
    @Published var showBatchDeleteConfirmation: Bool = false
    @Published var showBatchMovePicker: Bool = false
    @Published var showBatchScheduleSheet: Bool = false

    // Content-level edit mode (tasks within a goal)
    @Published var contentEditMode: Bool = false
    @Published var selectedContentTaskIds: Set<UUID> = []
    @Published var showContentBatchDeleteConfirmation: Bool = false
    @Published var showContentBatchScheduleSheet: Bool = false
    @Published var showContentBatchMovePicker: Bool = false

    // Search
    @Published var searchText: String = ""

    // Sort
    @Published var sortOption: SortOption = .creationDate
    @Published var sortDirection: SortDirection = .lowestFirst

    // Done section
    @Published var isDoneCollapsed: Bool = true
    @Published var isContentDoneCollapsed: Bool = true

    // Pending completion grace period
    let pendingCompletion = PendingCompletionManager()
    @Published var pendingCompletionTaskIds: Set<UUID> = []

    private let repository: TaskRepository
    let scheduleRepository: ScheduleRepository
    private let categoryRepository: CategoryRepository
    let authService: AuthService
    private var cancellables = Set<AnyCancellable>()

    init(repository: TaskRepository = TaskRepository(),
         scheduleRepository: ScheduleRepository = ScheduleRepository(),
         categoryRepository: CategoryRepository = CategoryRepository(),
         authService: AuthService) {
        self.repository = repository
        self.scheduleRepository = scheduleRepository
        self.categoryRepository = categoryRepository
        self.authService = authService

        // Pre-populate from cache for instant display
        let cache = AppDataCache.shared
        if cache.hasLoadedGoals {
            self.goals = cache.goals
        }
        if cache.hasLoadedCategories {
            self.categories = cache.categories
        }

        pendingCompletion.onChange = { [weak self] in
            self?.pendingCompletionTaskIds = self?.pendingCompletion.pendingIds ?? []
        }

        setupNotificationObserver()
    }

    // MARK: - Notification Sync

    private func setupNotificationObserver() {
        NotificationCenter.default.publisher(for: .taskCompletionChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleTaskCompletionNotification(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .projectListChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                _Concurrency.Task { @MainActor in
                    await self.fetchGoals()
                }
            }
            .store(in: &cancellables)
    }

    private func handleTaskCompletionNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let taskId = userInfo[TaskNotificationKeys.taskId] as? UUID,
              let isCompleted = userInfo[TaskNotificationKeys.isCompleted] as? Bool else {
            return
        }

        let completedDate = userInfo[TaskNotificationKeys.completedDate] as? Date

        if let index = goals.firstIndex(where: { $0.id == taskId }) {
            goals[index].isCompleted = isCompleted
            goals[index].completedDate = completedDate
        }

        for (goalId, var tasks) in goalTasksMap {
            if let index = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[index].isCompleted = isCompleted
                tasks[index].completedDate = completedDate
                goalTasksMap[goalId] = tasks
                _Concurrency.Task { @MainActor in
                    try? await checkGoalAutoComplete(goalId: goalId)
                }
                break
            }
        }

        for (parentId, var subtasks) in subtasksMap {
            if let index = subtasks.firstIndex(where: { $0.id == taskId }) {
                subtasks[index].isCompleted = isCompleted
                subtasks[index].completedDate = completedDate
                subtasksMap[parentId] = subtasks
                break
            }
        }
    }

    // MARK: - LogFilterable Conformance

    var showingAddItem: Bool {
        get { showingAddGoal }
        set { showingAddGoal = newValue }
    }

    var selectedItemIds: Set<UUID> {
        get { selectedGoalIds }
        set { selectedGoalIds = newValue }
    }

    var selectedItems: [FocusTask] {
        goals.filter { selectedGoalIds.contains($0.id) }
    }

    var selectedCount: Int { selectedGoalIds.count }

    var allUncompletedSelected: Bool {
        let uncompletedIds = Set(filteredGoals.map { $0.id })
        return !uncompletedIds.isEmpty && uncompletedIds.isSubset(of: selectedGoalIds)
    }

    // MARK: - Computed Properties

    private var baseFilteredGoals: [FocusTask] {
        var filtered = goals
        if let categoryId = selectedCategoryId {
            filtered = filtered.filter { $0.categoryId == categoryId }
        }
        if let scheduleFilter = scheduleFilter {
            switch scheduleFilter {
            case .scheduled:
                filtered = filtered.filter { scheduledTaskIds.contains($0.id) }
            case .unscheduled:
                filtered = filtered.filter { !scheduledTaskIds.contains($0.id) }
            }
        }
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
        }
        return filtered
    }

    var filteredGoals: [FocusTask] {
        applySorting(to: baseFilteredGoals.filter { !$0.isCompleted })
    }

    var completedGoals: [FocusTask] {
        baseFilteredGoals.filter { $0.isCompleted }
    }


    private func applySorting(to items: [FocusTask]) -> [FocusTask] {
        let ascending = sortDirection == .lowestFirst
        switch sortOption {
        case .priority:
            return items.sorted { a, b in
                if a.priority.sortIndex != b.priority.sortIndex {
                    return ascending ? a.priority.sortIndex < b.priority.sortIndex : a.priority.sortIndex > b.priority.sortIndex
                }
                return a.sortOrder < b.sortOrder
            }
        case .dueDate:
            return items.sorted { a, b in
                let dateA = a.dueDate ?? taskDueDates[a.id]
                let dateB = b.dueDate ?? taskDueDates[b.id]
                switch (dateA, dateB) {
                case (.some(let da), .some(let db)):
                    return ascending ? da < db : da > db
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return a.createdDate < b.createdDate
                }
            }
        case .creationDate:
            return items.sorted {
                ascending ? $0.createdDate < $1.createdDate : $0.createdDate > $1.createdDate
            }
        }
    }

    func toggleDoneCollapsed() {
        isDoneCollapsed.toggle()
    }

    func toggleContentDoneCollapsed() {
        isContentDoneCollapsed.toggle()
    }

    func flattenedGoalItems(for goalId: UUID) -> [GoalDisplayItem] {
        let allTasks = goalTasksMap[goalId] ?? []
        let uncompleted = allTasks.filter { !$0.isCompleted && $0.parentTaskId == nil }.sorted { $0.sortOrder < $1.sortOrder }
        let completed = allTasks.filter { $0.isCompleted && $0.parentTaskId == nil }.sorted { $0.sortOrder < $1.sortOrder }

        var result: [GoalDisplayItem] = []
        for task in uncompleted {
            if task.isSection {
                result.append(.section(task))
            } else {
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
        result.append(.addTaskRow)
        if !completed.isEmpty {
            result.append(.completedHeader(count: completed.count))
            if !isContentDoneCollapsed {
                for task in completed {
                    result.append(.task(task))
                }
            }
        }
        return result
    }

    func clearCompletedGoals() async {
        let completedIds = Set(completedGoals.map { $0.id })
        guard !completedIds.isEmpty else { return }

        do {
            try await repository.clearTasks(ids: completedIds)
            goals.removeAll { completedIds.contains($0.id) }
            for goalId in completedIds {
                goalTasksMap.removeValue(forKey: goalId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Task Expansion (within goals)

    func toggleTaskExpanded(_ taskId: UUID) async {
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

    func isTaskExpanded(_ taskId: UUID) -> Bool {
        expandedTasks.contains(taskId)
    }

    // MARK: - Data Fetching

    func fetchGoals() async {
        if goals.isEmpty { isLoading = true }
        errorMessage = nil

        do {
            let fetchedGoals = try await repository.fetchGoals(isCleared: false)
            self.goals = fetchedGoals
            self.categories = try await categoryRepository.fetchCategories()
            await fetchScheduledTaskIds()

            // Update cache
            let cache = AppDataCache.shared
            cache.goals = fetchedGoals
            cache.hasLoadedGoals = true

            for goal in goals {
                await fetchGoalTasks(for: goal.id)
            }

            isLoading = false
        } catch {
            if !_Concurrency.Task.isCancelled { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }

    func fetchGoalTasks(for goalId: UUID) async {
        guard !isLoadingGoalTasks.contains(goalId) else { return }
        isLoadingGoalTasks.insert(goalId)

        do {
            let allTasks = try await repository.fetchGoalTasks(goalId: goalId)
            let topLevelTasks = allTasks.filter { $0.parentTaskId == nil && !$0.isCleared }
            goalTasksMap[goalId] = topLevelTasks

            for task in allTasks where task.parentTaskId != nil && !task.isCleared {
                subtasksMap[task.parentTaskId!, default: []].append(task)
            }
            for task in topLevelTasks where !task.isSection {
                if subtasksMap[task.id] == nil {
                    subtasksMap[task.id] = []
                }
            }
        } catch {
            if !_Concurrency.Task.isCancelled { errorMessage = error.localizedDescription }
        }

        isLoadingGoalTasks.remove(goalId)
    }

    func fetchSubtasks(for taskId: UUID) async {
        guard !isLoadingSubtasks.contains(taskId) else { return }
        isLoadingSubtasks.insert(taskId)

        do {
            let subtasks = try await repository.fetchSubtasks(parentId: taskId)
            subtasksMap[taskId] = subtasks.filter { !$0.isCleared }
        } catch {
            if !_Concurrency.Task.isCancelled { errorMessage = error.localizedDescription }
        }

        isLoadingSubtasks.remove(taskId)
    }

    // MARK: - Progress Calculations

    func taskProgress(for goalId: UUID) -> (completed: Int, total: Int) {
        let tasks = (goalTasksMap[goalId] ?? []).filter { !$0.isSection }
        let completed = tasks.filter { $0.isCompleted }.count
        return (completed, tasks.count)
    }

    func progressPercentage(for goalId: UUID) -> Double {
        let (completed, total) = taskProgress(for: goalId)
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    // MARK: - Goal CRUD

    @discardableResult
    func saveNewGoal(title: String, dueDate: Date?, draftSteps: [DraftSubtaskEntry]) async -> UUID? {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return nil
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return nil }

        do {
            let goal = try await repository.createGoal(
                title: trimmedTitle,
                userId: userId,
                dueDate: dueDate
            )

            for (index, step) in draftSteps.enumerated() {
                let trimmed = step.title.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                _ = try await repository.createGoalTask(
                    title: trimmed,
                    goalId: goal.id,
                    userId: userId,
                    sortOrder: index
                )
            }

            goals.insert(goal, at: 0)
            await fetchGoalTasks(for: goal.id)
            NotificationCenter.default.post(name: .projectListChanged, object: nil)
            return goal.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteGoal(_ goal: FocusTask) async {
        do {
            try await scheduleRepository.deleteSchedules(forTask: goal.id)
            try await repository.deleteTask(id: goal.id)
            goals.removeAll { $0.id == goal.id }
            goalTasksMap.removeValue(forKey: goal.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteGoalKeepTasks(_ goal: FocusTask) async {
        do {
            try await repository.unlinkProjectTasks(projectId: goal.id)
            try await scheduleRepository.deleteSchedules(forTask: goal.id)
            try await repository.deleteTask(id: goal.id)
            goals.removeAll { $0.id == goal.id }
            goalTasksMap.removeValue(forKey: goal.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Goal Task CRUD

    func createGoalTask(title: String, goalId: UUID) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }

        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        do {
            let task = try await repository.createGoalTask(
                title: trimmed,
                goalId: goalId,
                userId: userId
            )

            if var tasks = goalTasksMap[goalId] {
                tasks.append(task)
                goalTasksMap[goalId] = tasks
            } else {
                goalTasksMap[goalId] = [task]
            }
            subtasksMap[task.id] = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteGoalTask(_ task: FocusTask, goalId: UUID) async {
        do {
            try await repository.deleteTask(id: task.id)
            if var tasks = goalTasksMap[goalId] {
                tasks.removeAll { $0.id == task.id }
                goalTasksMap[goalId] = tasks
            }
            subtasksMap.removeValue(forKey: task.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Task Completion

    func toggleTaskCompletion(_ task: FocusTask, goalId: UUID) async {
        do {
            if task.isCompleted {
                try await repository.uncompleteTask(id: task.id)

                let currentTask = goalTasksMap[goalId]?.first(where: { $0.id == task.id })
                if let previousStates = currentTask?.previousCompletionState {
                    try await repository.restoreSubtaskStates(parentId: task.id, completionStates: previousStates)
                    await fetchSubtasks(for: task.id)
                }
            } else {
                let subtasks = subtasksMap[task.id] ?? []
                let previousStates = subtasks.map { $0.isCompleted }

                if var tasks = goalTasksMap[goalId],
                   let index = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[index].previousCompletionState = previousStates
                    var updatedTask = tasks[index]
                    updatedTask.previousCompletionState = previousStates
                    try await repository.updateTask(updatedTask)
                    goalTasksMap[goalId] = tasks
                }

                try await repository.completeTask(id: task.id)
                if !subtasks.isEmpty {
                    try await repository.completeSubtasks(parentId: task.id)
                    if var localSubtasks = subtasksMap[task.id] {
                        for i in localSubtasks.indices {
                            localSubtasks[i].isCompleted = true
                            localSubtasks[i].completedDate = Date()
                        }
                        subtasksMap[task.id] = localSubtasks
                    }
                }
            }

            if var tasks = goalTasksMap[goalId],
               let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].isCompleted.toggle()
                if tasks[index].isCompleted {
                    tasks[index].completedDate = Date()
                } else {
                    tasks[index].completedDate = nil
                }
                goalTasksMap[goalId] = tasks

                try await checkGoalAutoComplete(goalId: goalId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Pending Completion (Grace Period)

    func requestToggleTaskCompletion(_ task: FocusTask, goalId: UUID) {
        if task.isCompleted {
            _Concurrency.Task { await toggleTaskCompletion(task, goalId: goalId) }
            return
        }

        let taskId = task.id
        pendingCompletion.scheduleCompletion(for: taskId) { [weak self] in
            guard let self,
                  let tasks = self.goalTasksMap[goalId],
                  let currentTask = tasks.first(where: { $0.id == taskId }),
                  !currentTask.isCompleted else { return }
            await self.toggleTaskCompletion(currentTask, goalId: goalId)
        }
    }

    func requestToggleSubtaskCompletion(_ subtask: FocusTask, parentId: UUID) {
        if subtask.isCompleted {
            _Concurrency.Task { await toggleSubtaskCompletion(subtask, parentId: parentId) }
            return
        }

        let subtaskId = subtask.id
        pendingCompletion.scheduleCompletion(for: subtaskId) { [weak self] in
            guard let self,
                  let subtasks = self.subtasksMap[parentId],
                  let currentSubtask = subtasks.first(where: { $0.id == subtaskId }),
                  !currentSubtask.isCompleted else { return }
            await self.toggleSubtaskCompletion(currentSubtask, parentId: parentId)
        }
    }

    func cancelPendingCompletion(_ taskId: UUID) {
        pendingCompletion.cancel(taskId)
    }

    func isPendingCompletion(_ taskId: UUID) -> Bool {
        pendingCompletion.isPending(taskId)
    }

    func toggleSubtaskCompletion(_ subtask: FocusTask, parentId: UUID) async {
        let preToggleStates = (subtasksMap[parentId] ?? []).map { $0.isCompleted }
        do {
            if subtask.isCompleted {
                try await repository.uncompleteTask(id: subtask.id)
            } else {
                try await repository.completeTask(id: subtask.id)
            }

            if var subtasks = subtasksMap[parentId],
               let index = subtasks.firstIndex(where: { $0.id == subtask.id }) {
                subtasks[index].isCompleted.toggle()
                if subtasks[index].isCompleted {
                    subtasks[index].completedDate = Date()
                } else {
                    subtasks[index].completedDate = nil
                }
                subtasksMap[parentId] = subtasks

                let allComplete = subtasks.allSatisfy { $0.isCompleted }
                if allComplete && !subtasks.isEmpty {
                    for (goalId, tasks) in goalTasksMap {
                        if let taskIndex = tasks.firstIndex(where: { $0.id == parentId }),
                           !tasks[taskIndex].isCompleted {
                            var updatedTasks = tasks
                            updatedTasks[taskIndex].previousCompletionState = preToggleStates
                            try await repository.updateTask(updatedTasks[taskIndex])
                            try await repository.completeTask(id: parentId)
                            updatedTasks[taskIndex].isCompleted = true
                            updatedTasks[taskIndex].completedDate = Date()
                            goalTasksMap[goalId] = updatedTasks
                            break
                        }
                    }
                } else if !allComplete {
                    for (goalId, tasks) in goalTasksMap {
                        if let taskIndex = tasks.firstIndex(where: { $0.id == parentId }),
                           tasks[taskIndex].isCompleted {
                            try await repository.uncompleteTask(id: parentId)
                            var updatedTasks = tasks
                            updatedTasks[taskIndex].isCompleted = false
                            updatedTasks[taskIndex].completedDate = nil
                            goalTasksMap[goalId] = updatedTasks
                            break
                        }
                    }
                }

                if let goalId = goalTasksMap.first(where: { $0.value.contains(where: { $0.id == parentId }) })?.key {
                    try await checkGoalAutoComplete(goalId: goalId)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Goal Auto-Complete

    private func checkGoalAutoComplete(goalId: UUID) async throws {
        let tasks = (goalTasksMap[goalId] ?? []).filter { !$0.isSection }
        guard !tasks.isEmpty else { return }

        let allTasksComplete = tasks.allSatisfy { $0.isCompleted }

        if allTasksComplete, let goalIndex = goals.firstIndex(where: { $0.id == goalId }),
           !goals[goalIndex].isCompleted {
            try await repository.completeTask(id: goalId)
            goals[goalIndex].isCompleted = true
            goals[goalIndex].completedDate = Date()
        } else if !allTasksComplete, let goalIndex = goals.firstIndex(where: { $0.id == goalId }),
                  goals[goalIndex].isCompleted {
            try await repository.uncompleteTask(id: goalId)
            goals[goalIndex].isCompleted = false
            goals[goalIndex].completedDate = nil
        }
    }

    // MARK: - Subtask CRUD

    func createSubtask(title: String, parentId: UUID) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }

        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let goalId = goalTasksMap.first(where: { $0.value.contains(where: { $0.id == parentId }) })?.key

        do {
            let newSubtask = try await repository.createSubtask(
                title: trimmed,
                parentTaskId: parentId,
                userId: userId,
                projectId: goalId
            )

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

    func deleteSubtask(_ subtask: FocusTask, parentId: UUID) async {
        do {
            try await repository.deleteTask(id: subtask.id)
            if var subtasks = subtasksMap[parentId] {
                subtasks.removeAll { $0.id == subtask.id }
                subtasksMap[parentId] = subtasks
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Section CRUD

    func createSection(title: String, goalId: UUID) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }
        do {
            let section = try await repository.createGoalSection(
                title: title,
                goalId: goalId,
                userId: userId
            )
            if var tasks = goalTasksMap[goalId] {
                tasks.append(section)
                goalTasksMap[goalId] = tasks
            } else {
                goalTasksMap[goalId] = [section]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameSection(_ section: FocusTask, newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != section.title else { return }
        await updateTask(section, newTitle: trimmed)
    }

    func deleteSection(_ section: FocusTask, goalId: UUID) async {
        await deleteGoalTask(section, goalId: goalId)
    }

    // MARK: - Content Edit Mode (tasks within a goal)

    func enterContentEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            contentEditMode = true
            selectedContentTaskIds = []
        }
    }

    func exitContentEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            contentEditMode = false
            selectedContentTaskIds = []
        }
    }

    func toggleContentTaskSelection(_ taskId: UUID) {
        if selectedContentTaskIds.contains(taskId) {
            selectedContentTaskIds.remove(taskId)
        } else {
            selectedContentTaskIds.insert(taskId)
        }
    }

    func selectAllContentTasks(goalId: UUID) {
        let tasks = (goalTasksMap[goalId] ?? []).filter { !$0.isSection && !$0.isCompleted }
        selectedContentTaskIds = Set(tasks.map { $0.id })
    }

    func deselectAllContentTasks() {
        selectedContentTaskIds = []
    }

    var allContentTasksSelected: Bool {
        guard let goalId = selectedGoalForContent?.id else { return false }
        let tasks = (goalTasksMap[goalId] ?? []).filter { !$0.isSection && !$0.isCompleted }
        return !tasks.isEmpty && Set(tasks.map { $0.id }).isSubset(of: selectedContentTaskIds)
    }

    var selectedContentTasks: [FocusTask] {
        guard let goalId = selectedGoalForContent?.id else { return [] }
        let allTasks = goalTasksMap[goalId] ?? []
        return allTasks.filter { selectedContentTaskIds.contains($0.id) }
    }

    func batchDeleteContentTasks(goalId: UUID) async {
        let idsToDelete = selectedContentTaskIds
        do {
            for id in idsToDelete {
                try await repository.deleteTask(id: id)
            }
            if var tasks = goalTasksMap[goalId] {
                tasks.removeAll { idsToDelete.contains($0.id) }
                goalTasksMap[goalId] = tasks
            }
            for id in idsToDelete {
                subtasksMap.removeValue(forKey: id)
            }
            exitContentEditMode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Edit Mode (goal list)

    func enterEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditMode = true
            selectedGoalIds = []
        }
    }

    func exitEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditMode = false
            selectedGoalIds = []
        }
    }

    func toggleGoalSelection(_ goalId: UUID) {
        if selectedGoalIds.contains(goalId) {
            selectedGoalIds.remove(goalId)
        } else {
            selectedGoalIds.insert(goalId)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func selectAllUncompleted() {
        selectedGoalIds = Set(filteredGoals.map { $0.id })
    }

    func deselectAll() {
        selectedGoalIds = []
    }

    func batchDeleteGoals() async {
        let idsToDelete = selectedGoalIds

        do {
            async let deleteSchedules: Void = scheduleRepository.deleteSchedules(forTasks: idsToDelete)
            async let deleteGoals: Void = repository.deleteTasks(ids: idsToDelete)
            _ = try await (deleteSchedules, deleteGoals)

            goals.removeAll { idsToDelete.contains($0.id) }
            for goalId in idsToDelete {
                goalTasksMap.removeValue(forKey: goalId)
            }
            exitEditMode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func batchMoveToCategory(_ categoryId: UUID?) async {
        do {
            for goalId in selectedGoalIds {
                if let index = goals.firstIndex(where: { $0.id == goalId }) {
                    var updated = goals[index]
                    updated.categoryId = categoryId
                    updated.modifiedDate = Date()
                    try await repository.updateTask(updated)
                    goals[index].categoryId = categoryId
                    goals[index].modifiedDate = Date()
                }
            }
            exitEditMode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Category

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

    func renameCategory(id: UUID, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        do {
            if let index = categories.firstIndex(where: { $0.id == id }) {
                var updated = categories[index]
                updated.name = trimmed
                try await categoryRepository.updateCategory(updated)
                categories[index].name = trimmed
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCategories(ids: Set<UUID>) async {
        do {
            for categoryId in ids {
                try await repository.nullifyCategoryId(categoryId: categoryId)
                try await categoryRepository.deleteCategory(id: categoryId)
            }
            for i in goals.indices {
                if let catId = goals[i].categoryId, ids.contains(catId) {
                    goals[i].categoryId = nil
                }
            }
            categories.removeAll { ids.contains($0.id) }
            if let selected = selectedCategoryId, ids.contains(selected) {
                selectedCategoryId = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func mergeCategories(ids: Set<UUID>) async {
        let sorted = categories.filter { ids.contains($0.id) }.sorted { $0.sortOrder < $1.sortOrder }
        guard sorted.count >= 2, let target = sorted.first else { return }
        let sourceIds = Set(sorted.dropFirst().map { $0.id })

        do {
            for sourceId in sourceIds {
                try await repository.reassignCategory(from: sourceId, to: target.id)
                try await categoryRepository.deleteCategory(id: sourceId)
            }
            for i in goals.indices {
                if let catId = goals[i].categoryId, sourceIds.contains(catId) {
                    goals[i].categoryId = target.id
                }
            }
            categories.removeAll { sourceIds.contains($0.id) }
            if let selected = selectedCategoryId, sourceIds.contains(selected) {
                selectedCategoryId = target.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reorderCategories(fromOffsets: IndexSet, toOffset: Int) async {
        categories.move(fromOffsets: fromOffsets, toOffset: toOffset)
        do {
            for (index, var cat) in categories.enumerated() {
                cat.sortOrder = index
                categories[index].sortOrder = index
                try await categoryRepository.updateCategory(cat)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Reordering

    func reorderGoal(droppedId: UUID, targetId: UUID) {
        guard let updates = ReorderUtility.reorderItems(
            &goals, droppedId: droppedId, targetId: targetId
        ) else { return }
        _Concurrency.Task { await persistSortOrders(updates) }
    }

    private func persistSortOrders(_ updates: [(id: UUID, sortOrder: Int)]) async {
        do {
            try await repository.updateSortOrders(updates)
        } catch {
            errorMessage = "Failed to save order: \(error.localizedDescription)"
        }
    }

    // MARK: - Goal Content Flat Move Handler

    func handleGoalContentFlatMove(from source: IndexSet, to destination: Int, goalId: UUID) {
        let flat = flattenedGoalItems(for: goalId)
        guard let fromIdx = source.first else { return }

        let movedTask: FocusTask
        switch flat[fromIdx] {
        case .task(let t): movedTask = t
        case .section(let s): movedTask = s
        default: return
        }
        guard !movedTask.isCompleted else { return }

        if movedTask.parentTaskId == nil {
            let parentIndices = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, task: FocusTask)? in
                switch item {
                case .task(let t) where t.parentTaskId == nil && !t.isCompleted: return (i, t)
                case .section(let s): return (i, s)
                default: return nil
                }
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

            guard var allTasks = goalTasksMap[goalId] else { return }
            var uncompleted = allTasks.filter { !$0.isCompleted && $0.parentTaskId == nil }.sorted { $0.sortOrder < $1.sortOrder }

            uncompleted.move(fromOffsets: IndexSet(integer: parentFrom), toOffset: parentTo)

            var updates: [(id: UUID, sortOrder: Int)] = []
            for (index, task) in uncompleted.enumerated() {
                if let mapIndex = allTasks.firstIndex(where: { $0.id == task.id }) {
                    allTasks[mapIndex].sortOrder = index
                }
                updates.append((id: task.id, sortOrder: index))
            }
            goalTasksMap[goalId] = allTasks
            _Concurrency.Task { await persistSortOrders(updates) }

        } else {
            let parentId = movedTask.parentTaskId!

            guard let parentFlatIdx = flat.firstIndex(where: {
                if case .task(let t) = $0 { return t.id == parentId }
                return false
            }) else { return }

            let sectionEnd = flat[(parentFlatIdx + 1)...].firstIndex(where: {
                if case .task(let t) = $0 { return t.parentTaskId == nil }
                return false
            }) ?? flat.count

            guard destination > parentFlatIdx && destination <= sectionEnd else { return }

            let siblingIndices = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, task: FocusTask)? in
                if case .task(let t) = item, t.parentTaskId == parentId, !t.isCompleted { return (i, t) }
                return nil
            }

            guard let siblingFrom = siblingIndices.firstIndex(where: { $0.task.id == movedTask.id }) else { return }

            var siblingTo = siblingIndices.count
            for (si, entry) in siblingIndices.enumerated() {
                if destination <= entry.flatIdx {
                    siblingTo = si
                    break
                }
            }
            if siblingTo > siblingFrom { siblingTo = min(siblingTo, siblingIndices.count) }

            guard siblingFrom != siblingTo && siblingFrom + 1 != siblingTo else { return }

            guard var allChildren = subtasksMap[parentId] else { return }
            var uncompleted = allChildren.filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }

            uncompleted.move(fromOffsets: IndexSet(integer: siblingFrom), toOffset: siblingTo)

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

    // MARK: - TaskEditingViewModel Conformance

    func findTask(byId id: UUID) -> FocusTask? {
        for tasks in goalTasksMap.values {
            if let task = tasks.first(where: { $0.id == id }) {
                return task
            }
        }
        for subtasks in subtasksMap.values {
            if let subtask = subtasks.first(where: { $0.id == id }) {
                return subtask
            }
        }
        return nil
    }

    func getSubtasks(for taskId: UUID) -> [FocusTask] {
        getUncompletedSubtasks(for: taskId) + getCompletedSubtasks(for: taskId)
    }

    func updateTask(_ task: FocusTask, newTitle: String) async {
        guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        do {
            var updatedTask = task
            updatedTask.title = newTitle
            updatedTask.modifiedDate = Date()
            try await repository.updateTask(updatedTask)

            if let goalId = task.projectId,
               var tasks = goalTasksMap[goalId],
               let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].title = newTitle
                tasks[index].modifiedDate = Date()
                goalTasksMap[goalId] = tasks
            }

            if let parentId = task.parentTaskId,
               var subtasks = subtasksMap[parentId],
               let index = subtasks.firstIndex(where: { $0.id == task.id }) {
                subtasks[index].title = newTitle
                subtasks[index].modifiedDate = Date()
                subtasksMap[parentId] = subtasks
            }

            NotificationCenter.default.post(name: .projectListChanged, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTaskNote(_ task: FocusTask, newNote: String?) async {
        do {
            var updatedTask = task
            updatedTask.description = newNote
            updatedTask.modifiedDate = Date()
            try await repository.updateTask(updatedTask)

            if let index = goals.firstIndex(where: { $0.id == task.id }) {
                goals[index].description = newNote
                goals[index].modifiedDate = Date()
            }

            if let goalId = task.projectId,
               var tasks = goalTasksMap[goalId],
               let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].description = newNote
                tasks[index].modifiedDate = Date()
                goalTasksMap[goalId] = tasks
            }

            if let parentId = task.parentTaskId,
               var subtasks = subtasksMap[parentId],
               let index = subtasks.firstIndex(where: { $0.id == task.id }) {
                subtasks[index].description = newNote
                subtasks[index].modifiedDate = Date()
                subtasksMap[parentId] = subtasks
            }

            NotificationCenter.default.post(name: .projectListChanged, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTask(_ task: FocusTask) async {
        guard let goalId = task.projectId else { return }
        await deleteGoalTask(task, goalId: goalId)
    }

    func updateTaskPriority(_ task: FocusTask, priority: Priority) async {
        do {
            var updated = task
            updated.priority = priority
            updated.modifiedDate = Date()
            try await repository.updateTask(updated)

            if let index = goals.firstIndex(where: { $0.id == task.id }) {
                goals[index].priority = priority
                goals[index].modifiedDate = Date()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveTaskToCategory(_ task: FocusTask, categoryId: UUID?) async {
        do {
            var updated = task
            updated.categoryId = categoryId
            updated.modifiedDate = Date()
            try await repository.updateTask(updated)

            if let goalId = task.projectId,
               var tasks = goalTasksMap[goalId],
               let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].categoryId = categoryId
                tasks[index].modifiedDate = Date()
                goalTasksMap[goalId] = tasks
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createCategoryAndMove(name: String, task: FocusTask) async {
        guard let userId = authService.currentUser?.id else { return }
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

    // MARK: - Due Date

    func updateGoalDueDate(_ goal: FocusTask, dueDate: Date?) async {
        do {
            var updated = goal
            updated.dueDate = dueDate
            updated.modifiedDate = Date()
            try await repository.updateTask(updated)

            if let index = goals.firstIndex(where: { $0.id == goal.id }) {
                goals[index].dueDate = dueDate
                goals[index].modifiedDate = Date()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
