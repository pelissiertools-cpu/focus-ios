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
    var onSearchTap: (() -> Void)? = nil
    @State private var isInlineAddFocused = false
    @State private var showCategoryEditDrawer = false
    @State private var initialLoadComplete = false

    init(viewModel: TaskListViewModel, searchText: String = "", onSearchTap: (() -> Void)? = nil) {
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
            // Category selector header
            CategorySelectorHeader(
                title: categoryTitle,
                count: viewModel.uncompletedTasks.count + viewModel.completedTasks.count,
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
                    ProgressView("Loading tasks...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.tasks.isEmpty {
                    GeometryReader { geometry in
                        ScrollView {
                            emptyState
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
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
        .sheet(isPresented: $showCategoryEditDrawer) {
            CategoryEditDrawer(viewModel: viewModel)
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
            initialLoadComplete = true
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
        VStack(spacing: 4) {
            Text("No tasks yet")
                .font(.sf(.headline))
                .bold()
            Text("Tap + to create your first task")
                .font(.sf(.subheadline))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .listRowBackground(Color.clear)

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
                    .listRowBackground(Color.clear)
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] - 12 }
                    .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] + 12 }

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
                    .listRowBackground(Color.clear)

                case .addTaskRow(let priority):
                    InlineAddRow(
                        placeholder: "Task title",
                        buttonLabel: "Add task",
                        onSubmit: { title in await viewModel.createTask(title: title, categoryId: viewModel.selectedCategoryId, priority: priority) },
                        isAnyAddFieldActive: $isInlineAddFocused,
                        verticalPadding: 12
                    )
                    .moveDisabled(true)
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                    .listRowBackground(Color.clear)
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
                    .listRowBackground(Color.clear)
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

            HStack(spacing: 8) {
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
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggle()
            }
            .frame(minHeight: 70, alignment: .bottom)

            Rectangle()
                .fill(Color.secondary.opacity(0.7))
                .frame(height: 1)
                .padding(.leading, 16)
                .padding(.trailing, 4)
        }
    }
}

// MARK: - Category Selector Header

struct CategorySelectorHeader<TrailingContent: View>: View {
    let title: String
    let count: Int
    let countSuffix: String
    let categories: [Category]
    let selectedCategoryId: UUID?
    let onSelectCategory: (UUID?) -> Void
    let onEdit: (() -> Void)?
    let trailingContent: TrailingContent

    init(
        title: String,
        count: Int,
        countSuffix: String = "task",
        categories: [Category],
        selectedCategoryId: UUID?,
        onSelectCategory: @escaping (UUID?) -> Void,
        onEdit: (() -> Void)? = nil,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.count = count
        self.countSuffix = countSuffix
        self.categories = categories
        self.selectedCategoryId = selectedCategoryId
        self.onSelectCategory = onSelectCategory
        self.onEdit = onEdit
        self.trailingContent = trailingContent()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                // Title displayed independently (not inside Menu label to avoid clip animation)
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(.golosText(size: 30))
                        .foregroundColor(.primary)

                    Text("\(count) \(countSuffix)\(count == 1 ? "" : "s")")
                        .font(.sf(size: 12))
                        .foregroundColor(.secondary)
                }
                .overlay {
                    // Invisible Menu tap target overlaid on top of the title
                    Menu {
                        // Header
                        Label("Category", systemImage: "folder")
                            .foregroundColor(.primary)

                        Divider()

                        // All categories
                        Button {
                            onSelectCategory(nil)
                        } label: {
                            if selectedCategoryId == nil {
                                Label("All", systemImage: "checkmark")
                                    .foregroundColor(.appRed)
                            } else {
                                Text("All")
                                    .foregroundColor(.primary)
                            }
                        }

                        ForEach(categories) { category in
                            Button {
                                onSelectCategory(category.id)
                            } label: {
                                if selectedCategoryId == category.id {
                                    Label(category.name, systemImage: "checkmark")
                                        .foregroundColor(.appRed)
                                } else {
                                    Text(category.name)
                                        .foregroundColor(.primary)
                                }
                            }
                        }

                        if onEdit != nil {
                            Divider()

                            Button {
                                onEdit?()
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .foregroundColor(.appRed)
                            }
                        }
                    } label: {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .menuIndicator(.hidden)
                    .tint(.appRed)
                }

                Spacer()

                trailingContent
                    .padding(.bottom, 6)
            }
            .padding(.vertical, 6)
            .padding(.leading, 22)
            .padding(.trailing, 9)

            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
                .padding(.leading, 4)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 16)
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
                            .background(Color.darkGray, in: Capsule())
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
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.sf(.title3))
                    .foregroundColor(isSelected ? .appRed : .secondary)
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
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.sf(.title3))
                    .foregroundColor(isSelected ? .appRed : .secondary)
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

// MARK: - Unified Options Menu Button

struct SortMenuButton<VM: LogFilterable>: View {
    @ObservedObject var viewModel: VM

    var body: some View {
        Menu {
            // Sort By submenu
            Menu {
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
                Toggle("Scheduled", isOn: Binding(
                    get: { viewModel.commitmentFilter == .committed },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.commitmentFilter = newValue ? .committed : nil
                        }
                    }
                ))

                Toggle("Unscheduled", isOn: Binding(
                    get: { viewModel.commitmentFilter == .uncommitted },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.commitmentFilter = newValue ? .uncommitted : nil
                        }
                    }
                ))

                Divider()

                // Direction
                ForEach(viewModel.sortOption.directionOrder, id: \.self) { direction in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.sortDirection = direction
                        }
                    } label: {
                        if viewModel.sortDirection == direction {
                            Label(direction.displayName(for: viewModel.sortOption), systemImage: "checkmark")
                        } else {
                            Text(direction.displayName(for: viewModel.sortOption))
                        }
                    }
                }
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }

            Divider()

            // Multiple actions
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.enterEditMode()
                }
            } label: {
                Label("Multiple actions", systemImage: "checkmark.circle")
            }
        } label: {
            Color.clear
                .frame(width: 36, height: 36)
        }
        .menuIndicator(.hidden)
        .tint(.appRed)
        .background(
            Image(systemName: "ellipsis")
                .font(.sf(.body, weight: .semibold))
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
