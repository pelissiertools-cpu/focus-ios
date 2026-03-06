//
//  HomeViewModel.swift
//  Focus IOS
//

import Foundation
import Combine
import SwiftUI

enum HomeMenuItem: String, CaseIterable, Identifiable, Hashable {
    case today = "Today"
    case assign = "Scheduled"
    case braindump = "Braindump"
    case backlog = "Backlog"
    case archive = "Archive"
    case projects = "Projects"
    case quickLists = "Quick Lists"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .today:      return "sun.max"
        case .assign:     return "calendar"
        case .braindump:  return "brain.head.profile"
        case .backlog:    return "tray"
        case .archive:    return "archivebox"
        case .projects:   return "folder"
        case .quickLists: return "list.bullet"
        }
    }
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var projects: [FocusTask] = []
    @Published var lists: [FocusTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var todayTaskCount: Int = 0

    // Navigation state
    @Published var selectedMenuItem: HomeMenuItem?
    @Published var selectedPinnedItem: FocusTask?
    @Published var categories: [Category] = []
    @Published var selectedCategory: Category?

    var pinnedItems: [FocusTask] {
        (projects + lists).filter { $0.isPinned && !$0.isSection }
    }

    private let repository: TaskRepository
    private let scheduleRepository = ScheduleRepository()
    private let categoryRepository = CategoryRepository()
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.repository = TaskRepository()
        setupNotificationObserver()
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.publisher(for: .projectListChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                _Concurrency.Task { @MainActor in
                    await self.fetchProjects()
                    await self.fetchLists()
                    await self.fetchCategories()
                }
            }
            .store(in: &cancellables)
    }

    func fetchProjects(showLoading: Bool = false) async {
        if showLoading { isLoading = true }
        do {
            projects = try await repository.fetchProjects(isCompleted: false)
        } catch {
            errorMessage = error.localizedDescription
        }
        if showLoading { isLoading = false }
    }

    func fetchLists() async {
        do {
            lists = try await repository.fetchTasks(ofType: .list, isCleared: false, isCompleted: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchCategories() async {
        do {
            categories = try await categoryRepository.fetchCategories()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createCategory(name: String, userId: UUID) async {
        let category = Category(userId: userId, name: name, sortOrder: categories.count)
        do {
            let created = try await categoryRepository.createCategory(category)
            categories.append(created)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameCategory(_ category: Category, newName: String) async {
        var updated = category
        updated.name = newName
        do {
            try await categoryRepository.updateCategory(updated)
            if let index = categories.firstIndex(where: { $0.id == category.id }) {
                categories[index].name = newName
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCategory(id: UUID) async {
        do {
            try await categoryRepository.deleteCategory(id: id)
            categories.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchTodayTaskCount() async {
        do {
            let focus = try await scheduleRepository.fetchSchedules(timeframe: .daily, date: Date(), section: .focus)
            let todo = try await scheduleRepository.fetchSchedules(timeframe: .daily, date: Date(), section: .todo)
            todayTaskCount = focus.count + todo.count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProject(_ project: FocusTask) async {
        do {
            try await repository.deleteTask(id: project.id)
            projects.removeAll { $0.id == project.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteList(_ list: FocusTask) async {
        do {
            try await repository.deleteTask(id: list.id)
            lists.removeAll { $0.id == list.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Pin

    func togglePin(_ task: FocusTask) async {
        let newPinned = !task.isPinned
        do {
            try await repository.togglePin(id: task.id, isPinned: newPinned)
            if task.type == .project {
                if let index = projects.firstIndex(where: { $0.id == task.id }) {
                    projects[index].isPinned = newPinned
                }
            } else {
                if let index = lists.firstIndex(where: { $0.id == task.id }) {
                    lists[index].isPinned = newPinned
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sections

    func createSection(type: TaskType, userId: UUID) async -> FocusTask? {
        do {
            let section = try await repository.createTopLevelSection(title: "", type: type, userId: userId)
            if type == .project {
                projects.append(section)
            } else {
                lists.append(section)
            }
            return section
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func renameSection(_ section: FocusTask, newTitle: String) async {
        var updated = section
        updated.title = newTitle
        updated.modifiedDate = Date()
        do {
            try await repository.updateTask(updated)
            if section.type == .project {
                if let index = projects.firstIndex(where: { $0.id == section.id }) {
                    projects[index] = updated
                }
            } else {
                if let index = lists.firstIndex(where: { $0.id == section.id }) {
                    lists[index] = updated
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSection(_ section: FocusTask) async {
        do {
            try await repository.deleteTask(id: section.id)
            if section.type == .project {
                projects.removeAll { $0.id == section.id }
            } else {
                lists.removeAll { $0.id == section.id }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Reorder

    func reorderProjects(from source: IndexSet, to destination: Int) {
        projects.move(fromOffsets: source, toOffset: destination)
        var updates: [(id: UUID, sortOrder: Int)] = []
        for (index, project) in projects.enumerated() {
            projects[index].sortOrder = index
            updates.append((id: project.id, sortOrder: index))
        }
        _Concurrency.Task { await persistSortOrders(updates) }
    }

    func reorderLists(from source: IndexSet, to destination: Int) {
        lists.move(fromOffsets: source, toOffset: destination)
        var updates: [(id: UUID, sortOrder: Int)] = []
        for (index, list) in lists.enumerated() {
            lists[index].sortOrder = index
            updates.append((id: list.id, sortOrder: index))
        }
        _Concurrency.Task { await persistSortOrders(updates) }
    }

    private func persistSortOrders(_ updates: [(id: UUID, sortOrder: Int)]) async {
        do {
            try await repository.updateSortOrders(updates)
        } catch {
            errorMessage = "Failed to save order: \(error.localizedDescription)"
        }
    }
}
