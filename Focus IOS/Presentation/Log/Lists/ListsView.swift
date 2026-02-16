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
                        .font(.headline)
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
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Lists Yet")
                .font(.title2)
                .fontWeight(.semibold)

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
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color(.systemBackground))

                case .item(let item, let listId):
                    ListItemRow(item: item, listId: listId, viewModel: viewModel)
                        .padding(.leading, 32)
                        .moveDisabled(item.isCompleted || viewModel.isEditMode)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(Color(.systemBackground))

                case .doneSection(let listId):
                    ListDoneSection(listId: listId, viewModel: viewModel)
                        .moveDisabled(true)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(.systemBackground))

                case .addItemRow(let listId):
                    InlineAddItemRow(listId: listId, viewModel: viewModel, isAnyAddFieldActive: $isInlineAddFocused)
                        .moveDisabled(true)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
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
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
            }

            // Title + item count
            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(.body)
                    .lineLimit(1)

                if itemCount.total > 0 {
                    Text("\(itemCount.uncompleted) item\(itemCount.uncompleted == 1 ? "" : "s")")
                        .font(.caption)
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
                Button {
                    viewModel.selectedListForDetails = list
                } label: {
                    Label("Edit Details", systemImage: "pencil")
                }

                // Move to category
                Menu {
                    Button {
                        _Concurrency.Task { await viewModel.moveTaskToCategory(list, categoryId: nil) }
                    } label: {
                        if list.categoryId == nil {
                            Label("None", systemImage: "checkmark")
                        } else {
                            Text("None")
                        }
                    }
                    ForEach(viewModel.categories) { category in
                        Button {
                            _Concurrency.Task { await viewModel.moveTaskToCategory(list, categoryId: category.id) }
                        } label: {
                            if list.categoryId == category.id {
                                Label(category.name, systemImage: "checkmark")
                            } else {
                                Text(category.name)
                            }
                        }
                    }
                } label: {
                    Label("Move to Category", systemImage: "folder")
                }

                Divider()

                Button(role: .destructive) {
                    _Concurrency.Task { await viewModel.deleteList(list) }
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
                .font(.subheadline)
                .strikethrough(item.isCompleted)
                .foregroundColor(item.isCompleted ? .secondary : .primary)

            Spacer()

            // Checkbox
            Button {
                _Concurrency.Task {
                    await viewModel.toggleItemCompletion(item, listId: listId)
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundColor(item.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedItemForDetails = item
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
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Completed")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Text("(\(completedItems.count))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if isExpanded {
                            Button {
                                showClearConfirmation = true
                            } label: {
                                Text("Clear list")
                                    .font(.caption)
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
                    .font(.subheadline)
                    .focused($isFocused)
                    .onSubmit {
                        submitItem()
                    }

                Spacer()

                Image(systemName: "circle")
                    .font(.subheadline)
                    .foregroundColor(.gray.opacity(0.5))
            } else {
                Button {
                    isEditing = true
                    isFocused = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.subheadline)
                        Text("Add")
                            .font(.subheadline)
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
