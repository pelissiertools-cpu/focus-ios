//
//  ProjectsViewModel.swift
//  Focus IOS
//

import Foundation
import Combine
import SwiftUI
import Auth

@MainActor
class ProjectsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var projects: [FocusTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingAddProject = false
    @Published var selectedProjectForDetails: FocusTask?

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

    // Search
    @Published var searchText: String = ""

    private let repository: TaskRepository
    private let categoryRepository: CategoryRepository
    let authService: AuthService

    init(repository: TaskRepository = TaskRepository(),
         categoryRepository: CategoryRepository = CategoryRepository(),
         authService: AuthService) {
        self.repository = repository
        self.categoryRepository = categoryRepository
        self.authService = authService
    }

    // MARK: - Computed Properties

    var filteredProjects: [FocusTask] {
        var filtered = projects
        if let categoryId = selectedCategoryId {
            filtered = filtered.filter { $0.categoryId == categoryId }
        }
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
        }
        return filtered.sorted { $0.sortOrder < $1.sortOrder }
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
        isLoading = true
        errorMessage = nil

        do {
            self.projects = try await repository.fetchProjects()
            self.categories = try await categoryRepository.fetchCategories(type: "project")

            // Pre-fetch task counts for all projects
            for project in projects {
                await fetchProjectTasks(for: project.id)
            }

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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

    func saveNewProject(title: String, categoryId: UUID?, draftTasks: [DraftTask]) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

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
            showingAddProject = false
        } catch {
            errorMessage = error.localizedDescription
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
                try await repository.uncompleteTask(id: task.id)
            } else {
                try await repository.completeTask(id: task.id)
                // Also complete all subtasks
                let subtasks = subtasksMap[task.id] ?? []
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
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleSubtaskCompletion(_ subtask: FocusTask, parentId: UUID) async {
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
                            try await repository.completeTask(id: parentId)
                            var updatedTasks = tasks
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
            }
        } catch {
            errorMessage = error.localizedDescription
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

    // MARK: - Category

    func selectCategory(_ categoryId: UUID?) {
        selectedCategoryId = categoryId
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
                sortOrder: categories.count,
                type: "project"
            )
            let created = try await categoryRepository.createCategory(newCategory)
            categories.append(created)
            selectedCategoryId = created.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Subtask Helpers

    func getUncompletedSubtasks(for taskId: UUID) -> [FocusTask] {
        (subtasksMap[taskId] ?? []).filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func getCompletedSubtasks(for taskId: UUID) -> [FocusTask] {
        (subtasksMap[taskId] ?? []).filter { $0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
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
