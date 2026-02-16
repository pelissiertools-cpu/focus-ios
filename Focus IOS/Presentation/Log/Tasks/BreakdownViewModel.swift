//
//  BreakdownViewModel.swift
//  Focus IOS
//

import Foundation
import Combine
import SwiftUI

struct SubtaskSuggestion: Identifiable {
    let id: UUID
    var title: String
    var isAISuggested: Bool
}

@MainActor
class BreakdownViewModel: ObservableObject {
    @Published var suggestions: [SubtaskSuggestion] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSaving = false

    let parentTask: FocusTask
    private let aiService: AIService
    private let taskRepository: TaskRepository
    private let userId: UUID
    private var existingSubtaskTitles: [String] = []

    init(parentTask: FocusTask, userId: UUID) {
        self.parentTask = parentTask
        self.userId = userId
        self.aiService = AIService()
        self.taskRepository = TaskRepository()
    }

    func loadExistingSubtasks() async {
        do {
            let subtasks = try await taskRepository.fetchSubtasks(parentId: parentTask.id)
            existingSubtaskTitles = subtasks.map { $0.title }
        } catch {
            // Non-fatal — AI just won't know about existing subtasks
        }
    }

    func generateSuggestions() async {
        isLoading = true
        errorMessage = nil

        do {
            // Combine DB subtasks + current suggestions so AI avoids all of them
            let allExisting = existingSubtaskTitles + suggestions.map { $0.title }
            let subtaskTitles = try await aiService.generateSubtasks(
                title: parentTask.title,
                description: parentTask.description,
                existingSubtasks: allExisting.isEmpty ? nil : allExisting
            )
            suggestions = subtaskTitles.map {
                SubtaskSuggestion(id: UUID(), title: $0, isAISuggested: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func removeSuggestion(_ suggestion: SubtaskSuggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
    }

    func addManualSubtask(title: String) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        suggestions.append(SubtaskSuggestion(id: UUID(), title: title, isAISuggested: false))
    }

    func updateSuggestion(_ suggestion: SubtaskSuggestion, newTitle: String) {
        guard let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
        suggestions[index].title = newTitle
    }

    func moveSuggestion(from source: IndexSet, to destination: Int) {
        suggestions.move(fromOffsets: source, toOffset: destination)
    }

    func saveSubtasks() async -> Bool {
        isSaving = true
        do {
            for suggestion in suggestions {
                let trimmed = suggestion.title.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                _ = try await taskRepository.createSubtask(
                    title: trimmed,
                    parentTaskId: parentTask.id,
                    userId: userId
                )
            }
            isSaving = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return false
        }
    }
}
