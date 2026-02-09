//
//  TasksListView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

// MARK: - Row Frame Preference Key

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
    @Binding var isSearchFocused: Bool

    // Drag state
    @State private var draggingTaskId: UUID?
    @State private var draggingSubtaskId: UUID?
    @State private var draggingSubtaskParentId: UUID?
    @State private var dragFingerY: CGFloat = 0          // finger Y in coordinate space (for reorder checks)
    @State private var dragTranslation: CGFloat = 0       // raw finger delta from start
    @State private var dragReorderAdjustment: CGFloat = 0 // compensates for layout shifts on reorder
    @State private var lastReorderTime: Date = .distantPast
    @State private var rowFrames: [UUID: CGRect] = [:]

    init(viewModel: TaskListViewModel, searchText: String = "", isSearchFocused: Binding<Bool> = .constant(false)) {
        self.viewModel = viewModel
        self.searchText = searchText
        self._isSearchFocused = isSearchFocused
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView("Loading tasks...")
            } else if viewModel.tasks.isEmpty {
                emptyState
            } else {
                taskList
            }

            // Tap-to-dismiss overlay when search is focused
            if isSearchFocused {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isSearchFocused = false
                    }
            }
        }
        .padding(.top, 44)
        .sheet(isPresented: $viewModel.showingAddTask) {
            AddTaskSheet(viewModel: viewModel)
                .drawerStyle()
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
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Tasks Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the + button to add your first task")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var taskList: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Uncompleted tasks — reorderable via handle drag
                ForEach(Array(viewModel.uncompletedTasks.enumerated()), id: \.element.id) { index, task in
                    let isDragging = draggingTaskId == task.id

                    VStack(spacing: 0) {
                        if index > 0 {
                            Divider()
                        }
                        ExpandableTaskRow(
                            task: task,
                            viewModel: viewModel,
                            onDragChanged: viewModel.isEditMode ? nil : { value in handleTaskDrag(task.id, value) },
                            onDragEnded: viewModel.isEditMode ? nil : { handleTaskDragEnd() },
                            isEditMode: viewModel.isEditMode,
                            isSelected: viewModel.selectedTaskIds.contains(task.id),
                            onSelectToggle: { viewModel.toggleTaskSelection(task.id) }
                        )

                        if !viewModel.isEditMode && viewModel.isExpanded(task.id) {
                            SubtasksList(
                                parentTask: task,
                                viewModel: viewModel,
                                draggingSubtaskId: draggingSubtaskId,
                                dragTranslation: dragTranslation,
                                dragReorderAdjustment: dragReorderAdjustment,
                                dragFingerY: dragFingerY,
                                rowFrames: rowFrames,
                                onSubtaskDragChanged: { subtaskId, value in
                                    handleSubtaskDrag(subtaskId, parentId: task.id, value)
                                },
                                onSubtaskDragEnded: { handleSubtaskDragEnd() }
                            )
                            InlineAddSubtaskRow(parentId: task.id, viewModel: viewModel)
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: RowFramePreference.self,
                                value: [task.id: geo.frame(in: .named("taskList"))]
                            )
                        }
                    )
                    .background(Color(.systemBackground))
                    .offset(y: isDragging ? (dragTranslation + dragReorderAdjustment) : 0)
                    .scaleEffect(isDragging ? 1.03 : 1.0)
                    .shadow(color: .black.opacity(isDragging ? 0.15 : 0), radius: 8, y: 2)
                    .zIndex(isDragging ? 1 : 0)
                    .transaction { t in
                        if isDragging { t.animation = nil }
                    }
                }

                // Done pill (when there are completed tasks, hidden in edit mode)
                if !viewModel.isEditMode && !viewModel.completedTasks.isEmpty {
                    Divider()
                    LibraryDonePillView(completedTasks: viewModel.completedTasks, viewModel: viewModel)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 100)
            .onPreferenceChange(RowFramePreference.self) { frames in
                rowFrames = frames
            }
        }
        .coordinateSpace(name: "taskList")
    }

    // MARK: - Task Drag Handlers

    private func handleTaskDrag(_ taskId: UUID, _ value: DragGesture.Value) {
        // Don't start a task drag if a subtask drag is active
        guard draggingSubtaskId == nil else { return }

        if draggingTaskId == nil {
            withAnimation(.easeInOut(duration: 0.15)) {
                draggingTaskId = taskId
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        dragTranslation = value.translation.height
        dragFingerY = value.location.y

        // Cooldown: prevent double-swaps during animation
        guard Date().timeIntervalSince(lastReorderTime) > 0.25 else { return }

        // Check midpoint crossings for reorder
        let uncompleted = viewModel.uncompletedTasks
        guard let currentIdx = uncompleted.firstIndex(where: { $0.id == taskId }) else { return }

        for (idx, other) in uncompleted.enumerated() where other.id != taskId {
            guard let frame = rowFrames[other.id] else { continue }
            let crossedDown = idx > currentIdx && dragFingerY > frame.midY
            let crossedUp = idx < currentIdx && dragFingerY < frame.midY
            if crossedDown || crossedUp {
                // Adjust offset to compensate for layout shift
                let passedHeight = frame.height
                dragReorderAdjustment += crossedDown ? -passedHeight : passedHeight

                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.reorderTask(droppedId: taskId, targetId: other.id)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                lastReorderTime = Date()
                break
            }
        }
    }

    private func handleTaskDragEnd() {
        withAnimation(.easeInOut(duration: 0.2)) {
            draggingTaskId = nil
            dragTranslation = 0
            dragReorderAdjustment = 0
            dragFingerY = 0
        }
        lastReorderTime = .distantPast
    }

    // MARK: - Subtask Drag Handlers

    private func handleSubtaskDrag(_ subtaskId: UUID, parentId: UUID, _ value: DragGesture.Value) {
        // Don't start a subtask drag if a task drag is active
        guard draggingTaskId == nil else { return }

        if draggingSubtaskId == nil {
            withAnimation(.easeInOut(duration: 0.15)) {
                draggingSubtaskId = subtaskId
                draggingSubtaskParentId = parentId
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        dragTranslation = value.translation.height
        dragFingerY = value.location.y

        // Cooldown: prevent double-swaps during animation
        guard Date().timeIntervalSince(lastReorderTime) > 0.25 else { return }

        let uncompleted = viewModel.getUncompletedSubtasks(for: parentId)
        guard let currentIdx = uncompleted.firstIndex(where: { $0.id == subtaskId }) else { return }

        for (idx, other) in uncompleted.enumerated() where other.id != subtaskId {
            guard let frame = rowFrames[other.id] else { continue }
            let crossedDown = idx > currentIdx && dragFingerY > frame.midY
            let crossedUp = idx < currentIdx && dragFingerY < frame.midY
            if crossedDown || crossedUp {
                // Adjust offset to compensate for layout shift
                let passedHeight = frame.height
                dragReorderAdjustment += crossedDown ? -passedHeight : passedHeight

                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.reorderSubtask(droppedId: subtaskId, targetId: other.id, parentId: parentId)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                lastReorderTime = Date()
                break
            }
        }
    }

    private func handleSubtaskDragEnd() {
        withAnimation(.easeInOut(duration: 0.2)) {
            draggingSubtaskId = nil
            draggingSubtaskParentId = nil
            dragTranslation = 0
            dragReorderAdjustment = 0
            dragFingerY = 0
        }
        lastReorderTime = .distantPast
    }
}

// MARK: - Library Done Pill View

struct LibraryDonePillView: View {
    let completedTasks: [FocusTask]
    @ObservedObject var viewModel: TaskListViewModel
    @State private var showClearConfirmation = false

    private var isExpanded: Bool {
        !viewModel.isDoneSubsectionCollapsed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Done pill header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleDoneSubsectionCollapsed()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Done")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text("(\(completedTasks.count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Clear list pill button (only visible when expanded)
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
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded completed tasks
            if isExpanded {
                ForEach(completedTasks) { task in
                    VStack(spacing: 0) {
                        Divider()
                        ExpandableTaskRow(task: task, viewModel: viewModel)

                        if viewModel.isExpanded(task.id) {
                            SubtasksList(parentTask: task, viewModel: viewModel)
                            InlineAddSubtaskRow(parentId: task.id, viewModel: viewModel)
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

// MARK: - Expandable Task Row

struct ExpandableTaskRow: View {
    let task: FocusTask
    @ObservedObject var viewModel: TaskListViewModel
    var onDragChanged: ((DragGesture.Value) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    var isEditMode: Bool = false
    var isSelected: Bool = false
    var onSelectToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Edit mode: selection circle (uncompleted tasks only)
            if isEditMode && !task.isCompleted {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
            } else if !task.isCompleted && onDragChanged != nil && !isEditMode {
                // Drag handle (normal mode only)
                DragHandleView()
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .named("taskList"))
                            .onChanged { value in onDragChanged?(value) }
                            .onEnded { _ in onDragEnded?() }
                    )
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
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Completion button (hidden in edit mode)
            if !isEditMode {
                Button {
                    Task {
                        await viewModel.toggleCompletion(task)
                    }
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(task.isCompleted ? .green : .gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode && !task.isCompleted {
                onSelectToggle?()
            } else if !isEditMode {
                Task {
                    await viewModel.toggleExpanded(task.id)
                }
            }
        }
        .onLongPressGesture {
            if !isEditMode {
                viewModel.selectedTaskForDetails = task
            }
        }
    }
}

// MARK: - Subtasks List

struct SubtasksList: View {
    let parentTask: FocusTask
    @ObservedObject var viewModel: TaskListViewModel
    var draggingSubtaskId: UUID? = nil
    var dragTranslation: CGFloat = 0
    var dragReorderAdjustment: CGFloat = 0
    var dragFingerY: CGFloat = 0
    var rowFrames: [UUID: CGRect] = [:]
    var onSubtaskDragChanged: ((UUID, DragGesture.Value) -> Void)? = nil
    var onSubtaskDragEnded: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Uncompleted subtasks — reorderable via handle drag
            ForEach(viewModel.getUncompletedSubtasks(for: parentTask.id)) { subtask in
                let isDragging = draggingSubtaskId == subtask.id

                SubtaskRow(
                    subtask: subtask,
                    parentId: parentTask.id,
                    viewModel: viewModel,
                    onDragChanged: onSubtaskDragChanged != nil
                        ? { value in onSubtaskDragChanged?(subtask.id, value) }
                        : nil,
                    onDragEnded: onSubtaskDragEnded
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: RowFramePreference.self,
                            value: [subtask.id: geo.frame(in: .named("taskList"))]
                        )
                    }
                )
                .background(Color(.systemBackground))
                .offset(y: isDragging ? (dragTranslation + dragReorderAdjustment) : 0)
                .scaleEffect(isDragging ? 1.03 : 1.0)
                .shadow(color: .black.opacity(isDragging ? 0.15 : 0), radius: 8, y: 2)
                .zIndex(isDragging ? 1 : 0)
                .transaction { t in
                    if isDragging { t.animation = nil }
                }
            }

            // Completed subtasks — not draggable
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
    var onDragChanged: ((DragGesture.Value) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Drag handle (only for uncompleted subtasks with drag enabled)
            if !subtask.isCompleted && onDragChanged != nil {
                DragHandleView()
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .named("taskList"))
                            .onChanged { value in onDragChanged?(value) }
                            .onEnded { _ in onDragEnded?() }
                    )
            }

            Text(subtask.title)
                .font(.subheadline)
                .strikethrough(subtask.isCompleted)
                .foregroundColor(subtask.isCompleted ? .secondary : .primary)

            Spacer()

            // Checkbox on right for thumb access
            Button {
                Task {
                    await viewModel.toggleSubtaskCompletion(subtask, parentId: parentId)
                }
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundColor(subtask.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onLongPressGesture {
            viewModel.selectedTaskForDetails = subtask
        }
    }
}

// MARK: - Inline Add Subtask Row

struct InlineAddSubtaskRow: View {
    let parentId: UUID
    @ObservedObject var viewModel: TaskListViewModel
    @State private var newSubtaskTitle = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isEditing {
                TextField("Subtask title", text: $newSubtaskTitle)
                    .font(.subheadline)
                    .focused($isFocused)
                    .onSubmit {
                        submitSubtask()
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
        .padding(.vertical, 6)
        .padding(.leading, 32)
    }

    private func submitSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            isEditing = false
            return
        }

        Task {
            await viewModel.createSubtask(title: title, parentId: parentId)
            newSubtaskTitle = ""
            // Keep editing mode open for adding more subtasks
        }
    }
}

struct AddTaskSheet: View {
    @ObservedObject var viewModel: TaskListViewModel
    @State private var taskTitle = ""
    @State private var draftSubtasks: [DraftSubtaskEntry] = []
    @State private var selectedCategoryId: UUID? = nil
    @State private var showNewCategory = false
    @State private var newCategoryName = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Task title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Task")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)

                        TextField("What do you need to do?", text: $taskTitle)
                            .textFieldStyle(.roundedBorder)
                            .focused($titleFocused)
                    }

                    // Subtasks
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subtasks")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)

                        ForEach(Array(draftSubtasks.enumerated()), id: \.element.id) { index, _ in
                            HStack(spacing: 8) {
                                Image(systemName: "circle")
                                    .font(.caption)
                                    .foregroundColor(.gray.opacity(0.5))

                                TextField("Subtask title", text: $draftSubtasks[index].title)
                                    .font(.subheadline)

                                Button {
                                    draftSubtasks.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.leading, 4)
                        }

                        Button {
                            draftSubtasks.append(DraftSubtaskEntry())
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.subheadline)
                                Text("Add subtask")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 4)
                    }

                    // Category picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)

                        HStack {
                            Picker("Category", selection: $selectedCategoryId) {
                                Text("None").tag(nil as UUID?)
                                ForEach(viewModel.categories) { category in
                                    Text(category.name).tag(category.id as UUID?)
                                }
                            }
                            .pickerStyle(.menu)

                            Spacer()

                            Button {
                                showNewCategory = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text("New")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }

                        if showNewCategory {
                            HStack {
                                TextField("Category name", text: $newCategoryName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.subheadline)

                                Button("Add") {
                                    submitNewCategory()
                                }
                                .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }

                    // Add Task button
                    Button {
                        addTask()
                    } label: {
                        Text("Add Task")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(taskTitle.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? Color.blue.opacity(0.5)
                                          : Color.blue)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(taskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        viewModel.showingAddTask = false
                    }
                }
            }
            .onAppear {
                titleFocused = true
            }
        }
    }

    private func addTask() {
        let title = taskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let subtasksToCreate = draftSubtasks
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let categoryToAssign = selectedCategoryId

        _Concurrency.Task { @MainActor in
            guard let parentId = await viewModel.createTask(title: title, categoryId: categoryToAssign) else {
                return
            }

            for subtaskTitle in subtasksToCreate {
                await viewModel.createSubtask(title: subtaskTitle, parentId: parentId)
            }

            // Reset fields for next task (keep category selection)
            taskTitle = ""
            draftSubtasks = []
            titleFocused = true
        }
    }

    private func submitNewCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        _Concurrency.Task {
            await viewModel.createCategory(name: name)
            if let created = viewModel.categories.last {
                selectedCategoryId = created.id
            }
            newCategoryName = ""
            showNewCategory = false
        }
    }
}

// MARK: - Draft Subtask Entry (for AddTaskSheet)

struct DraftSubtaskEntry: Identifiable {
    let id = UUID()
    var title: String = ""
}

#Preview {
    NavigationView {
        TasksListView(viewModel: TaskListViewModel(authService: AuthService()))
            .environmentObject(AuthService())
    }
}
