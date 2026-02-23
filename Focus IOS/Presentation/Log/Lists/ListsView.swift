//
//  ListsView.swift
//  Focus IOS
//

import SwiftUI

// MARK: - Lists View

struct ListsView: View {
    @ObservedObject var viewModel: ListsViewModel
    let searchText: String
    var onSearchTap: (() -> Void)? = nil
    @State private var isInlineAddFocused = false
    @State private var showCategoryEditDrawer = false
    @State private var initialLoadComplete = false

    init(viewModel: ListsViewModel, searchText: String = "", onSearchTap: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.searchText = searchText
        self.onSearchTap = onSearchTap
    }

    private var categoryTitle: String {
        if let id = viewModel.selectedCategoryId,
           let cat = viewModel.categories.first(where: { $0.id == id }) {
            return cat.name
        }
        return "All"
    }

    var body: some View {
        VStack(spacing: 0) {
            CategorySelectorHeader(
                title: categoryTitle,
                count: viewModel.filteredLists.count,
                countSuffix: "list",
                categories: viewModel.categories,
                selectedCategoryId: viewModel.selectedCategoryId,
                onSelectCategory: { categoryId in
                    viewModel.selectedCategoryId = categoryId
                },
                onEdit: { showCategoryEditDrawer = true }
            ) {
                if viewModel.isEditMode {
                    HStack(spacing: 8) {
                        Button {
                            if viewModel.allUncompletedSelected {
                                viewModel.deselectAll()
                            } else {
                                viewModel.selectAllUncompleted()
                            }
                        } label: {
                            Text(LocalizedStringKey(viewModel.allUncompletedSelected ? "Deselect All" : "Select All"))
                                .font(.sf(.subheadline, weight: .medium))
                                .foregroundColor(.appRed)
                        }
                        .buttonStyle(.plain)

                        Text("\(viewModel.selectedCount) selected")
                            .font(.sf(.subheadline))
                            .foregroundColor(.secondary)

                        Button {
                            viewModel.exitEditMode()
                        } label: {
                            Text("Done")
                                .font(.sf(.subheadline, weight: .medium))
                                .foregroundColor(.appRed)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 8) {
                        SortMenuButton(viewModel: viewModel)

                        if let onSearchTap {
                            Button(action: onSearchTap) {
                                Image(systemName: "magnifyingglass")
                                    .font(.sf(.body, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(width: 36, height: 36)
                                    .glassEffect(.regular.interactive(), in: .circle)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 8)

            ZStack {
                if viewModel.isLoading && !initialLoadComplete {
                    ProgressView("Loading lists...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.lists.isEmpty {
                    GeometryReader { geometry in
                        ScrollView {
                            emptyState
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                        .refreshable {
                            await withCheckedContinuation { continuation in
                                _Concurrency.Task { @MainActor in
                                    await viewModel.fetchLists()
                                    continuation.resume()
                                }
                            }
                        }
                    }
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

            Spacer(minLength: 0)
        }
        .sheet(item: $viewModel.selectedListForDetails) { list in
            ListDetailsDrawer(list: list, viewModel: viewModel)
                .drawerStyle()
        }
        .sheet(isPresented: $showCategoryEditDrawer) {
            CategoryEditDrawer(viewModel: viewModel)
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
            initialLoadComplete = true
        }
        .onAppear {
            viewModel.searchText = searchText
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No lists yet")
                .font(.sf(.headline))
                .bold()
            Text("Tap to create your first list")
                .font(.sf(.subheadline))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.showingAddList = true
        }
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
                    .listRowBackground(Color.clear)
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] - 12 }
                    .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] + 12 }

                case .item(let item, let listId):
                    ListItemRow(item: item, listId: listId, viewModel: viewModel)
                        .padding(.leading, 32)
                        .moveDisabled(item.isCompleted || viewModel.isEditMode)
                        .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                        .listRowBackground(Color.clear)
                        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] - 12 }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] + 12 }

                case .doneSection(let listId):
                    ListDoneSection(listId: listId, viewModel: viewModel)
                        .moveDisabled(true)
                        .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                case .addItemRow(let listId):
                    InlineAddRow(
                        placeholder: "Item title",
                        buttonLabel: "Add items",
                        onSubmit: { title in await viewModel.createItem(title: title, listId: listId) },
                        isAnyAddFieldActive: $isInlineAddFocused,
                        verticalPadding: 12
                    )
                    .padding(.leading, 32)
                    .moveDisabled(true)
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                    .listRowBackground(Color.clear)
                }
            }
            .onMove { from, to in
                viewModel.handleFlatMove(from: from, to: to)
            }

            // Bottom spacer so content can scroll above the floating + button
            Color.clear
                .frame(height: 100)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
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
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.sf(.title3))
                    .foregroundColor(isSelected ? .appRed : .secondary)
            }

            // Title + item count
            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(.sf(.body))
                    .lineLimit(1)

                Text("\(itemCount.uncompleted) item\(itemCount.uncompleted == 1 ? "" : "s")")
                    .font(.sf(.caption))
                    .foregroundColor(.secondary)
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

                ContextMenuItems.prioritySubmenu(
                    currentPriority: list.priority
                ) { priority in
                    _Concurrency.Task { await viewModel.updateTaskPriority(list, priority: priority) }
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
    @State private var showDeleteConfirmation = false

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
                    .foregroundColor(item.isCompleted ? Color.completedPurple.opacity(0.6) : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedItemForDetails = item
        }
        .contextMenu {
            if !item.isCompleted {
                ContextMenuItems.editButton {
                    viewModel.selectedItemForDetails = item
                }

                Divider()

                ContextMenuItems.deleteButton {
                    showDeleteConfirmation = true
                }
            }
        }
        .alert("Delete item?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.deleteItem(item, listId: listId)
                }
            }
        } message: {
            Text("This will permanently delete this item.")
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
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleDoneSectionCollapsed(for: listId)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text("Completed")
                                .font(.sf(.subheadline, weight: .medium))
                                .foregroundColor(.secondary)

                            Text("\(completedItems.count)")
                                .font(.sf(.subheadline))
                                .foregroundColor(.secondary)

                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.sf(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .clipShape(Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if isExpanded {
                        Button {
                            showClearConfirmation = true
                        } label: {
                            Text("Clear list")
                                .font(.sf(.caption))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.darkGray, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 10)

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

#Preview {
    ListsView(viewModel: ListsViewModel(authService: AuthService()))
}
