//
//  ListsViewModel.swift
//  Focus IOS
//

import Foundation
import Combine
import SwiftUI
import Auth

@MainActor
class ListsViewModel: ObservableObject, LibraryFilterable, TaskEditingViewModel {
    // MARK: - Published Properties

    // Lists data
    @Published var lists: [FocusTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Items state management (items = subtasks of a list)
    @Published var itemsMap: [UUID: [FocusTask]] = [:]
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

    // MARK: - LibraryFilterable Conformance

    var categoryType: String { "list" }

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
                sortOrder: categories.count,
                type: .list
            )
            let created = try await categoryRepository.createCategory(newCategory)
            categories.append(created)
            selectedCategoryId = created.id
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
        return filtered.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Data Fetching

    func fetchLists() async {
        if lists.isEmpty { isLoading = true }
        errorMessage = nil

        do {
            self.lists = try await repository.fetchTasks(ofType: .list)
            self.categories = try await categoryRepository.fetchCategories(type: .list)
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
            self.categories = try await categoryRepository.fetchCategories(type: .list)
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
                        TaskNotificationKeys.source: TaskNotificationSource.library.rawValue,
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

    func reorderList(droppedId: UUID, targetId: UUID) {
        guard let updates = ReorderUtility.reorderItems(
            &lists, droppedId: droppedId, targetId: targetId,
            filterCompleted: false
        ) else { return }
        _Concurrency.Task { await persistSortOrders(updates) }
    }

    func reorderItem(droppedId: UUID, targetId: UUID, listId: UUID) {
        guard let updates = ReorderUtility.reorderChildItems(
            in: &itemsMap, parentId: listId, droppedId: droppedId, targetId: targetId
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
                sortOrder: categories.count,
                type: .list
            )
            let created = try await categoryRepository.createCategory(newCategory)
            categories.append(created)
            await moveTaskToCategory(task, categoryId: created.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
