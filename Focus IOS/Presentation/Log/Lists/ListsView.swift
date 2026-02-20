//
//  ListsView.swift
//  Focus IOS
//

import SwiftUI

// MARK: - Lists View

struct ListsView: View {
    @ObservedObject var viewModel: ListsViewModel
    let searchText: String
    @State private var isInlineAddFocused = false

    init(viewModel: ListsViewModel, searchText: String = "") {
        self.viewModel = viewModel
        self.searchText = searchText
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView("Loading lists...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.lists.isEmpty {
                emptyState
            } else if viewModel.filteredLists.isEmpty {
                VStack(spacing: 12) {
                    Text("No matching lists")
                        .font(.sf(.headline))
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                listContent
            }
        }
        .padding(.top, 44)
        .sheet(item: $viewModel.selectedListForDetails) { list in
            ListDetailsDrawer(list: list, viewModel: viewModel)
                .drawerStyle()
        }
        .sheet(item: $viewModel.selectedItemForDetails) { item in
            TaskDetailsDrawer(task: item, viewModel: viewModel, categories: viewModel.categories)
                .drawerStyle()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        // Batch delete confirmation
        .alert("Delete \(viewModel.selectedCount) list\(viewModel.selectedCount == 1 ? "" : "s")?", isPresented: $viewModel.showBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task { await viewModel.batchDeleteLists() }
            }
        } message: {
            Text("This will permanently delete the selected lists and all their items.")
        }
        // Batch move category sheet
        .sheet(isPresented: $viewModel.showBatchMovePicker) {
            BatchMoveCategorySheet(viewModel: viewModel)
                .drawerStyle()
        }
        // Batch commit sheet
        .sheet(isPresented: $viewModel.showBatchCommitSheet) {
            BatchCommitSheet(viewModel: viewModel)
                .drawerStyle()
        }
        .task {
            if viewModel.lists.isEmpty && !viewModel.isLoading {
                await viewModel.fetchLists()
            }
        }
        .onAppear {
            viewModel.searchText = searchText
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.sf(size: 60))
                .foregroundColor(.secondary)

            Text("No Lists Yet")
                .font(.sf(.title2, weight: .semibold))

            Text("Tap the + button to create your first list")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var listContent: some View {
        List {
            ForEach(viewModel.flattenedDisplayItems) { item in
                switch item {
                case .list(let list):
                    ListRow(
                        list: list,
                        viewModel: viewModel,
                        isEditMode: viewModel.isEditMode,
                        isSelected: viewModel.selectedListIds.contains(list.id),
                        onSelectToggle: { viewModel.toggleListSelection(list.id) }
                    )
                    .moveDisabled(viewModel.isEditMode)
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                    .listRowBackground(Color(.systemBackground))

                case .item(let item, let listId):
                    ListItemRow(item: item, listId: listId, viewModel: viewModel)
                        .padding(.leading, 32)
                        .moveDisabled(item.isCompleted || viewModel.isEditMode)
                        .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                        .listRowBackground(Color(.systemBackground))

                case .doneSection(let listId):
                    ListDoneSection(listId: listId, viewModel: viewModel)
                        .moveDisabled(true)
                        .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(.systemBackground))

                case .addItemRow(let listId):
                    InlineAddItemRow(listId: listId, viewModel: viewModel, isAnyAddFieldActive: $isInlineAddFocused)
                        .moveDisabled(true)
                        .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                        .listRowBackground(Color(.systemBackground))
                }
            }
            .onMove { from, to in
                viewModel.handleFlatMove(from: from, to: to)
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissOverlay(isActive: $isInlineAddFocused)
        .refreshable {
            await withCheckedContinuation { continuation in
                _Concurrency.Task { @MainActor in
                    await viewModel.fetchLists()
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - List Row (NO checkbox — lists are not checkable)

struct ListRow: View {
    let list: FocusTask
    @ObservedObject var viewModel: ListsViewModel
    var isEditMode: Bool = false
    var isSelected: Bool = false
    var onSelectToggle: (() -> Void)? = nil
    @State private var showDeleteConfirmation = false

    private var itemCount: (uncompleted: Int, total: Int) {
        let items = viewModel.itemsMap[list.id] ?? []
        let completed = items.filter { $0.isCompleted }.count
        return (items.count - completed, items.count)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Edit mode: selection circle
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.sf(.title3))
                    .foregroundColor(isSelected ? .appRed : .gray)
            }

            // Title + item count
            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(.sf(.body))
                    .lineLimit(1)

                if itemCount.total > 0 {
                    Text("\(itemCount.uncompleted) item\(itemCount.uncompleted == 1 ? "" : "s")")
                        .font(.sf(.caption))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 70)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode {
                onSelectToggle?()
            } else {
                _Concurrency.Task {
                    await viewModel.toggleExpanded(list.id)
                }
            }
        }
        .contextMenu {
            if !isEditMode {
                ContextMenuItems.editButton {
                    viewModel.selectedListForDetails = list
                }

                ContextMenuItems.categorySubmenu(
                    currentCategoryId: list.categoryId,
                    categories: viewModel.categories
                ) { categoryId in
                    _Concurrency.Task { await viewModel.moveTaskToCategory(list, categoryId: categoryId) }
                }

                Divider()

                ContextMenuItems.deleteButton {
                    showDeleteConfirmation = true
                }
            }
        }
        .alert("Delete List", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                _Concurrency.Task { await viewModel.deleteList(list) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(list.title)\"?")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isEditMode {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - List Item Row (WITH checkbox)

struct ListItemRow: View {
    let item: FocusTask
    let listId: UUID
    @ObservedObject var viewModel: ListsViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text(item.title)
                .font(.sf(.subheadline))
                .strikethrough(item.isCompleted)
                .foregroundColor(item.isCompleted ? .secondary : .primary)

            Spacer()

            // Checkbox
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                _Concurrency.Task {
                    await viewModel.toggleItemCompletion(item, listId: listId)
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.sf(.subheadline))
                    .foregroundColor(item.isCompleted ? Color(red: 0x61/255.0, green: 0x10/255.0, blue: 0xF8/255.0).opacity(0.6) : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedItemForDetails = item
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                _Concurrency.Task {
                    await viewModel.deleteItem(item, listId: listId)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - List Done Section (per-list collapsible done with "Clear list")

struct ListDoneSection: View {
    let listId: UUID
    @ObservedObject var viewModel: ListsViewModel
    @State private var showClearConfirmation = false

    private var completedItems: [FocusTask] {
        viewModel.getCompletedItems(for: listId)
    }

    private var isExpanded: Bool {
        !viewModel.isDoneSectionCollapsed(for: listId)
    }

    var body: some View {
        if !completedItems.isEmpty {
            VStack(spacing: 0) {
                // Done pill header
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleDoneSectionCollapsed(for: listId)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.sf(.caption))
                            .foregroundColor(.secondary)

                        Text("Completed")
                            .font(.sf(.subheadline, weight: .medium))
                            .foregroundColor(.secondary)

                        Text("(\(completedItems.count))")
                            .font(.sf(.subheadline))
                            .foregroundColor(.secondary)

                        if isExpanded {
                            Button {
                                showClearConfirmation = true
                            } label: {
                                Text("Clear list")
                                    .font(.sf(.caption))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.secondary.opacity(0.15))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Expanded completed items
                if isExpanded {
                    ForEach(completedItems) { item in
                        VStack(spacing: 0) {
                            Divider()
                            ListItemRow(item: item, listId: listId, viewModel: viewModel)
                        }
                    }
                }
            }
            .padding(.leading, 32)
            .alert("Clear completed items?", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    _Concurrency.Task {
                        await viewModel.clearCompletedItems(for: listId)
                    }
                }
            } message: {
                Text("This will permanently delete \(completedItems.count) completed item\(completedItems.count == 1 ? "" : "s").")
            }
        }
    }
}

// MARK: - Inline Add Item Row

struct InlineAddItemRow: View {
    let listId: UUID
    @ObservedObject var viewModel: ListsViewModel
    @Binding var isAnyAddFieldActive: Bool
    @State private var newItemTitle = ""
    @State private var isEditing = false
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("Item title", text: $newItemTitle)
                    .font(.sf(.subheadline))
                    .focused($isFocused)
                    .onSubmit {
                        submitItem()
                    }

                Spacer()

                Image(systemName: "circle")
                    .font(.sf(.subheadline))
                    .foregroundColor(.gray.opacity(0.5))
            } else {
                Button {
                    isEditing = true
                    isFocused = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.sf(.subheadline))
                        Text("Add items")
                            .font(.sf(.subheadline))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 32)
        .onChange(of: isFocused) { _, focused in
            if focused {
                isAnyAddFieldActive = true
            } else if !isSubmitting {
                isAnyAddFieldActive = false
                isEditing = false
                newItemTitle = ""
            }
        }
    }

    private func submitItem() {
        let title = newItemTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            isEditing = false
            return
        }

        isSubmitting = true
        _Concurrency.Task {
            await viewModel.createItem(title: title, listId: listId)
            newItemTitle = ""
            isFocused = true
            isSubmitting = false
        }
    }
}

#Preview {
    ListsView(viewModel: ListsViewModel(authService: AuthService()))
}
