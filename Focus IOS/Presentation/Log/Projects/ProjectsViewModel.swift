//
//  ProjectsViewModel.swift
//  Focus IOS
//

import Foundation
import Combine
import SwiftUI
import Auth

// MARK: - Project Card Display Item

enum ProjectCardDisplayItem: Identifiable {
    case task(FocusTask)
    case addSubtaskRow(parentId: UUID)
    case addTaskRow

    var id: String {
        switch self {
        case .task(let task): return task.id.uuidString
        case .addSubtaskRow(let parentId): return "add-subtask-\(parentId.uuidString)"
        case .addTaskRow: return "add-task"
        }
    }
}

@MainActor
class ProjectsViewModel: ObservableObject, TaskEditingViewModel, LogFilterable {
    // MARK: - Published Properties
    @Published var projects: [FocusTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingAddProject = false
    @Published var selectedProjectForDetails: FocusTask?
    @Published var selectedTaskForDetails: FocusTask?

    // Project tasks state management
    @Published var projectTasksMap: [UUID: [FocusTask]] = [:]
    @Published var expandedProjects: Set<UUID> = []
    @Published var isLoadingProjectTasks: Set<UUID> = []

    // Subtasks for tasks within projects
    @Published var subtasksMap: [UUID: [FocusTask]] = [:]
    @Published var expandedTasks: Set<UUID> = []
    @Published var isLoadingSubtasks: Set<UUID> = []

    // Category filter
    @Published var categories: [Category] = []
    @Published var selectedCategoryId: UUID? = nil

    // Commitment filter
    @Published var commitmentFilter: CommitmentFilter? = nil
    @Published var committedTaskIds: Set<UUID> = []

    // Edit mode
    @Published var isEditMode: Bool = false
    @Published var selectedProjectIds: Set<UUID> = []

    // Batch operation triggers
    @Published var showBatchDeleteConfirmation: Bool = false
    @Published var showBatchMovePicker: Bool = false
    @Published var showBatchCommitSheet: Bool = false

    // Search
    @Published var searchText: String = ""

    // Done section
    @Published var isDoneCollapsed: Bool = true

    private let repository: TaskRepository
    let commitmentRepository: CommitmentRepository
    private let categoryRepository: CategoryRepository
    let authService: AuthService
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

    // MARK: - Notification Sync

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

        // Update projects array if this project was completed/uncompleted
        if let index = projects.firstIndex(where: { $0.id == taskId }) {
            projects[index].isCompleted = isCompleted
            projects[index].completedDate = completedDate
        }

        // Update projectTasksMap if this is a project task
        for (projectId, var tasks) in projectTasksMap {
            if let index = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[index].isCompleted = isCompleted
                tasks[index].completedDate = completedDate
                projectTasksMap[projectId] = tasks
                break
            }
        }

        // Update subtasksMap if this is a subtask within a project
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

    var categoryType: String { "project" }

    var showingAddItem: Bool {
        get { showingAddProject }
        set { showingAddProject = newValue }
    }

    var selectedItemIds: Set<UUID> {
        get { selectedProjectIds }
        set { selectedProjectIds = newValue }
    }

    var selectedItems: [FocusTask] {
        projects.filter { selectedProjectIds.contains($0.id) }
    }

    var selectedCount: Int { selectedProjectIds.count }

    var allUncompletedSelected: Bool {
        let uncompletedIds = Set(filteredProjects.map { $0.id })
        return !uncompletedIds.isEmpty && uncompletedIds.isSubset(of: selectedProjectIds)
    }

    // MARK: - Computed Properties

