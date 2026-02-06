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

    private let repository: TaskRepository
    private let authService: AuthService

    nonisolated init(repository: TaskRepository = TaskRepository(), authService: AuthService) {
        self.repository = repository
        self.authService = authService
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

    /// Toggle task completion
    func toggleCompletion(_ task: FocusTask) async {
        do {
            if task.isCompleted {
                try await repository.uncompleteTask(id: task.id)
            } else {
                try await repository.completeTask(id: task.id)
            }

            // Update local state
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

            // Update local state
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].title = newTitle
                tasks[index].modifiedDate = Date()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
