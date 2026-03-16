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
        }
    }
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var projects: [FocusTask] = []
    @Published var lists: [FocusTask] = []
    @Published var pinnedTasks: [FocusTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var todayTaskCount: Int = 0
    @Published var todayCompletedCount: Int = 0
    @Published var mainFocusTasks: [FocusTask] = []

    // Navigation state
    @Published var selectedMenuItem: HomeMenuItem?
    @Published var selectedPinnedItem: FocusTask?
    @Published var categories: [Category] = []
    @Published var selectedCategory: Category?

    @Published var sharedTaskIds: Set<UUID> = []

    // Pinned task subtask support
    @Published var pinnedSubtasksMap: [UUID: [FocusTask]] = [:]
    @Published var expandedPinnedTasks: Set<UUID> = []
    @Published var selectedPinnedTaskForDetails: FocusTask?
    @Published var selectedPinnedTaskForSchedule: FocusTask?

    var pinnedItems: [FocusTask] {
        (projects + lists + pinnedTasks).filter { $0.isPinned && !$0.isSection }
    }

    private let repository: TaskRepository
    private let scheduleRepository = ScheduleRepository()
    private let categoryRepository = CategoryRepository()
    private let shareRepository = ShareRepository()
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.repository = TaskRepository()

        // Pre-populate from cache so first render shows progress card instantly
        let cache = AppDataCache.shared
        if cache.hasLoadedTodayProgress {
            todayTaskCount = cache.todayTaskCount
            todayCompletedCount = cache.todayCompletedCount
            mainFocusTasks = cache.mainFocusTasks
        }

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
                    await self.fetchSharedTaskIds()
                    await self.fetchProjects()
                    await self.fetchLists()
                    await self.fetchPinnedTasks()
                    await self.fetchCategories()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .taskCompletionChanged)
            .merge(with: NotificationCenter.default.publisher(for: .schedulesChanged))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                // Optimistically adjust completed count for instant feedback
                if notification.name == .taskCompletionChanged,
                   let isCompleted = notification.userInfo?[TaskNotificationKeys.isCompleted] as? Bool {
                    if isCompleted {
                        self.todayCompletedCount = min(self.todayCompletedCount + 1, self.todayTaskCount)
                    } else {
                        self.todayCompletedCount = max(self.todayCompletedCount - 1, 0)
                    }
                    self.updateProgressCache()
                }
                _Concurrency.Task { @MainActor in
                    await self.fetchTodayProgress()
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
            var fetched = try await repository.fetchProjects(isCleared: false, isCompleted: false)

            // Merge shared projects via SECURITY DEFINER RPC (bypasses tasks RLS)
            let fetchedIds = Set(fetched.map(\.id))
            let sharedTasks = try await repository.fetchSharedTasks()
            let sharedProjects = sharedTasks.filter { $0.type == .project && !$0.isCleared && !$0.isCompleted && !fetchedIds.contains($0.id) }
            fetched.append(contentsOf: sharedProjects)

            projects = fetched
        } catch {
            errorMessage = error.localizedDescription
        }
        if showLoading { isLoading = false }
    }

    func fetchLists() async {
        do {
            var fetched = try await repository.fetchTasks(ofType: .list, isCleared: false, isCompleted: false)

            // Merge shared lists via SECURITY DEFINER RPC (bypasses tasks RLS)
            let fetchedListIds = Set(fetched.map(\.id))
            let sharedListTasks = try await repository.fetchSharedTasks()
            let sharedLists = sharedListTasks.filter { $0.type == .list && !$0.isCleared && !$0.isCompleted && !fetchedListIds.contains($0.id) }
            fetched.append(contentsOf: sharedLists)

            lists = fetched
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchPinnedTasks() async {
        do {
            pinnedTasks = try await repository.fetchPinnedTasks()
            // Pre-fetch subtask counts for pinned tasks
            let taskIds = pinnedTasks.map(\.id)
            if !taskIds.isEmpty {
                let subtasksByParent = try await repository.fetchSubtasksByParentIds(taskIds)
                for (parentId, subtasks) in subtasksByParent {
                    pinnedSubtasksMap[parentId] = subtasks
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchSharedTaskIds() async {
        do {
            sharedTaskIds = try await shareRepository.fetchSharedTaskIds()
        } catch {
            // Silently handled — icon just won't show
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

    /// Combined fetch for progress count + focus tasks (shares schedule data, single pass)
    func fetchTodayProgress() async {
        do {
            // Parallel schedule fetches (was 3 sequential calls before)
            async let focusResult = scheduleRepository.fetchSchedules(timeframe: .daily, date: Date(), section: .focus)
            async let todoResult = scheduleRepository.fetchSchedules(timeframe: .daily, date: Date(), section: .todo)
            let (focus, todo) = try await (focusResult, todoResult)

            let allSchedules = focus + todo
            todayTaskCount = allSchedules.count

            let allTaskIds = Array(Set(allSchedules.map(\.taskId)))
            guard !allTaskIds.isEmpty else {
                todayCompletedCount = 0
                mainFocusTasks = []
                AppDataCache.shared.mainFocusTasks = []
                updateProgressCache()
                return
            }

            // Single tasks fetch for both progress count and focus task list
            let tasks = try await repository.fetchTasksByIds(allTaskIds)
            let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

            // Update completed count
            todayCompletedCount = allSchedules.filter { taskMap[$0.taskId]?.isCompleted == true }.count
            updateProgressCache()

            // Update main focus tasks
            let focusTaskIds = focus.sorted(by: { $0.sortOrder < $1.sortOrder }).map(\.taskId)
            mainFocusTasks = focusTaskIds.compactMap { taskMap[$0] }.filter { !$0.isCompleted }
            AppDataCache.shared.mainFocusTasks = mainFocusTasks

            // Pre-fetch subtasks for focus tasks
            let focusTaskOnlyIds = mainFocusTasks.filter { $0.type == .task }.map(\.id)
            if !focusTaskOnlyIds.isEmpty {
                let subtasksByParent = try await repository.fetchSubtasksByParentIds(focusTaskOnlyIds)
                for (parentId, subtasks) in subtasksByParent {
                    pinnedSubtasksMap[parentId] = subtasks
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateProgressCache() {
        let cache = AppDataCache.shared
        cache.todayTaskCount = todayTaskCount
        cache.todayCompletedCount = todayCompletedCount
        cache.hasLoadedTodayProgress = true
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

    // MARK: - Pin

    func togglePin(_ task: FocusTask) async {
        let newPinned = !task.isPinned
        do {
            try await repository.togglePin(id: task.id, isPinned: newPinned)
            if task.type == .project {
                if let index = projects.firstIndex(where: { $0.id == task.id }) {
                    projects[index].isPinned = newPinned
                }
            } else if task.type == .list {
                if let index = lists.firstIndex(where: { $0.id == task.id }) {
                    lists[index].isPinned = newPinned
                }
            } else {
                // Task type — add/remove from pinnedTasks
                if newPinned {
                    var pinned = task
                    pinned.isPinned = true
                    pinnedTasks.append(pinned)
                } else {
                    pinnedTasks.removeAll { $0.id == task.id }
                }
            }
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePinnedTaskCompletion(_ task: FocusTask) async {
        do {
            if task.isCompleted {
                try await repository.uncompleteTask(id: task.id)
            } else {
                try await repository.completeTask(id: task.id)
            }
            if let index = pinnedTasks.firstIndex(where: { $0.id == task.id }) {
                pinnedTasks[index].isCompleted = !task.isCompleted
            }
            // Also check subtasks
            for (parentId, subtasks) in pinnedSubtasksMap {
                if let index = subtasks.firstIndex(where: { $0.id == task.id }) {
                    pinnedSubtasksMap[parentId]?[index].isCompleted = !task.isCompleted
                }
            }
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Pinned Task Subtasks

    func togglePinnedTaskExpanded(_ taskId: UUID) async {
        if expandedPinnedTasks.contains(taskId) {
            expandedPinnedTasks.remove(taskId)
        } else {
            expandedPinnedTasks.insert(taskId)
            if pinnedSubtasksMap[taskId] == nil {
                await fetchPinnedSubtasks(for: taskId)
            }
        }
    }

    func fetchPinnedSubtasks(for taskId: UUID) async {
        do {
            let subtasks = try await repository.fetchSubtasks(parentId: taskId)
            pinnedSubtasksMap[taskId] = subtasks
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func getUncompletedPinnedSubtasks(for taskId: UUID) -> [FocusTask] {
        (pinnedSubtasksMap[taskId] ?? []).filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func getCompletedPinnedSubtasks(for taskId: UUID) -> [FocusTask] {
        (pinnedSubtasksMap[taskId] ?? []).filter { $0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func deletePinnedTask(_ task: FocusTask) async {
        do {
            try await repository.deleteTask(id: task.id)
            pinnedTasks.removeAll { $0.id == task.id }
            // Also remove from subtasks if it's a subtask
            for (parentId, subtasks) in pinnedSubtasksMap {
                if subtasks.contains(where: { $0.id == task.id }) {
                    pinnedSubtasksMap[parentId]?.removeAll { $0.id == task.id }
                }
            }
            pinnedSubtasksMap.removeValue(forKey: task.id)
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
