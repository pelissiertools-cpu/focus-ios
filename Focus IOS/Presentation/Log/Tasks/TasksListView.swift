//
//  TasksListView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

// MARK: - Row Frame Preference Key (used by FocusTabView, ProjectsListView)

struct RowFramePreference: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Tasks List View

struct TasksListView: View {
    @ObservedObject var viewModel: TaskListViewModel

    let searchText: String
    @State private var isInlineAddFocused = false
    @State private var isCategoryExpanded = false

    init(viewModel: TaskListViewModel, searchText: String = "") {
        self.viewModel = viewModel
        self.searchText = searchText
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
            // Category selector header
            CategorySelectorHeader(
                title: categoryTitle,
                count: viewModel.uncompletedTasks.count + viewModel.completedTasks.count,
                isExpanded: $isCategoryExpanded,
                categories: viewModel.categories,
                selectedCategoryId: viewModel.selectedCategoryId,
                onSelectCategory: { categoryId in
                    viewModel.selectedCategoryId = categoryId
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCategoryExpanded = false
                    }
                },
                onCreateCategory: { name in
                    _Concurrency.Task {
                        await viewModel.createCategory(name: name)
                    }
                },
                onDeleteCategories: { ids in
                    _Concurrency.Task {
                        await viewModel.deleteCategories(ids: ids)
                    }
                },
                onMergeCategories: { ids in
                    _Concurrency.Task {
                        await viewModel.mergeCategories(ids: ids)
                    }
                },
                onRenameCategory: { id, name in
                    _Concurrency.Task {
                        await viewModel.renameCategory(id: id, newName: name)
                    }
                }
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

                        Button {
                            viewModel.enterEditMode()
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.sf(.body, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(width: 36, height: 36)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 8)

            ZStack {
                if viewModel.isLoading {
                    ProgressView("Loading tasks...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.tasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }

            Spacer(minLength: 0)
        }
        .sheet(item: $viewModel.selectedTaskForDetails) { task in
            TaskDetailsDrawer(task: task, viewModel: viewModel, categories: viewModel.categories)
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
        .alert("Delete \(viewModel.selectedCount) task\(viewModel.selectedCount == 1 ? "" : "s")?", isPresented: $viewModel.showBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task { await viewModel.batchDeleteTasks() }
            }
        } message: {
            Text("This will permanently delete the selected tasks and their commitments.")
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
            // Reinitialize viewModel with proper authService from environment
            if viewModel.tasks.isEmpty && !viewModel.isLoading {
                await viewModel.fetchTasks()
                await viewModel.fetchCategories()
                await viewModel.fetchCommittedTaskIds()
            }
        }
        .onAppear {
            viewModel.searchText = searchText
            // Refresh committed task IDs (lightweight, handles changes from Focus tab)
            Task {
                await viewModel.fetchCommittedTaskIds()
            }
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.sf(size: 60))
                .foregroundColor(.secondary)

            Text("No Tasks Yet")
                .font(.sf(.title2, weight: .semibold))

            Text("Tap the + button to add your first task")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var taskList: some View {
        List {
            // Flat array: priority headers + parents + expanded subtasks + add rows
            ForEach(viewModel.flattenedDisplayItems) { item in
                switch item {
                case .priorityHeader(let priority):
                    PrioritySectionHeader(
                        priority: priority,
                        count: viewModel.uncompletedTasks(for: priority).count,
                        isCollapsed: viewModel.isPriorityCollapsed(priority),
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.togglePriorityCollapsed(priority)
                            }
                        }
                    )
                    .moveDisabled(true)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color(.systemBackground))

                case .task(let task):
                    FlatTaskRow(
                        task: task,
                        viewModel: viewModel,
                        isEditMode: viewModel.isEditMode,
                        isSelected: viewModel.selectedTaskIds.contains(task.id),
                        onSelectToggle: { viewModel.toggleTaskSelection(task.id) }
                    )
                    .padding(.leading, task.parentTaskId != nil ? 32 : 0)
                    .moveDisabled(task.isCompleted || viewModel.isEditMode)
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                    .listRowBackground(Color(.systemBackground))

                case .addSubtaskRow(let parentId):
                    InlineAddRow(
                        placeholder: "Subtask title",
                        buttonLabel: "Add subtask",
                        onSubmit: { title in await viewModel.createSubtask(title: title, parentId: parentId) },
                        isAnyAddFieldActive: $isInlineAddFocused,
                        verticalPadding: 12
                    )
                    .padding(.leading, 32)
                    .moveDisabled(true)
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                    .listRowBackground(Color(.systemBackground))
                }
            }
            .onMove { from, to in
                viewModel.handleFlatMove(from: from, to: to)
            }

            // Done pill (when there are completed tasks, hidden in edit mode)
            if !viewModel.isEditMode && !viewModel.completedTasks.isEmpty {
                LogDonePillView(completedTasks: viewModel.completedTasks, viewModel: viewModel, isInlineAddFocused: $isInlineAddFocused)
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color(.systemBackground))
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissOverlay(isActive: $isInlineAddFocused)
        .refreshable {
            await withCheckedContinuation { continuation in
                _Concurrency.Task { @MainActor in
                    await viewModel.fetchTasks()
                    await viewModel.fetchCategories()
                    await viewModel.fetchCommittedTaskIds()
                    continuation.resume()
                }
            }
        }
    }

}

// MARK: - Priority Section Header

struct PrioritySectionHeader: View {
    let priority: Priority
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Circle()
                    .fill(priority.dotColor)
                    .frame(width: 8, height: 8)

                Text(priority.displayName)
                    .font(.golosText(size: 14))

                if count > 0 {
                    Text("\(count)")
                        .font(.sf(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.sf(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggle()
            }
            .frame(minHeight: 70, alignment: .bottom)

            Rectangle()
                .fill(Color.secondary.opacity(0.7))
                .frame(height: 1)
        }
    }
}

// MARK: - Category Selector Header

struct CategorySelectorHeader<TrailingContent: View>: View {
    let title: String
    let count: Int
    let countSuffix: String
    @Binding var isExpanded: Bool
    let categories: [Category]
    let selectedCategoryId: UUID?
    let onSelectCategory: (UUID?) -> Void
    let onCreateCategory: (String) -> Void
    let onDeleteCategories: (Set<UUID>) -> Void
    let onMergeCategories: (Set<UUID>) -> Void
    let onRenameCategory: (UUID, String) -> Void
    let trailingContent: TrailingContent

    @State private var newCategoryName = ""
    @State private var isAddingCategory = false
    @FocusState private var isTextFieldFocused: Bool

    // Category edit mode
    @State private var isCategoryEditMode = false
    @State private var selectedCategoryIds: Set<UUID> = []
    @State private var editingCategoryId: UUID? = nil
    @State private var editingCategoryName: String = ""
    @State private var showDeleteConfirmation = false
    @State private var showMergeConfirmation = false
    @FocusState private var focusedRenameId: UUID?

    init(
        title: String,
        count: Int,
        countSuffix: String = "task",
        isExpanded: Binding<Bool>,
        categories: [Category],
        selectedCategoryId: UUID?,
        onSelectCategory: @escaping (UUID?) -> Void,
        onCreateCategory: @escaping (String) -> Void,
        onDeleteCategories: @escaping (Set<UUID>) -> Void,
        onMergeCategories: @escaping (Set<UUID>) -> Void,
        onRenameCategory: @escaping (UUID, String) -> Void,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.count = count
        self.countSuffix = countSuffix
        self._isExpanded = isExpanded
        self.categories = categories
        self.selectedCategoryId = selectedCategoryId
        self.onSelectCategory = onSelectCategory
        self.onCreateCategory = onCreateCategory
        self.onDeleteCategories = onDeleteCategories
        self.onMergeCategories = onMergeCategories
        self.onRenameCategory = onRenameCategory
        self.trailingContent = trailingContent()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.golosText(size: 30))

                    if count > 0 {
                        Text("\(count) \(countSuffix)\(count == 1 ? "" : "s")")
                            .font(.sf(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isCategoryEditMode {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                }

                Spacer()

                trailingContent
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)

            Rectangle()
                .fill(Color.black)
                .frame(height: 1)

            // Expanded category choices
            if isExpanded {
                if isCategoryEditMode {
                    // Edit mode header
                    HStack {
                        Spacer()
                        Button {
                            commitRenameIfNeeded()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isCategoryEditMode = false
                                selectedCategoryIds = []
                                editingCategoryId = nil
                            }
                        } label: {
                            Text("Done")
                                .font(.sf(.subheadline, weight: .medium))
                                .foregroundColor(.appRed)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                } else {
                    // Normal mode: "All" option + Edit button row
                    HStack {
                        // "All" option
                        Button {
                            onSelectCategory(nil)
                        } label: {
                            HStack {
                                Text("All")
                                    .font(.sf(.body))
                                    .foregroundColor(.primary)
                                if selectedCategoryId == nil {
                                    Image(systemName: "checkmark")
                                        .font(.sf(.body))
                                        .foregroundColor(.appRed)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if !categories.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isCategoryEditMode = true
                                    selectedCategoryIds = []
                                    isAddingCategory = false
                                }
                            } label: {
                                Text("Edit")
                                    .font(.sf(.subheadline, weight: .medium))
                                    .foregroundColor(.appRed)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                // Category list
                ForEach(categories) { category in
                    if isCategoryEditMode {
                        editableCategoryRow(category: category)
                    } else {
                        categoryRow(name: category.name, isSelected: selectedCategoryId == category.id) {
                            onSelectCategory(category.id)
                        }
                    }
                }

                if isCategoryEditMode {
                    // Action bar (bottom right)
                    HStack {
                        Spacer()

                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.sf(.body))
                                .foregroundColor(selectedCategoryIds.isEmpty ? .gray : .appRed)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedCategoryIds.isEmpty)

                        Button {
                            showMergeConfirmation = true
                        } label: {
                            Image(systemName: "arrow.triangle.merge")
                                .font(.sf(.body))
                                .foregroundColor(selectedCategoryIds.count < 2 ? .gray : .green)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedCategoryIds.count < 2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                } else {
                    // Add new category
                    if isAddingCategory {
                        HStack(spacing: 8) {
                            TextField("Category name", text: $newCategoryName)
                                .font(.sf(.body))
                                .focused($isTextFieldFocused)
                                .onSubmit { submitNewCategory() }
                            Button {
                                submitNewCategory()
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.sf(.body))
                                    .foregroundColor(
                                        newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? .gray : .appRed
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    } else {
                        Button {
                            isAddingCategory = true
                            isTextFieldFocused = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.sf(.subheadline))
                                Text("New Category")
                                    .font(.sf(.subheadline))
                            }
                            .foregroundColor(.appRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Rectangle()
                    .fill(Color.secondary.opacity(0.7))
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, 16)
        .alert(deleteConfirmationTitle, isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                let ids = selectedCategoryIds
                onDeleteCategories(ids)
                selectedCategoryIds = []
                isCategoryEditMode = false
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .alert(mergeConfirmationTitle, isPresented: $showMergeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Merge", role: .destructive) {
                let ids = selectedCategoryIds
                onMergeCategories(ids)
                selectedCategoryIds = []
                isCategoryEditMode = false
            }
        } message: {
            Text(mergeConfirmationMessage)
        }
    }

    // MARK: - Edit Mode Row

    @ViewBuilder
    private func editableCategoryRow(category: Category) -> some View {
        HStack(spacing: 10) {
            // Selection circle
            Image(systemName: selectedCategoryIds.contains(category.id) ? "checkmark.circle.fill" : "circle")
                .font(.sf(.title3))
                .foregroundColor(selectedCategoryIds.contains(category.id) ? .appRed : .gray)
                .onTapGesture {
                    if selectedCategoryIds.contains(category.id) {
                        selectedCategoryIds.remove(category.id)
                    } else {
                        selectedCategoryIds.insert(category.id)
                    }
                }

            // Editable name
            if editingCategoryId == category.id {
                TextField("Category name", text: $editingCategoryName)
                    .font(.sf(.body))
                    .focused($focusedRenameId, equals: category.id)
                    .onSubmit {
                        commitRename(for: category.id)
                    }
            } else {
                Text(category.name)
                    .font(.sf(.body))
                    .foregroundColor(.primary)
                    .onTapGesture {
                        commitRenameIfNeeded()
                        editingCategoryId = category.id
                        editingCategoryName = category.name
                        focusedRenameId = category.id
                    }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Normal Row

    @ViewBuilder
    private func categoryRow(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack {
                Text(name)
                    .font(.sf(.body))
                    .foregroundColor(.primary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.sf(.body))
                        .foregroundColor(.appRed)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func submitNewCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onCreateCategory(name)
        newCategoryName = ""
        isAddingCategory = false
    }

    private func commitRename(for categoryId: UUID) {
        let trimmed = editingCategoryName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRenameCategory(categoryId, trimmed)
        }
        editingCategoryId = nil
        editingCategoryName = ""
    }

    private func commitRenameIfNeeded() {
        if let id = editingCategoryId {
            commitRename(for: id)
        }
    }

    // MARK: - Confirmation Text

    private var selectedCategoryNames: [String] {
        categories
            .filter { selectedCategoryIds.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.name }
    }

    private func formatNameList(_ names: [String]) -> String {
        let quoted = names.map { "\"\($0)\"" }
        switch quoted.count {
        case 0: return ""
        case 1: return quoted[0]
        case 2: return "\(quoted[0]) and \(quoted[1])"
        default:
            let last = quoted.last ?? ""
            let rest = quoted.dropLast().joined(separator: ", ")
            return "\(rest), and \(last)"
        }
    }

    private var deleteConfirmationTitle: String {
        let names = selectedCategoryNames
        if names.count == 1, let name = names.first {
            return "Delete \"\(name)\"?"
        }
        return "Delete \(names.count) categories?"
    }

    private var deleteConfirmationMessage: String {
        let names = selectedCategoryNames
        guard !names.isEmpty else { return "" }
        return "Tasks in \(formatNameList(names)) will become uncategorized."
    }

    private var mergeConfirmationTitle: String {
        let names = selectedCategoryNames
        guard let targetName = names.first else { return "Merge?" }
        return "Merge into \"\(targetName)\"?"
    }

    private var mergeConfirmationMessage: String {
        let names = selectedCategoryNames
        guard let targetName = names.first else { return "" }
        let sourceNames = Array(names.dropFirst())
        guard !sourceNames.isEmpty else { return "" }
        return "All tasks from \(formatNameList(sourceNames)) will be moved to \"\(targetName)\"."
    }
}

// MARK: - Log Done Pill View

struct LogDonePillView: View {
    let completedTasks: [FocusTask]
    @ObservedObject var viewModel: TaskListViewModel
    @Binding var isInlineAddFocused: Bool
    @State private var showClearConfirmation = false

    private var isExpanded: Bool {
        !viewModel.isDoneSubsectionCollapsed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Done pill header
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleDoneSubsectionCollapsed()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("Completed")
                            .font(.sf(.subheadline, weight: .medium))
                            .foregroundColor(.secondary)

                        Text("\(completedTasks.count)")
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
                            .background(Color.appRed, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)

            // Expanded completed tasks
            if isExpanded {
                ForEach(completedTasks) { task in
                    VStack(spacing: 0) {
                        Divider()
                        ExpandableTaskRow(task: task, viewModel: viewModel)

                        if viewModel.isExpanded(task.id) {
                            SubtasksList(parentTask: task, viewModel: viewModel)
                            InlineAddRow(
                                placeholder: "Subtask title",
                                buttonLabel: "Add subtask",
                                onSubmit: { title in await viewModel.createSubtask(title: title, parentId: task.id) },
                                isAnyAddFieldActive: $isInlineAddFocused,
                                verticalPadding: 12
                            )
                            .padding(.leading, 32)
                        }
                    }
                }
            }
        }
        .alert("Clear completed tasks?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task {
                    await viewModel.clearCompletedTasks()
                }
            }
        } message: {
            Text("This will permanently delete \(completedTasks.count) completed task\(completedTasks.count == 1 ? "" : "s").")
        }
    }
}

// MARK: - Flat Task Row (Unified for parents and subtasks)

struct FlatTaskRow: View {
    let task: FocusTask
    @ObservedObject var viewModel: TaskListViewModel
    var isEditMode: Bool = false
    var isSelected: Bool = false
    var onSelectToggle: (() -> Void)? = nil
    @State private var showDeleteConfirmation = false

    private var isParent: Bool { task.parentTaskId == nil }

    var body: some View {
        HStack(spacing: 12) {
            // Edit mode: selection circle (uncompleted parent tasks only)
            if isEditMode && !task.isCompleted && isParent {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.sf(.title3))
                    .foregroundColor(isSelected ? .appRed : .gray)
            }

            // Task content
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(isParent ? .sf(.body) : .sf(.subheadline))
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)

                // Parent: subtask count badge
                if isParent, let subtasks = viewModel.subtasksMap[task.id], !subtasks.isEmpty {
                    let completedCount = subtasks.filter { $0.isCompleted }.count
                    Text("\(completedCount)/\(subtasks.count) subtasks")
                        .font(.sf(.caption))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Completion checkbox (hidden in edit mode)
            if !isEditMode {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    _Concurrency.Task {
                        if isParent {
                            await viewModel.toggleCompletion(task)
                        } else {
                            await viewModel.toggleSubtaskCompletion(task, parentId: task.parentTaskId!)
                        }
                    }
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(isParent ? .sf(.title3) : .sf(.subheadline))
                        .foregroundColor(task.isCompleted ? Color.completedPurple.opacity(0.6) : .gray)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: isParent ? 70 : 44)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode && !task.isCompleted && isParent {
                onSelectToggle?()
            } else if !isEditMode {
                if isParent {
                    // Parent tap: expand/collapse subtasks
                    _Concurrency.Task {
                        await viewModel.toggleExpanded(task.id)
                    }
                } else {
                    // Subtask tap: open details drawer
                    viewModel.selectedTaskForDetails = task
                }
            }
        }
        .contextMenu {
            if !isEditMode && !task.isCompleted {
                ContextMenuItems.editButton {
                    viewModel.selectedTaskForDetails = task
                }

                if isParent {
                    // Priority submenu
                    Menu {
                        ForEach(Priority.allCases, id: \.self) { priority in
                            Button {
                                _Concurrency.Task { await viewModel.updateTaskPriority(task, priority: priority) }
                            } label: {
                                if task.priority == priority {
                                    Label(priority.displayName, systemImage: "checkmark")
                                } else {
                                    Text(priority.displayName)
                                }
                            }
                        }
                    } label: {
                        Label("Priority", systemImage: "flag")
                    }

                    ContextMenuItems.categorySubmenu(
                        currentCategoryId: task.categoryId,
                        categories: viewModel.categories
                    ) { categoryId in
                        _Concurrency.Task { await viewModel.moveTaskToCategory(task, categoryId: categoryId) }
                    }
                }

                Divider()

                ContextMenuItems.deleteButton {
                    if isParent {
                        showDeleteConfirmation = true
                    } else {
                        _Concurrency.Task {
                            await viewModel.deleteSubtask(task, parentId: task.parentTaskId!)
                        }
                    }
                }
            }
        }
        .alert("Delete Task", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                _Concurrency.Task { await viewModel.deleteTask(task) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(task.title)\"?")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isEditMode && !task.isCompleted {
                Button(role: .destructive) {
                    _Concurrency.Task {
                        if isParent {
                            await viewModel.deleteTask(task)
                        } else if let parentId = task.parentTaskId {
                            await viewModel.deleteSubtask(task, parentId: parentId)
                        }
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Expandable Task Row

struct ExpandableTaskRow: View {
    let task: FocusTask
    @ObservedObject var viewModel: TaskListViewModel
    var isEditMode: Bool = false
    var isSelected: Bool = false
    var onSelectToggle: (() -> Void)? = nil
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // Edit mode: selection circle (uncompleted tasks only)
            if isEditMode && !task.isCompleted {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.sf(.title3))
                    .foregroundColor(isSelected ? .appRed : .gray)
            }

            // Task content
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)

                // Subtask count indicator
                if let subtasks = viewModel.subtasksMap[task.id], !subtasks.isEmpty {
                    let completedCount = subtasks.filter { $0.isCompleted }.count
                    Text("\(completedCount)/\(subtasks.count) subtasks")
                        .font(.sf(.caption))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Completion button (hidden in edit mode)
            if !isEditMode {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    _Concurrency.Task {
                        await viewModel.toggleCompletion(task)
                    }
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.sf(.title3))
                        .foregroundColor(task.isCompleted ? Color.completedPurple.opacity(0.6) : .gray)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 70)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode && !task.isCompleted {
                onSelectToggle?()
            } else if !isEditMode {
                _Concurrency.Task {
                    await viewModel.toggleExpanded(task.id)
                }
            }
        }
        .contextMenu {
            if !isEditMode && !task.isCompleted {
                ContextMenuItems.editButton {
                    viewModel.selectedTaskForDetails = task
                }

                if task.parentTaskId == nil {
                    ContextMenuItems.categorySubmenu(
                        currentCategoryId: task.categoryId,
                        categories: viewModel.categories
                    ) { categoryId in
                        _Concurrency.Task { await viewModel.moveTaskToCategory(task, categoryId: categoryId) }
                    }
                }

                Divider()

                ContextMenuItems.deleteButton {
                    showDeleteConfirmation = true
                }
            }
        }
        .alert("Delete Task", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                _Concurrency.Task { await viewModel.deleteTask(task) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(task.title)\"?")
        }
    }
}

// MARK: - Subtasks List

struct SubtasksList: View {
    let parentTask: FocusTask
    @ObservedObject var viewModel: TaskListViewModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.getUncompletedSubtasks(for: parentTask.id)) { subtask in
                SubtaskRow(subtask: subtask, parentId: parentTask.id, viewModel: viewModel)
            }

            ForEach(viewModel.getCompletedSubtasks(for: parentTask.id)) { subtask in
                SubtaskRow(subtask: subtask, parentId: parentTask.id, viewModel: viewModel)
            }
        }
        .padding(.leading, 32)
    }
}

// MARK: - Subtask Row

struct SubtaskRow: View {
    let subtask: FocusTask
    let parentId: UUID
    @ObservedObject var viewModel: TaskListViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text(subtask.title)
                .font(.sf(.subheadline))
                .strikethrough(subtask.isCompleted)
                .foregroundColor(subtask.isCompleted ? .secondary : .primary)

            Spacer()

            // Checkbox on right for thumb access
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    await viewModel.toggleSubtaskCompletion(subtask, parentId: parentId)
                }
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.sf(.subheadline))
                    .foregroundColor(subtask.isCompleted ? Color.completedPurple.opacity(0.6) : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedTaskForDetails = subtask
        }
    }
}

// MARK: - Sort Menu Button

struct SortMenuButton<VM: LogFilterable>: View {
    @ObservedObject var viewModel: VM

    var body: some View {
        Menu {
            // Sort options
            ForEach(SortOption.allCases, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.sortOption = option
                    }
                } label: {
                    if viewModel.sortOption == option {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }

            // Commitment filter
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.commitmentFilter = viewModel.commitmentFilter == .committed ? nil : .committed
                }
            } label: {
                if viewModel.commitmentFilter == .committed {
                    Label("Committed", systemImage: "checkmark")
                } else {
                    Text("Committed")
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.commitmentFilter = viewModel.commitmentFilter == .uncommitted ? nil : .uncommitted
                }
            } label: {
                if viewModel.commitmentFilter == .uncommitted {
                    Label("Not committed", systemImage: "checkmark")
                } else {
                    Text("Not committed")
                }
            }

            Divider()

            // Direction
            ForEach(SortDirection.allCases, id: \.self) { direction in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.sortDirection = direction
                    }
                } label: {
                    if viewModel.sortDirection == direction {
                        Label(direction.displayName, systemImage: "checkmark")
                    } else {
                        Text(direction.displayName)
                    }
                }
            }
        } label: {
            Color.clear
                .frame(width: 36, height: 36)
        }
        .menuIndicator(.hidden)
        .tint(.appRed)
        .background(
            Image(systemName: "arrow.up.arrow.down")
                .font(.sf(.subheadline, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle)
                .allowsHitTesting(false)
        )
    }
}

#Preview {
    NavigationView {
        TasksListView(viewModel: TaskListViewModel(authService: AuthService()))
            .environmentObject(AuthService())
    }
}
