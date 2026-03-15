//
//  ListsViewModel.swift
//  Focus IOS
//

import Foundation
import Combine
import SwiftUI
import Auth

// MARK: - Flat List Display Item

enum FlatListDisplayItem: Identifiable {
    case list(FocusTask)
    case item(FocusTask, listId: UUID)
    case addItemRow(listId: UUID)
    case doneSection(listId: UUID)

    var id: String {
        switch self {
        case .list(let list): return list.id.uuidString
        case .item(let item, _): return item.id.uuidString
        case .addItemRow(let listId): return "add-\(listId.uuidString)"
        case .doneSection(let listId): return "done-\(listId.uuidString)"
        }
    }
}

@MainActor
class ListsViewModel: ObservableObject, LogFilterable, TaskEditingViewModel {
    // MARK: - Published Properties

    // Lists data
    @Published var lists: [FocusTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Items state management (items = subtasks of a list)
    @Published var itemsMap: [UUID: [FocusTask]] = [:]
    var subtasksMap: [UUID: [FocusTask]] { itemsMap }
    @Published var expandedLists: Set<UUID> = []
    @Published var isLoadingItems: Set<UUID> = []

    // Done subsection state per list
    @Published var doneSectionCollapsed: [UUID: Bool] = [:]

    // Detail drawers
    @Published var selectedListForDetails: FocusTask?
    @Published var selectedItemForDetails: FocusTask?
    @Published var selectedItemForSchedule: FocusTask?

    // Category filter
    @Published var categories: [Category] = []
    @Published var selectedCategoryId: UUID? = nil

    // Schedule filter & due dates
    @Published var scheduleFilter: ScheduleFilter? = nil
    @Published var scheduledTaskIds: Set<UUID> = []
    @Published var taskDueDates: [UUID: Date] = [:]
    @Published var taskScheduleDates: [UUID: Date] = [:]
    @Published var sharedTaskIds: Set<UUID> = []

    // Edit mode
    @Published var isEditMode: Bool = false
    @Published var selectedListIds: Set<UUID> = []

    // Batch operation triggers
    @Published var showBatchDeleteConfirmation: Bool = false
    @Published var showBatchMovePicker: Bool = false
    @Published var showBatchScheduleSheet: Bool = false

    // Content edit mode (items within a list)
    @Published var contentEditMode: Bool = false
    @Published var selectedContentItemIds: Set<UUID> = []
    @Published var showContentBatchDeleteConfirmation: Bool = false
    @Published var showContentBatchMovePicker: Bool = false
    @Published var showContentBatchScheduleSheet: Bool = false

    // Add list
    @Published var showingAddList: Bool = false

    // Search
    @Published var searchText: String = ""

    // Sort
    @Published var sortOption: SortOption = .creationDate
    @Published var sortDirection: SortDirection = .lowestFirst

    // Pending completion grace period
    let pendingCompletion = PendingCompletionManager()
    @Published var pendingCompletionTaskIds: Set<UUID> = []

    private let repository: TaskRepository
    private let categoryRepository: CategoryRepository
    let scheduleRepository: ScheduleRepository
    let shareRepository: ShareRepository
    let authService: AuthService
    private var cancellables = Set<AnyCancellable>()

    init(repository: TaskRepository = TaskRepository(),
         categoryRepository: CategoryRepository = CategoryRepository(),
         scheduleRepository: ScheduleRepository = ScheduleRepository(),
         shareRepository: ShareRepository = ShareRepository(),
         authService: AuthService) {
        self.repository = repository
        self.categoryRepository = categoryRepository
        self.scheduleRepository = scheduleRepository
        self.shareRepository = shareRepository
        self.authService = authService

        // Pre-populate from cache for instant display
        let cache = AppDataCache.shared
        if cache.hasLoadedLists {
            self.lists = cache.lists
        }
        if cache.hasLoadedCategories {
            self.categories = cache.categories
        }

        pendingCompletion.onChange = { [weak self] in
            self?.pendingCompletionTaskIds = self?.pendingCompletion.pendingIds ?? []
        }

        setupNotificationObserver()
    }

    deinit {
        let manager = pendingCompletion
        MainActor.assumeIsolated {
            manager.flushAll()
        }
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
            .sink { [weak self] notification in
                guard let self else { return }
                if notification.object as AnyObject? === self { return }
                if notification.object == nil,
                   LocalMutationTracker.isRecentlyMutated() { return }
                _Concurrency.Task { @MainActor in
                    await self.fetchLists()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .schedulesChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                if notification.object as AnyObject? === self { return }
                if notification.object == nil,
                   LocalMutationTracker.isRecentlyMutated() { return }
                _Concurrency.Task { @MainActor in
                    await self.fetchScheduledTaskIds()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sharedItemsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                _Concurrency.Task { @MainActor in
                    await self.fetchSharedTaskIds()
                }
            }
            .store(in: &cancellables)
    }

    private func notifyTasksChanged() {
        LocalMutationTracker.markMutation()
        NotificationCenter.default.post(name: .projectListChanged, object: self)
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

        // Update lists array if this list was completed/uncompleted
        if let index = lists.firstIndex(where: { $0.id == taskId }) {
            lists[index].isCompleted = isCompleted
            lists[index].completedDate = completedDate
        }

        // Update itemsMap if this is a list item
        for (listId, var items) in itemsMap {
            if let index = items.firstIndex(where: { $0.id == taskId }) {
                items[index].isCompleted = isCompleted
                items[index].completedDate = completedDate
                itemsMap[listId] = items
                break
            }
        }
    }

    // MARK: - LogFilterable Conformance

    var showingAddItem: Bool {
        get { showingAddList }
        set { showingAddList = newValue }
    }

    var selectedItemIds: Set<UUID> {
        get { selectedListIds }
        set { selectedListIds = newValue }
    }

    var selectedCount: Int { selectedListIds.count }

    var allUncompletedSelected: Bool {
        let allIds = Set(filteredLists.map { $0.id })
        return !allIds.isEmpty && allIds.isSubset(of: selectedListIds)
    }

    var selectedItems: [FocusTask] {
        lists.filter { selectedListIds.contains($0.id) }
    }

    func createCategory(name: String) async {
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
            for i in lists.indices {
                if let catId = lists[i].categoryId, ids.contains(catId) {
                    lists[i].categoryId = nil
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
            for i in lists.indices {
                if let catId = lists[i].categoryId, sourceIds.contains(catId) {
                    lists[i].categoryId = target.id
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

    // MARK: - Computed Properties

    var filteredLists: [FocusTask] {
        var filtered = lists
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
        return applySorting(to: filtered)
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
                let dateA = taskDueDates[a.id]
                let dateB = taskDueDates[b.id]
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

    /// Flat display array: lists interleaved with their expanded items, done sections, and add rows.
    var flattenedDisplayItems: [FlatListDisplayItem] {
        var result: [FlatListDisplayItem] = []
        for list in filteredLists {
            result.append(.list(list))
            if expandedLists.contains(list.id) {
                for item in getUncompletedItems(for: list.id) {
                    result.append(.item(item, listId: list.id))
                }
                result.append(.addItemRow(listId: list.id))
                if !getCompletedItems(for: list.id).isEmpty {
                    result.append(.doneSection(listId: list.id))
                }
            }
        }
        return result
    }

    // MARK: - Data Fetching

    func fetchLists() async {
        if lists.isEmpty { isLoading = true }
        errorMessage = nil

        do {
            let fetchedLists = try await repository.fetchTasks(ofType: .list, isCleared: false)
            self.lists = fetchedLists
            self.categories = try await categoryRepository.fetchCategories()
            await fetchScheduledTaskIds()
            await fetchSharedTaskIds()

            // Update cache
            let cache = AppDataCache.shared
            cache.lists = fetchedLists
            cache.hasLoadedLists = true

            // Pre-fetch items for all lists
            for list in lists {
                await fetchItems(for: list.id)
            }

            isLoading = false
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
            isLoading = false
        }
    }

    func fetchItems(for listId: UUID) async {
        guard !isLoadingItems.contains(listId) else { return }
        isLoadingItems.insert(listId)

        do {
            let items = try await repository.fetchSubtasks(parentId: listId)
            itemsMap[listId] = items.filter { !$0.isCleared }
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }

        isLoadingItems.remove(listId)
    }

    func fetchCategories() async {
        do {
            self.categories = try await categoryRepository.fetchCategories()
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    // MARK: - Expansion

    func toggleExpanded(_ listId: UUID) async {
        if expandedLists.contains(listId) {
            expandedLists.remove(listId)
        } else {
            expandedLists.insert(listId)
            if itemsMap[listId] == nil {
                await fetchItems(for: listId)
            }
        }
    }

    func isExpanded(_ listId: UUID) -> Bool {
        expandedLists.contains(listId)
    }

    // MARK: - Item Helpers

    func getUncompletedItems(for listId: UUID) -> [FocusTask] {
        (itemsMap[listId] ?? []).filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func getCompletedItems(for listId: UUID) -> [FocusTask] {
        (itemsMap[listId] ?? []).filter { $0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func isDoneSectionCollapsed(for listId: UUID) -> Bool {
        doneSectionCollapsed[listId] ?? true
    }

    func toggleDoneSectionCollapsed(for listId: UUID) {
        doneSectionCollapsed[listId] = !(doneSectionCollapsed[listId] ?? true)
    }

    // MARK: - Pending Completion (Grace Period)

    func requestToggleItemCompletion(_ item: FocusTask, listId: UUID) {
        if item.isCompleted {
            _Concurrency.Task { await toggleItemCompletion(item, listId: listId) }
            return
        }

        let itemId = item.id
        let repo = repository
        pendingCompletion.scheduleCompletion(for: itemId, action: { [weak self] in
            guard let self,
                  let items = self.itemsMap[listId],
                  let currentItem = items.first(where: { $0.id == itemId }),
                  !currentItem.isCompleted else { return false }
            await self.toggleItemCompletion(currentItem, listId: listId)
            return true
        }, fallback: {
            try? await repo.completeTask(id: itemId)
        })
    }

    func cancelPendingCompletion(_ taskId: UUID) {
        pendingCompletion.cancel(taskId)
    }

    func isPendingCompletion(_ taskId: UUID) -> Bool {
        pendingCompletion.isPending(taskId)
    }

    // MARK: - Item Completion (NO parent auto-complete — lists are never "completed")

    func toggleItemCompletion(_ item: FocusTask, listId: UUID) async {
        do {
            if item.isCompleted {
                try await repository.uncompleteTask(id: item.id)
            } else {
                try await repository.completeTask(id: item.id)
            }

            if var items = itemsMap[listId],
               let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isCompleted.toggle()
                if items[index].isCompleted {
                    items[index].completedDate = Date()
                } else {
                    items[index].completedDate = nil
                }
                itemsMap[listId] = items

                // Reset done section to collapsed when no completed items remain
                if items.filter({ $0.isCompleted }).isEmpty {
                    doneSectionCollapsed.removeValue(forKey: listId)
                }

                // Notify other views about item completion change
                NotificationCenter.default.post(
                    name: .taskCompletionChanged,
                    object: nil,
                    userInfo: [
                        TaskNotificationKeys.taskId: item.id,
                        TaskNotificationKeys.isCompleted: items[index].isCompleted,
                        TaskNotificationKeys.completedDate: items[index].completedDate as Any,
                        TaskNotificationKeys.source: TaskNotificationSource.log.rawValue,
                        TaskNotificationKeys.subtasksChanged: false
                    ]
                )
                notifyTasksChanged()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - List CRUD

    func createList(title: String, categoryId: UUID? = nil, priority: Priority = .low) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        do {
            let newList = FocusTask(
                userId: userId,
                title: trimmed,
                type: .list,
                isCompleted: false,
                sortOrder: 0,
                priority: priority,
                categoryId: categoryId
            )
            let created = try await repository.createTask(newList)
            lists.insert(created, at: 0)
            itemsMap[created.id] = []

            // Reassign sort orders
            let sorted = lists.sorted { $0.sortOrder < $1.sortOrder }
            var updates: [(id: UUID, sortOrder: Int)] = []
            for (index, list) in sorted.enumerated() {
                if let listIndex = lists.firstIndex(where: { $0.id == list.id }) {
                    lists[listIndex].sortOrder = index
                }
                updates.append((id: list.id, sortOrder: index))
            }
            await persistSortOrders(updates)
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteList(_ list: FocusTask) async {
        do {
            // Delete all items under this list first
            let items = itemsMap[list.id] ?? []
            for item in items {
                try await scheduleRepository.deleteSchedules(forTask: item.id)
                try await repository.deleteTask(id: item.id)
            }
            // Delete schedules and the list itself
            try await scheduleRepository.deleteSchedules(forTask: list.id)
            try await repository.deleteTask(id: list.id)

            lists.removeAll { $0.id == list.id }
            itemsMap.removeValue(forKey: list.id)
            expandedLists.remove(list.id)
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Item CRUD

    func createItem(title: String, listId: UUID) async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "No authenticated user"
            return
        }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        do {
            let newItem = try await repository.createSubtask(
                title: trimmed,
                parentTaskId: listId,
                userId: userId
            )

            if var items = itemsMap[listId] {
                items.append(newItem)
                itemsMap[listId] = items
            } else {
                itemsMap[listId] = [newItem]
            }
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePin(_ item: FocusTask, listId: UUID) async {
        let newPinned = !item.isPinned
        do {
            try await repository.togglePin(id: item.id, isPinned: newPinned)
            if var items = itemsMap[listId] {
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].isPinned = newPinned
                    itemsMap[listId] = items
                }
            }
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteItem(_ item: FocusTask, listId: UUID) async {
        do {
            try await scheduleRepository.deleteSchedules(forTask: item.id)
            try await repository.deleteTask(id: item.id)

            if var items = itemsMap[listId] {
                items.removeAll { $0.id == item.id }
                itemsMap[listId] = items
            }
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Clear Done

    /// Clear completed items from a list (soft-delete — still visible in Archive)
    func clearCompletedItems(for listId: UUID) async {
        guard let items = itemsMap[listId] else { return }
        let completedIds = Set(items.filter { $0.isCompleted }.map { $0.id })
        guard !completedIds.isEmpty else { return }

        do {
            try await repository.clearTasks(ids: completedIds)
            itemsMap[listId] = items.filter { !completedIds.contains($0.id) }
            doneSectionCollapsed.removeValue(forKey: listId)
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Reordering

    private func persistSortOrders(_ updates: [(id: UUID, sortOrder: Int)]) async {
        do {
            try await repository.updateSortOrders(updates)
        } catch {
            errorMessage = "Failed to save order: \(error.localizedDescription)"
        }
    }

    // MARK: - Flat List Move Handler

    func handleFlatMove(from source: IndexSet, to destination: Int) {
        let flat = flattenedDisplayItems
        guard let fromIdx = source.first else { return }

        switch flat[fromIdx] {
        case .list(let movedList):
            // --- Parent list moved ---
            let listIndices = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, list: FocusTask)? in
                if case .list(let l) = item { return (i, l) }
                return nil
            }

            guard let listFrom = listIndices.firstIndex(where: { $0.list.id == movedList.id }) else { return }

            var listTo = listIndices.count
            for (li, entry) in listIndices.enumerated() {
                if destination <= entry.flatIdx {
                    listTo = li
                    break
                }
            }
            if listTo > listFrom { listTo = min(listTo, listIndices.count) }

            guard listFrom != listTo && listFrom + 1 != listTo else { return }

            var ordered = filteredLists
            ordered.move(fromOffsets: IndexSet(integer: listFrom), toOffset: listTo)

            var updates: [(id: UUID, sortOrder: Int)] = []
            for (index, list) in ordered.enumerated() {
                if let masterIdx = lists.firstIndex(where: { $0.id == list.id }) {
                    lists[masterIdx].sortOrder = index
                }
                updates.append((id: list.id, sortOrder: index))
            }
            _Concurrency.Task { await persistSortOrders(updates) }

        case .item(let movedItem, let listId):
            guard !movedItem.isCompleted else { return }

            guard let parentFlatIdx = flat.firstIndex(where: {
                if case .list(let l) = $0 { return l.id == listId }
                return false
            }) else { return }

            let sectionEnd = flat[(parentFlatIdx + 1)...].firstIndex(where: {
                if case .list(_) = $0 { return true }
                return false
            }) ?? flat.count

            guard destination > parentFlatIdx && destination <= sectionEnd else { return }

            let siblingIndices = flat.enumerated().compactMap { (i, item) -> (flatIdx: Int, task: FocusTask)? in
                if case .item(let t, let lid) = item, lid == listId, !t.isCompleted { return (i, t) }
                return nil
            }

            guard let siblingFrom = siblingIndices.firstIndex(where: { $0.task.id == movedItem.id }) else { return }

            var siblingTo = siblingIndices.count
            for (si, entry) in siblingIndices.enumerated() {
                if destination <= entry.flatIdx {
                    siblingTo = si
                    break
                }
            }
            if siblingTo > siblingFrom { siblingTo = min(siblingTo, siblingIndices.count) }

            guard siblingFrom != siblingTo && siblingFrom + 1 != siblingTo else { return }

            guard var allChildren = itemsMap[listId] else { return }
            var uncompleted = allChildren.filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }

            uncompleted.move(fromOffsets: IndexSet(integer: siblingFrom), toOffset: siblingTo)

            var updates: [(id: UUID, sortOrder: Int)] = []
            for (index, child) in uncompleted.enumerated() {
                if let mapIndex = allChildren.firstIndex(where: { $0.id == child.id }) {
                    allChildren[mapIndex].sortOrder = index
                }
                updates.append((id: child.id, sortOrder: index))
            }
            itemsMap[listId] = allChildren
            _Concurrency.Task { await persistSortOrders(updates) }

        default:
            return
        }
    }

    // MARK: - List Content Move Handler (items within a single list)

    func handleListContentFlatMove(from source: IndexSet, to destination: Int, listId: UUID) {
        guard let fromIdx = source.first else { return }

        let uncompleted = getUncompletedItems(for: listId)

        // The flat display order is: [uncompleted items..., addItemRow, completedHeader?, completed items...]
        // Only uncompleted items are movable, so fromIdx maps directly to the uncompleted array
        guard fromIdx < uncompleted.count else { return }

        let clampedTo = min(destination, uncompleted.count)
        guard fromIdx != clampedTo && fromIdx + 1 != clampedTo else { return }

        guard var allChildren = itemsMap[listId] else { return }
        var ordered = allChildren.filter { !$0.isCompleted }.sorted { $0.sortOrder < $1.sortOrder }

        ordered.move(fromOffsets: IndexSet(integer: fromIdx), toOffset: clampedTo)

        var updates: [(id: UUID, sortOrder: Int)] = []
        for (index, child) in ordered.enumerated() {
            if let mapIndex = allChildren.firstIndex(where: { $0.id == child.id }) {
                allChildren[mapIndex].sortOrder = index
            }
            updates.append((id: child.id, sortOrder: index))
        }
        itemsMap[listId] = allChildren
        _Concurrency.Task { await persistSortOrders(updates) }
    }

    // MARK: - Edit Mode

    func enterEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditMode = true
            selectedListIds = []
            expandedLists.removeAll()
        }
    }

    func exitEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditMode = false
            selectedListIds = []
        }
    }

    func toggleListSelection(_ listId: UUID) {
        if selectedListIds.contains(listId) {
            selectedListIds.remove(listId)
        } else {
            selectedListIds.insert(listId)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func selectAllUncompleted() {
        selectedListIds = Set(filteredLists.map { $0.id })
    }

    func deselectAll() {
        selectedListIds = []
    }

    func batchDeleteLists() async {
        let idsToDelete = selectedListIds

        do {
            // Collect all item IDs across selected lists
            var allItemIds = Set<UUID>()
            for listId in idsToDelete {
                let items = itemsMap[listId] ?? []
                for item in items {
                    allItemIds.insert(item.id)
                }
            }

            // All task IDs to delete (items + lists themselves)
            let allTaskIds = allItemIds.union(idsToDelete)

            // Delete all schedules and tasks concurrently
            async let deleteSchedules: Void = scheduleRepository.deleteSchedules(forTasks: allTaskIds)
            async let deleteTasks: Void = repository.deleteTasks(ids: allTaskIds)
            _ = try await (deleteSchedules, deleteTasks)

            lists.removeAll { idsToDelete.contains($0.id) }
            for listId in idsToDelete {
                itemsMap.removeValue(forKey: listId)
                expandedLists.remove(listId)
            }
            exitEditMode()
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func batchMoveToCategory(_ categoryId: UUID?) async {
        do {
            for listId in selectedListIds {
                if let index = lists.firstIndex(where: { $0.id == listId }) {
                    var updated = lists[index]
                    updated.categoryId = categoryId
                    updated.modifiedDate = Date()
                    try await repository.updateTask(updated)
                    lists[index].categoryId = categoryId
                    lists[index].modifiedDate = Date()
                }
            }
            exitEditMode()
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - TaskEditingViewModel Conformance

    func findTask(byId id: UUID) -> FocusTask? {
        if let list = lists.first(where: { $0.id == id }) {
            return list
        }
        for items in itemsMap.values {
            if let item = items.first(where: { $0.id == id }) {
                return item
            }
        }
        return nil
    }

    func getSubtasks(for taskId: UUID) -> [FocusTask] {
        getUncompletedItems(for: taskId) + getCompletedItems(for: taskId)
    }

    func updateTask(_ task: FocusTask, newTitle: String) async {
        guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        do {
            var updatedTask = task
            updatedTask.title = newTitle
            updatedTask.modifiedDate = Date()
            try await repository.updateTask(updatedTask)

            // Update in lists array
            if let index = lists.firstIndex(where: { $0.id == task.id }) {
                lists[index].title = newTitle
                lists[index].modifiedDate = Date()
            }

            // Update in itemsMap
            if let parentId = task.parentTaskId,
               var items = itemsMap[parentId],
               let index = items.firstIndex(where: { $0.id == task.id }) {
                items[index].title = newTitle
                items[index].modifiedDate = Date()
                itemsMap[parentId] = items
            }

            LocalMutationTracker.markMutation()
            NotificationCenter.default.post(name: .projectListChanged, object: self)
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

            if let index = lists.firstIndex(where: { $0.id == task.id }) {
                lists[index].description = newNote
                lists[index].modifiedDate = Date()
            }

            if let parentId = task.parentTaskId,
               var items = itemsMap[parentId],
               let index = items.firstIndex(where: { $0.id == task.id }) {
                items[index].description = newNote
                items[index].modifiedDate = Date()
                itemsMap[parentId] = items
            }

            LocalMutationTracker.markMutation()
            NotificationCenter.default.post(name: .projectListChanged, object: self)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTask(_ task: FocusTask) async {
        if task.type == .list {
            await deleteList(task)
        } else if let parentId = task.parentTaskId {
            await deleteItem(task, listId: parentId)
        }
    }

    func deleteSubtask(_ subtask: FocusTask, parentId: UUID) async {
        await deleteItem(subtask, listId: parentId)
    }

    func toggleSubtaskCompletion(_ subtask: FocusTask, parentId: UUID) async {
        await toggleItemCompletion(subtask, listId: parentId)
    }

    func createSubtask(title: String, parentId: UUID) async {
        await createItem(title: title, listId: parentId)
    }

    func updateTaskPriority(_ task: FocusTask, priority: Priority) async {
        do {
            var updated = task
            updated.priority = priority
            updated.modifiedDate = Date()
            try await repository.updateTask(updated)

            if let index = lists.firstIndex(where: { $0.id == task.id }) {
                lists[index].priority = priority
                lists[index].modifiedDate = Date()
            }
            notifyTasksChanged()
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

            if let index = lists.firstIndex(where: { $0.id == task.id }) {
                lists[index].categoryId = categoryId
                lists[index].modifiedDate = Date()
            }
            notifyTasksChanged()
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

    // MARK: - Content Edit Mode (items within a list)

    func enterContentEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            contentEditMode = true
            selectedContentItemIds = []
        }
    }

    func exitContentEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            contentEditMode = false
            selectedContentItemIds = []
        }
    }

    func toggleContentItemSelection(_ itemId: UUID) {
        if selectedContentItemIds.contains(itemId) {
            selectedContentItemIds.remove(itemId)
        } else {
            selectedContentItemIds.insert(itemId)
        }
    }

    func selectAllContentItems(listId: UUID) {
        let items = getUncompletedItems(for: listId)
        selectedContentItemIds = Set(items.map { $0.id })
    }

    func deselectAllContentItems() {
        selectedContentItemIds = []
    }

    var allContentItemsSelected: Bool {
        false // Will be computed per-list in the view
    }

    func allContentItemsSelected(for listId: UUID) -> Bool {
        let items = getUncompletedItems(for: listId)
        return !items.isEmpty && Set(items.map { $0.id }).isSubset(of: selectedContentItemIds)
    }

    func batchDeleteContentItems(listId: UUID) async {
        let idsToDelete = selectedContentItemIds
        do {
            for id in idsToDelete {
                try await scheduleRepository.deleteSchedules(forTask: id)
                try await repository.deleteTask(id: id)
            }
            if var items = itemsMap[listId] {
                items.removeAll { idsToDelete.contains($0.id) }
                itemsMap[listId] = items
            }
            exitContentEditMode()
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Move selected content items to a different list.
    func batchMoveContentItemsToList(targetListId: UUID, sourceListId: UUID) async {
        guard !selectedContentItemIds.isEmpty else { return }
        let selectedIds = selectedContentItemIds

        do {
            let existingItems = try await repository.fetchSubtasks(parentId: targetListId)
            let newCount = selectedIds.count

            // Shift existing items down
            let shiftUpdates = existingItems.map { (id: $0.id, sortOrder: $0.sortOrder + newCount) }
            if !shiftUpdates.isEmpty {
                try await repository.updateSortOrders(shiftUpdates)
            }

            // Move selected items
            for (offset, itemId) in selectedIds.enumerated() {
                try await repository.assignToList(taskId: itemId, listId: targetListId, sortOrder: offset)
            }

            // Update local state: remove from source
            if var items = itemsMap[sourceListId] {
                items.removeAll { selectedIds.contains($0.id) }
                itemsMap[sourceListId] = items
            }

            // Refresh target list items if loaded
            if itemsMap[targetListId] != nil {
                await fetchItems(for: targetListId)
            }

            exitContentEditMode()
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Create a new project and return its ID.
    func createProjectAndReturnId(title: String) async -> UUID? {
        guard let userId = authService.currentUser?.id else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        do {
            let newProject = FocusTask(
                userId: userId,
                title: trimmed,
                type: .project,
                isCompleted: false,
                sortOrder: 0,
                priority: .low
            )
            let created = try await repository.createTask(newProject)
            notifyTasksChanged()
            return created.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Move selected content items to a project.
    func batchMoveContentItemsToProject(projectId: UUID, sourceListId: UUID) async {
        guard !selectedContentItemIds.isEmpty else { return }
        let selectedIds = selectedContentItemIds

        do {
            let existingTasks = try await repository.fetchProjectTasks(projectId: projectId)
            let newCount = selectedIds.count

            // Shift existing items down
            let shiftUpdates = existingTasks.map { (id: $0.id, sortOrder: $0.sortOrder + newCount) }
            if !shiftUpdates.isEmpty {
                try await repository.updateSortOrders(shiftUpdates)
            }

            // Move selected items from list to project (clears parent_task_id, sets project_id)
            for (offset, itemId) in selectedIds.enumerated() {
                try await repository.moveFromListToProject(taskId: itemId, projectId: projectId, sortOrder: offset)
            }

            // Update local state: remove from source
            if var items = itemsMap[sourceListId] {
                items.removeAll { selectedIds.contains($0.id) }
                itemsMap[sourceListId] = items
            }

            exitContentEditMode()
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Move selected content items to inbox (standalone tasks).
    func batchMoveContentItemsToInbox(sourceListId: UUID) async {
        guard !selectedContentItemIds.isEmpty else { return }
        let selectedIds = selectedContentItemIds

        do {
            for itemId in selectedIds {
                try await repository.moveToInbox(taskId: itemId)
            }

            // Update local state: remove from source
            if var items = itemsMap[sourceListId] {
                items.removeAll { selectedIds.contains($0.id) }
                itemsMap[sourceListId] = items
            }

            exitContentEditMode()
            notifyTasksChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
