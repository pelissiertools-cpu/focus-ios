//
//  HomeViewModel.swift
//  Focus IOS
//

import Foundation
import Combine
import SwiftUI

enum HomeMenuItem: String, CaseIterable, Identifiable, Hashable {
    case today = "Today"
    case assign = "Upcoming"
    case inbox = "Inbox"
    case backlog = "Backlog"
    case archive = "Archive"
    case projects = "Projects"
    case quickLists = "Quick Lists"
    case goals = "Goals"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .today:      return "sun.max"
        case .assign:     return "calendar"
        case .inbox:      return "tray.and.arrow.down"
        case .backlog:    return "tray"
        case .archive:    return "archivebox"
        case .projects:   return "folder"
        case .quickLists: return "checklist"
        case .goals:      return "target"
        }
    }
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var projects: [FocusTask] = []
    @Published var lists: [FocusTask] = []
    @Published var goals: [FocusTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var todayTaskCount: Int = 0
    @Published var mainFocusTasks: [FocusTask] = []

    // Navigation state
    @Published var selectedMenuItem: HomeMenuItem?
    @Published var selectedPinnedItem: FocusTask?
    @Published var categories: [Category] = []
    @Published var selectedCategory: Category?

    var pinnedItems: [FocusTask] {
        (projects + lists + goals).filter { $0.isPinned && !$0.isSection }
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
            .sink { [weak self] notification in
                guard let self else { return }
                if notification.object as AnyObject? === self { return }
                if notification.object == nil,
                   LocalMutationTracker.isRecentlyMutated() { return }
                _Concurrency.Task { @MainActor in
                    await self.fetchProjects()
                    await self.fetchLists()
                    await self.fetchGoals()
                    await self.fetchCategories()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .notificationTappedNavigateToday)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.navigateToToday()
            }
            .store(in: &cancellables)

        // Handle cold-start: notification tapped before this VM existed
        if AppDelegate.pendingNavigateToToday {
            AppDelegate.pendingNavigateToToday = false
            selectedMenuItem = .today
        }
    }

    private func navigateToToday() {
        AppDelegate.pendingNavigateToToday = false
        selectedMenuItem = .today
    }

    func fetchProjects(showLoading: Bool = false) async {
        if showLoading { isLoading = true }
        do {
            projects = try await repository.fetchProjects(isCleared: false, isCompleted: false)
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

    func fetchGoals() async {
        do {
            goals = try await repository.fetchGoals(isCompleted: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchCategories() async {
        do {
            let allCategories = try await categoryRepository.fetchCategories()
            categories = allCategories.filter { !$0.isSystem }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createCategory(name: String, userId: UUID) async {
        let category = Category(userId: userId, name: name, sortOrder: categories.count)
        do {
            let created = try await categoryRepository.createCategory(category)
            categories.append(created)
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameCategory(_ category: Category, newName: String) async {
        guard !category.isSystem else { return }
        var updated = category
        updated.name = newName
        do {
            try await categoryRepository.updateCategory(updated)
            if let index = categories.firstIndex(where: { $0.id == category.id }) {
                categories[index].name = newName
            }
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCategory(id: UUID) async {
        do {
            try await categoryRepository.deleteCategory(id: id)
            categories.removeAll { $0.id == id }
            notifyTasksChanged()
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

    func fetchMainFocusTasks() async {
        do {
            let focusSchedules = try await scheduleRepository.fetchSchedules(timeframe: .daily, date: Date(), section: .focus)
            let taskIds = focusSchedules.sorted(by: { $0.sortOrder < $1.sortOrder }).map(\.taskId)
            guard !taskIds.isEmpty else {
                mainFocusTasks = []
                return
            }
            let tasks = try await repository.fetchTasksByIds(taskIds)
            // Preserve schedule sort order and exclude completed
            let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
            mainFocusTasks = taskIds.compactMap { taskMap[$0] }.filter { !$0.isCompleted }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProject(_ project: FocusTask) async {
        do {
            try await repository.deleteTask(id: project.id)
            projects.removeAll { $0.id == project.id }
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteList(_ list: FocusTask) async {
        do {
            try await repository.deleteTask(id: list.id)
            lists.removeAll { $0.id == list.id }
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteGoal(_ goal: FocusTask) async {
        do {
            try await repository.deleteTask(id: goal.id)
            goals.removeAll { $0.id == goal.id }
            notifyTasksChanged()
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
            } else if task.type == .goal {
                if let index = goals.firstIndex(where: { $0.id == task.id }) {
                    goals[index].isPinned = newPinned
                }
            } else {
                if let index = lists.firstIndex(where: { $0.id == task.id }) {
                    lists[index].isPinned = newPinned
                }
            }
            notifyTasksChanged()
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
            } else if type == .goal {
                goals.append(section)
            } else {
                lists.append(section)
            }
            notifyTasksChanged()
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
            } else if section.type == .goal {
                if let index = goals.firstIndex(where: { $0.id == section.id }) {
                    goals[index] = updated
                }
            } else {
                if let index = lists.firstIndex(where: { $0.id == section.id }) {
                    lists[index] = updated
                }
            }
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSection(_ section: FocusTask) async {
        do {
            try await repository.deleteTask(id: section.id)
            if section.type == .project {
                projects.removeAll { $0.id == section.id }
            } else if section.type == .goal {
                goals.removeAll { $0.id == section.id }
            } else {
                lists.removeAll { $0.id == section.id }
            }
            notifyTasksChanged()
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
        notifyTasksChanged()
        _Concurrency.Task { await persistSortOrders(updates) }
    }

    func reorderGoals(from source: IndexSet, to destination: Int) {
        goals.move(fromOffsets: source, toOffset: destination)
        var updates: [(id: UUID, sortOrder: Int)] = []
        for (index, goal) in goals.enumerated() {
            goals[index].sortOrder = index
            updates.append((id: goal.id, sortOrder: index))
        }
        notifyTasksChanged()
        _Concurrency.Task { await persistSortOrders(updates) }
    }

    func reorderLists(from source: IndexSet, to destination: Int) {
        lists.move(fromOffsets: source, toOffset: destination)
        var updates: [(id: UUID, sortOrder: Int)] = []
        for (index, list) in lists.enumerated() {
            lists[index].sortOrder = index
            updates.append((id: list.id, sortOrder: index))
        }
        notifyTasksChanged()
        _Concurrency.Task { await persistSortOrders(updates) }
    }

    private func persistSortOrders(_ updates: [(id: UUID, sortOrder: Int)]) async {
        do {
            try await repository.updateSortOrders(updates)
        } catch {
            errorMessage = "Failed to save order: \(error.localizedDescription)"
        }
    }

    private func notifyTasksChanged() {
        LocalMutationTracker.markMutation()
        NotificationCenter.default.post(name: .projectListChanged, object: self)
    }
}