    private var baseFilteredProjects: [FocusTask] {
        var filtered = projects
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
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
        }
        return filtered
    }

    var filteredProjects: [FocusTask] {
        baseFilteredProjects.filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var completedProjects: [FocusTask] {
        baseFilteredProjects.filter { $0.isCompleted }
    }

    func toggleDoneCollapsed() {
        isDoneCollapsed.toggle()
    }

    /// Flat display array for a project's expanded content: tasks interleaved with their subtasks and add rows.
    func flattenedProjectItems(for projectId: UUID) -> [ProjectCardDisplayItem] {
        let allTasks = projectTasksMap[projectId] ?? []
        let uncompleted = allTasks.filter { !$0.isCompleted && $0.parentTaskId == nil }.sorted { $0.sortOrder < $1.sortOrder }
        let completed = allTasks.filter { $0.isCompleted && $0.parentTaskId == nil }.sorted { $0.sortOrder < $1.sortOrder }

        var result: [ProjectCardDisplayItem] = []
        for task in uncompleted {
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
        for task in completed {
            result.append(.task(task))
        }
        result.append(.addTaskRow)
        return result
    }

    func clearCompletedProjects() async {
        let completedIds = completedProjects.map { $0.id }
        do {
            for projectId in completedIds {
                try await commitmentRepository.deleteCommitments(forTask: projectId)
                try await repository.deleteTask(id: projectId)
            }
            projects.removeAll { completedIds.contains($0.id) }
            for projectId in completedIds {
                projectTasksMap.removeValue(forKey: projectId)
                expandedProjects.remove(projectId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Project Expansion

    func toggleExpanded(_ projectId: UUID) async {
        if expandedProjects.contains(projectId) {
            expandedProjects.remove(projectId)
        } else {
            expandedProjects.insert(projectId)
            if projectTasksMap[projectId] == nil {
                await fetchProjectTasks(for: projectId)
            }
        }
    }

    func isExpanded(_ projectId: UUID) -> Bool {
        expandedProjects.contains(projectId)
    }

    // MARK: - Task Expansion (within projects)

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

    func fetchProjects() async {
        if projects.isEmpty { isLoading = true }
        errorMessage = nil

        do {
            self.projects = try await repository.fetchProjects()
            self.categories = try await categoryRepository.fetchCategories(type: .project)
            await fetchCommittedTaskIds()

            // Pre-fetch task counts for all projects
            for project in projects {
                await fetchProjectTasks(for: project.id)
            }

            isLoading = false
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }

    func fetchProjectTasks(for projectId: UUID) async {
        guard !isLoadingProjectTasks.contains(projectId) else { return }
        isLoadingProjectTasks.insert(projectId)

        do {
            let allTasks = try await repository.fetchProjectTasks(projectId: projectId)
            // Separate top-level tasks and subtasks
            let topLevelTasks = allTasks.filter { $0.parentTaskId == nil }
            projectTasksMap[projectId] = topLevelTasks

            // Pre-populate subtasksMap
            for task in allTasks where task.parentTaskId != nil {
                subtasksMap[task.parentTaskId!, default: []].append(task)
            }
            // Ensure empty entries for tasks without subtasks
            for task in topLevelTasks {
                if subtasksMap[task.id] == nil {
                    subtasksMap[task.id] = []
                }
            }
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }

        isLoadingProjectTasks.remove(projectId)
    }

    func fetchSubtasks(for taskId: UUID) async {
        guard !isLoadingSubtasks.contains(taskId) else { return }
        isLoadingSubtasks.insert(taskId)

        do {
            let subtasks = try await repository.fetchSubtasks(parentId: taskId)
            subtasksMap[taskId] = subtasks
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }

        isLoadingSubtasks.remove(taskId)
    }

    // MARK: - Progress Calculations

    func taskProgress(for projectId: UUID) -> (completed: Int, total: Int) {
        let tasks = projectTasksMap[projectId] ?? []
        let completed = tasks.filter { $0.isCompleted }.count
        return (completed, tasks.count)
    }

    func subtaskProgress(for projectId: UUID) -> (completed: Int, total: Int) {
        let tasks = projectTasksMap[projectId] ?? []
        var totalSubtasks = 0
        var completedSubtasks = 0

        for task in tasks {
            if let subtasks = subtasksMap[task.id] {
                totalSubtasks += subtasks.count
                completedSubtasks += subtasks.filter { $0.isCompleted }.count
            }
        }

        return (completedSubtasks, totalSubtasks)
    }

    func progressPercentage(for projectId: UUID) -> Double {
        let (completed, total) = taskProgress(for: projectId)
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    // MARK: - Project CRUD

    @discardableResult
    func saveNewProject(title: String, categoryId: UUID?, draftTasks: [DraftTask]) async -> UUID? {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return nil
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return nil }

        do {
            // 1. Create the project
            let project = try await repository.createProject(
                title: trimmedTitle,
                userId: userId,
                categoryId: categoryId
            )

            // 2. Create each task and its subtasks
            for (taskIndex, draftTask) in draftTasks.enumerated() {
                let trimmedTaskTitle = draftTask.title.trimmingCharacters(in: .whitespaces)
                guard !trimmedTaskTitle.isEmpty else { continue }

                let createdTask = try await repository.createProjectTask(
                    title: trimmedTaskTitle,
                    projectId: project.id,
                    userId: userId,
                    sortOrder: taskIndex
                )

                // Create subtasks for this task
                for (subtaskIndex, draftSubtask) in draftTask.subtasks.enumerated() {
                    let trimmedSubtaskTitle = draftSubtask.title.trimmingCharacters(in: .whitespaces)
                    guard !trimmedSubtaskTitle.isEmpty else { continue }

                    let subtask = FocusTask(
                        userId: userId,
                        title: trimmedSubtaskTitle,
                        type: .task,
                        sortOrder: subtaskIndex,
                        projectId: project.id,
                        parentTaskId: createdTask.id
                    )
                    _ = try await repository.createTask(subtask)
                }
            }

            // 3. Refresh projects list
            projects.insert(project, at: 0)
            await fetchProjectTasks(for: project.id)
            return project.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteProject(_ project: FocusTask) async {
        do {
            try await repository.deleteTask(id: project.id)
            projects.removeAll { $0.id == project.id }
            projectTasksMap.removeValue(forKey: project.id)
            expandedProjects.remove(project.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Project Task CRUD

    func createProjectTask(title: String, projectId: UUID) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }

        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        do {
            let task = try await repository.createProjectTask(
                title: trimmed,
                projectId: projectId,
                userId: userId
            )

            if var tasks = projectTasksMap[projectId] {
                tasks.append(task)
                projectTasksMap[projectId] = tasks
            } else {
                projectTasksMap[projectId] = [task]
            }
            subtasksMap[task.id] = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProjectTask(_ task: FocusTask, projectId: UUID) async {
        do {
            try await repository.deleteTask(id: task.id)
            if var tasks = projectTasksMap[projectId] {
                tasks.removeAll { $0.id == task.id }
                projectTasksMap[projectId] = tasks
            }
            subtasksMap.removeValue(forKey: task.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Task Completion

    func toggleTaskCompletion(_ task: FocusTask, projectId: UUID) async {
        do {
            if task.isCompleted {
                // Uncompleting parent - restore previous subtask states
                try await repository.uncompleteTask(id: task.id)

                let currentTask = projectTasksMap[projectId]?.first(where: { $0.id == task.id })
                if let previousStates = currentTask?.previousCompletionState {
                    try await repository.restoreSubtaskStates(parentId: task.id, completionStates: previousStates)
                    await fetchSubtasks(for: task.id)
                }
            } else {
                // Completing parent - save subtask states then complete all
                let subtasks = subtasksMap[task.id] ?? []
                let previousStates = subtasks.map { $0.isCompleted }

                // Save previous states to parent task
                if var tasks = projectTasksMap[projectId],
                   let index = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[index].previousCompletionState = previousStates
                    var updatedTask = tasks[index]
                    updatedTask.previousCompletionState = previousStates
                    try await repository.updateTask(updatedTask)
                    projectTasksMap[projectId] = tasks
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

            // Update local state
            if var tasks = projectTasksMap[projectId],
               let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].isCompleted.toggle()
                if tasks[index].isCompleted {
                    tasks[index].completedDate = Date()
                } else {
                    tasks[index].completedDate = nil
                }
                projectTasksMap[projectId] = tasks

                // Auto-complete/uncomplete project based on task states
                try await checkProjectAutoComplete(projectId: projectId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleSubtaskCompletion(_ subtask: FocusTask, parentId: UUID) async {
        // Capture BEFORE toggle for potential parent auto-complete restore
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

                // Auto-complete parent if all subtasks done
                let allComplete = subtasks.allSatisfy { $0.isCompleted }
                if allComplete && !subtasks.isEmpty {
                    // Find which project this parent belongs to
                    for (projectId, tasks) in projectTasksMap {
                        if let taskIndex = tasks.firstIndex(where: { $0.id == parentId }),
                           !tasks[taskIndex].isCompleted {
                            // Save pre-toggle states for restore on parent uncomplete
                            var updatedTasks = tasks
                            updatedTasks[taskIndex].previousCompletionState = preToggleStates
                            try await repository.updateTask(updatedTasks[taskIndex])
                            try await repository.completeTask(id: parentId)
                            updatedTasks[taskIndex].isCompleted = true
                            updatedTasks[taskIndex].completedDate = Date()
                            projectTasksMap[projectId] = updatedTasks
                            break
                        }
                    }
                } else if !allComplete {
                    // Uncomplete parent if not all subtasks are complete
                    for (projectId, tasks) in projectTasksMap {
                        if let taskIndex = tasks.firstIndex(where: { $0.id == parentId }),
                           tasks[taskIndex].isCompleted {
                            try await repository.uncompleteTask(id: parentId)
                            var updatedTasks = tasks
                            updatedTasks[taskIndex].isCompleted = false
                            updatedTasks[taskIndex].completedDate = nil
                            projectTasksMap[projectId] = updatedTasks
                            break
                        }
                    }
                }

                // Auto-complete/uncomplete project after subtask→task cascade
                if let projectId = projectTasksMap.first(where: { $0.value.contains(where: { $0.id == parentId }) })?.key {
                    try await checkProjectAutoComplete(projectId: projectId)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Project Auto-Complete

    private func checkProjectAutoComplete(projectId: UUID) async throws {
        let tasks = projectTasksMap[projectId] ?? []
        guard !tasks.isEmpty else { return }

        let allTasksComplete = tasks.allSatisfy { $0.isCompleted }

        if allTasksComplete, let projectIndex = projects.firstIndex(where: { $0.id == projectId }),
           !projects[projectIndex].isCompleted {
            // All tasks done → complete the project
            try await repository.completeTask(id: projectId)
            projects[projectIndex].isCompleted = true
            projects[projectIndex].completedDate = Date()
        } else if !allTasksComplete, let projectIndex = projects.firstIndex(where: { $0.id == projectId }),
                  projects[projectIndex].isCompleted {
            // A task was uncompleted → uncomplete the project
            try await repository.uncompleteTask(id: projectId)
            projects[projectIndex].isCompleted = false
            projects[projectIndex].completedDate = nil
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

        // Find the project this parent task belongs to
        let projectId = projectTasksMap.first(where: { $0.value.contains(where: { $0.id == parentId }) })?.key

        do {
            let newSubtask = try await repository.createSubtask(
                title: trimmed,
                parentTaskId: parentId,
                userId: userId,
                projectId: projectId
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

    // MARK: - Edit Mode

    func enterEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditMode = true
            selectedProjectIds = []
            expandedProjects.removeAll()
        }
    }

    func exitEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditMode = false
            selectedProjectIds = []
        }
    }

    func toggleProjectSelection(_ projectId: UUID) {
        if selectedProjectIds.contains(projectId) {
            selectedProjectIds.remove(projectId)
        } else {
            selectedProjectIds.insert(projectId)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func selectAllUncompleted() {
        selectedProjectIds = Set(filteredProjects.map { $0.id })
    }

    func deselectAll() {
        selectedProjectIds = []
    }

    func batchDeleteProjects() async {
        let idsToDelete = selectedProjectIds

        do {
            for projectId in idsToDelete {
                try await commitmentRepository.deleteCommitments(forTask: projectId)
                try await repository.deleteTask(id: projectId)
            }

            projects.removeAll { idsToDelete.contains($0.id) }
            for projectId in idsToDelete {
                projectTasksMap.removeValue(forKey: projectId)
                expandedProjects.remove(projectId)
            }
            exitEditMode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func batchMoveToCategory(_ categoryId: UUID?) async {
        do {
            for projectId in selectedProjectIds {
                if let index = projects.firstIndex(where: { $0.id == projectId }) {
                    var updated = projects[index]
                    updated.categoryId = categoryId
                    updated.modifiedDate = Date()
                    try await repository.updateTask(updated)
                    projects[index].categoryId = categoryId
                    projects[index].modifiedDate = Date()
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
                sortOrder: categories.count,
                type: .project
            )
            let created = try await categoryRepository.createCategory(newCategory)
            categories.append(created)
            selectedCategoryId = created.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Reordering

    func reorderProject(droppedId: UUID, targetId: UUID) {
        guard let updates = ReorderUtility.reorderItems(
            &projects, droppedId: droppedId, targetId: targetId
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

    // MARK: - Project Content Flat Move Handler

    /// Handle .onMove from the flat ForEach inside a project card.
    /// Same pattern as ListsViewModel.handleFlatMove and TaskListViewModel.handleFlatMove.
    func handleProjectContentFlatMove(from source: IndexSet, to destination: Int, projectId: UUID) {
        let flat = flattenedProjectItems(for: projectId)
        guard let fromIdx = source.first else { return }

        // Only task items can be moved
        guard case .task(let movedTask) = flat[fromIdx],
              !movedTask.isCompleted else { return }

        if movedTask.parentTaskId == nil {
            // --- Parent task moved ---
            let parentIndices = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, task: FocusTask)? in
                if case .task(let t) = item, t.parentTaskId == nil, !t.isCompleted { return (i, t) }
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

            guard var allTasks = projectTasksMap[projectId] else { return }
            var uncompleted = allTasks.filter { !$0.isCompleted && $0.parentTaskId == nil }.sorted { $0.sortOrder < $1.sortOrder }

            uncompleted.move(fromOffsets: IndexSet(integer: parentFrom), toOffset: parentTo)

            var updates: [(id: UUID, sortOrder: Int)] = []
            for (index, task) in uncompleted.enumerated() {
                if let mapIndex = allTasks.firstIndex(where: { $0.id == task.id }) {
                    allTasks[mapIndex].sortOrder = index
                }
                updates.append((id: task.id, sortOrder: index))
            }
            projectTasksMap[projectId] = allTasks
            _Concurrency.Task { await persistSortOrders(updates) }

        } else {
            // --- Subtask moved ---
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

    // MARK: - Subtask Helpers

    func getUncompletedSubtasks(for taskId: UUID) -> [FocusTask] {
        (subtasksMap[taskId] ?? []).filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func getCompletedSubtasks(for taskId: UUID) -> [FocusTask] {
        (subtasksMap[taskId] ?? []).filter { $0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - TaskEditingViewModel Conformance

    func findTask(byId id: UUID) -> FocusTask? {
        for tasks in projectTasksMap.values {
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

            // Update local state in projectTasksMap
            if let projectId = task.projectId,
               var tasks = projectTasksMap[projectId],
               let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].title = newTitle
                tasks[index].modifiedDate = Date()
                projectTasksMap[projectId] = tasks
            }

            // Update local state in subtasksMap
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

    func deleteTask(_ task: FocusTask) async {
        guard let projectId = task.projectId else { return }
        await deleteProjectTask(task, projectId: projectId)
    }

    func moveTaskToCategory(_ task: FocusTask, categoryId: UUID?) async {
        do {
            var updated = task
            updated.categoryId = categoryId
            updated.modifiedDate = Date()
            try await repository.updateTask(updated)

            if let projectId = task.projectId,
               var tasks = projectTasksMap[projectId],
               let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].categoryId = categoryId
                tasks[index].modifiedDate = Date()
                projectTasksMap[projectId] = tasks
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
                sortOrder: categories.count,
                type: .project
            )
            let created = try await categoryRepository.createCategory(newCategory)
            categories.append(created)
            await moveTaskToCategory(task, categoryId: created.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Draft Models for Project Creation

struct DraftSubtask: Identifiable {
    let id = UUID()
    var title: String
}

struct DraftTask: Identifiable {
    let id = UUID()
    var title: String
    var subtasks: [DraftSubtask]

    init(title: String = "", subtasks: [DraftSubtask] = []) {
        self.title = title
        self.subtasks = subtasks
    }
}
