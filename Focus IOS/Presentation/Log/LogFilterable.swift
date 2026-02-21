//
//  LogFilterable.swift
//  Focus IOS
//

import Foundation
import Combine

@MainActor
protocol LogFilterable: ObservableObject {
    // MARK: - Category filter
    var categories: [Category] { get }
    var selectedCategoryId: UUID? { get set }
    func selectCategory(_ categoryId: UUID?)
    func createCategory(name: String) async
    func deleteCategories(ids: Set<UUID>) async
    func mergeCategories(ids: Set<UUID>) async
    func renameCategory(id: UUID, newName: String) async
    func reorderCategories(fromOffsets: IndexSet, toOffset: Int) async

    // MARK: - Sort
    var sortOption: SortOption { get set }
    var sortDirection: SortDirection { get set }

    // MARK: - Commitment filter
    var commitmentFilter: CommitmentFilter? { get set }
    var committedTaskIds: Set<UUID> { get set }
    var commitmentRepository: CommitmentRepository { get }
    func toggleCommitmentFilter(_ filter: CommitmentFilter)
    func fetchCommittedTaskIds() async

    // MARK: - Edit mode
    var isEditMode: Bool { get }
    var selectedItemIds: Set<UUID> { get }
    var selectedCount: Int { get }
    var allUncompletedSelected: Bool { get }
    func enterEditMode()
    func exitEditMode()
    func selectAllUncompleted()
    func deselectAll()

    // MARK: - Add item
    var showingAddItem: Bool { get set }

    // MARK: - Batch operations
    var showBatchDeleteConfirmation: Bool { get set }
    var showBatchMovePicker: Bool { get set }
    var showBatchCommitSheet: Bool { get set }
    var selectedItems: [FocusTask] { get }
    func batchMoveToCategory(_ categoryId: UUID?) async
}

// Default implementations for trivial methods identical across all Log ViewModels.
extension LogFilterable {
    func selectCategory(_ categoryId: UUID?) {
        selectedCategoryId = categoryId
    }

    func toggleCommitmentFilter(_ filter: CommitmentFilter) {
        if commitmentFilter == filter {
            commitmentFilter = nil
        } else {
            commitmentFilter = filter
        }
    }

    func fetchCommittedTaskIds() async {
        do {
            committedTaskIds = try await commitmentRepository.fetchCommittedTaskIds()
        } catch {
            // Error already handled by caller
        }
    }
}
