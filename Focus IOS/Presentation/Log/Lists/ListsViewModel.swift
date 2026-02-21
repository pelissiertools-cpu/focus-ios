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

    // Category filter
    @Published var categories: [Category] = []
    @Published var selectedCategoryId: UUID? = nil

    // Commitment filter
    @Published var commitmentFilter: CommitmentFilter? = nil
    @Published var committedTaskIds: Set<UUID> = []

    // Edit mode
    @Published var isEditMode: Bool = false
    @Published var selectedListIds: Set<UUID> = []

    // Batch operation triggers
    @Published var showBatchDeleteConfirmation: Bool = false
    @Published var showBatchMovePicker: Bool = false
    @Published var showBatchCommitSheet: Bool = false

    // Add list
    @Published var showingAddList: Bool = false

    // Search
    @Published var searchText: String = ""

    // Sort
    @Published var sortOption: SortOption = .creationDate
    @Published var sortDirection: SortDirection = .lowestFirst

    private let repository: TaskRepository
    private let categoryRepository: CategoryRepository
    let commitmentRepository: CommitmentRepository
    private let authService: AuthService
    private var cancellables = Set<AnyCancellable>()

    init(repository: TaskRepository = TaskRepository(),
         categoryRepository: CategoryRepository = CategoryRepository(),
         commitmentRepository: CommitmentRepository = CommitmentRepository(),
         authService: AuthService) {
        self.repository = repository
        self.categoryRepository = categoryRepository
        self.commitmentRepository = commitmentRepository
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

    // MARK: - Computed Properties

    var filteredLists: [FocusTask] {
        var filtered = lists
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
            return items.sorted {
                ascending ? $0.createdDate < $1.createdDate : $0.createdDate > $1.createdDate
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
            self.lists = try await repository.fetchTasks(ofType: .list)
            self.categories = try await categoryRepository.fetchCategories()
            await fetchCommittedTaskIds()

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
            itemsMap[listId] = items
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
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - List CRUD

    func createList(title: String, categoryId: UUID? = nil) async {
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteList(_ list: FocusTask) async {
        do {
            // Delete all items under this list first
            let items = itemsMap[list.id] ?? []
            for item in items {
                try await commitmentRepository.deleteCommitments(forTask: item.id)
                try await repository.deleteTask(id: item.id)
            }
            // Delete commitments and the list itself
            try await commitmentRepository.deleteCommitments(forTask: list.id)
            try await repository.deleteTask(id: list.id)

            lists.removeAll { $0.id == list.id }
            itemsMap.removeValue(forKey: list.id)
            expandedLists.remove(list.id)
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteItem(_ item: FocusTask, listId: UUID) async {
        do {
            try await commitmentRepository.deleteCommitments(forTask: item.id)
            try await repository.deleteTask(id: item.id)

            if var items = itemsMap[listId] {
                items.removeAll { $0.id == item.id }
                itemsMap[listId] = items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Clear Done

    func clearCompletedItems(for listId: UUID) async {
        guard var items = itemsMap[listId] else { return }
        let completedItems = items.filter { $0.isCompleted }

        do {
            for item in completedItems {
                try await commitmentRepository.deleteCommitments(forTask: item.id)
                try await repository.deleteTask(id: item.id)
            }
            items.removeAll { $0.isCompleted }
            itemsMap[listId] = items
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
            for listId in idsToDelete {
                let items = itemsMap[listId] ?? []
                for item in items {
                    try await commitmentRepository.deleteCommitments(forTask: item.id)
                    try await repository.deleteTask(id: item.id)
                }
                try await commitmentRepository.deleteCommitments(forTask: listId)
                try await repository.deleteTask(id: listId)
            }

            lists.removeAll { idsToDelete.contains($0.id) }
            for listId in idsToDelete {
                itemsMap.removeValue(forKey: listId)
                expandedLists.remove(listId)
            }
            exitEditMode()
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
}
