//
//  TasksListView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI
import Auth

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

    init(viewModel: TaskListViewModel, searchText: String = "", isSearchFocused: Binding<Bool> = .constant(false)) {
        self.viewModel = viewModel
        self.searchText = searchText
        self._isSearchFocused = isSearchFocused
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView("Loading tasks...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var taskList: some View {
        List {
            // Uncompleted tasks — reorderable via List's native drag
            ForEach(viewModel.uncompletedTasks) { task in
                VStack(spacing: 0) {
                    ExpandableTaskRow(
                        task: task,
                        viewModel: viewModel,
                        isEditMode: viewModel.isEditMode,
                        isSelected: viewModel.selectedTaskIds.contains(task.id),
                        onSelectToggle: { viewModel.toggleTaskSelection(task.id) }
                    )

                    if !viewModel.isEditMode && viewModel.isExpanded(task.id) {
                        SubtasksList(parentTask: task, viewModel: viewModel)
                        InlineAddSubtaskRow(parentId: task.id, viewModel: viewModel)
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color(.systemBackground))
            }
            .onMove { from, to in
                viewModel.moveTask(from: from, to: to)
            }

            // Done pill (when there are completed tasks, hidden in edit mode)
            if !viewModel.isEditMode && !viewModel.completedTasks.isEmpty {
                LogDonePillView(completedTasks: viewModel.completedTasks, viewModel: viewModel)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color(.systemBackground))
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
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

// MARK: - Log Done Pill View

struct LogDonePillView: View {
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

                    Text("Completed")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text("(\(completedTasks.count))")
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
                    _Concurrency.Task {
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
        // Context menu: long-press shows quick actions
        .contextMenu {
            if !isEditMode && !task.isCompleted {
                Button {
                    viewModel.selectedTaskForDetails = task
                } label: {
                    Label("Edit Details", systemImage: "pencil")
                }

                // Move to category (parent tasks only, not committed)
                if task.parentTaskId == nil {
                    Menu {
                        Button {
                            _Concurrency.Task { await viewModel.moveTaskToCategory(task, categoryId: nil) }
                        } label: {
                            if task.categoryId == nil {
                                Label("None", systemImage: "checkmark")
                            } else {
                                Text("None")
                            }
                        }
                        ForEach(viewModel.categories) { category in
                            Button {
                                _Concurrency.Task { await viewModel.moveTaskToCategory(task, categoryId: category.id) }
                            } label: {
                                if task.categoryId == category.id {
                                    Label(category.name, systemImage: "checkmark")
                                } else {
                                    Text(category.name)
                                }
                            }
                        }
                    } label: {
                        Label("Move to Category", systemImage: "folder")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    _Concurrency.Task { await viewModel.deleteTask(task) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
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
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
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
        .padding(.vertical, 12)
        .padding(.leading, 32)
        .onChange(of: isFocused) { _, focused in
            if !focused {
                isEditing = false
                newSubtaskTitle = ""
            }
        }
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
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @EnvironmentObject var authService: AuthService
    @State private var taskTitle = ""
    @State private var draftSubtasks: [DraftSubtaskEntry] = []
    @State private var selectedCategoryId: UUID? = nil
    @State private var showNewCategory = false
    @State private var newCategoryName = ""
    @State private var commitAfterCreate = false
    @State private var selectedTimeframe: Timeframe = .daily
    @State private var selectedSection: Section = .focus
    @State private var selectedDates: Set<Date> = []
    @State private var hasScheduledTime = false
    @State private var scheduledTime: Date = {
        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: now)
        let roundUp = ((minute / 15) + 1) * 15
        return calendar.date(byAdding: .minute, value: roundUp - minute, to: now) ?? now
    }()
    @State private var sheetDetent: PresentationDetent = .fraction(0.75)
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
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

                    // Commit & schedule toggles
                    CommitScheduleSection(
                        commitAfterCreate: $commitAfterCreate,
                        selectedTimeframe: $selectedTimeframe,
                        selectedSection: $selectedSection,
                        selectedDates: $selectedDates,
                        hasScheduledTime: $hasScheduledTime,
                        scheduledTime: $scheduledTime
                    )

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
                    .id("addTaskButton")
                }
                .padding()
            }
            .onChange(of: commitAfterCreate) { _, isOn in
                if isOn {
                    titleFocused = false
                }
                withAnimation {
                    sheetDetent = isOn ? .large : .fraction(0.75)
                }
                if isOn {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            proxy.scrollTo("addTaskButton", anchor: .bottom)
                        }
                    }
                }
            }
            } // ScrollViewReader
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
            .presentationDetents([.fraction(0.75), .large], selection: $sheetDetent)
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
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

            // Create commitments if commit toggle is on and dates selected
            if commitAfterCreate && !selectedDates.isEmpty {
                guard let userId = authService.currentUser?.id else { return }
                let commitmentRepository = CommitmentRepository()
                for date in selectedDates {
                    let commitment = Commitment(
                        userId: userId,
                        taskId: parentId,
                        timeframe: selectedTimeframe,
                        section: selectedSection,
                        commitmentDate: date,
                        sortOrder: 0,
                        scheduledTime: hasScheduledTime ? scheduledTime : nil,
                        durationMinutes: hasScheduledTime ? 30 : nil
                    )
                    _ = try? await commitmentRepository.createCommitment(commitment)
                }
                await focusViewModel.fetchCommitments()
                await viewModel.fetchCommittedTaskIds()
            }

            // Reset fields for next task (keep category selection)
            taskTitle = ""
            draftSubtasks = []
            commitAfterCreate = false
            hasScheduledTime = false
            selectedDates = []
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
