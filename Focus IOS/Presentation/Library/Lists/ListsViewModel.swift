//
//  ListsViewModel.swift
//  Focus IOS
//

import Foundation
import Combine
import SwiftUI
import Auth

@MainActor
class ListsViewModel: ObservableObject, LibraryFilterable {
    // MARK: - Published Properties
    @Published var categories: [Category] = []
    @Published var selectedCategoryId: UUID? = nil
    @Published var commitmentFilter: CommitmentFilter? = nil
    @Published var committedTaskIds: Set<UUID> = []
    @Published var isEditMode: Bool = false
    @Published var selectedListIds: Set<UUID> = []
    @Published var showingAddList: Bool = false

    // Batch operation triggers
    @Published var showBatchDeleteConfirmation: Bool = false
    @Published var showBatchMovePicker: Bool = false
    @Published var showBatchCommitSheet: Bool = false

    // Search
    @Published var searchText: String = ""

    private let categoryRepository: CategoryRepository
    private let commitmentRepository: CommitmentRepository
    private let authService: AuthService

    init(categoryRepository: CategoryRepository = CategoryRepository(),
         commitmentRepository: CommitmentRepository = CommitmentRepository(),
         authService: AuthService) {
        self.categoryRepository = categoryRepository
        self.commitmentRepository = commitmentRepository
        self.authService = authService
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

    var allUncompletedSelected: Bool { false }

    func selectCategory(_ categoryId: UUID?) {
        selectedCategoryId = categoryId
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
                type: "list"
            )
            let created = try await categoryRepository.createCategory(newCategory)
            categories.append(created)
            selectedCategoryId = created.id
        } catch {
            print("Error creating category: \(error)")
        }
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
            print("Error fetching committed task IDs: \(error)")
        }
    }

    func enterEditMode() {
        // Stub — no items to edit yet
    }

    func exitEditMode() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditMode = false
            selectedListIds = []
        }
    }

    var selectedItems: [FocusTask] { [] }

    func batchMoveToCategory(_ categoryId: UUID?) async {
        // Stub — no items yet
    }

    func selectAllUncompleted() {
        // Stub — no items yet
    }

    func deselectAll() {
        selectedListIds = []
    }
}
