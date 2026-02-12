//
//  TaskDetailsDrawer.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct TaskDetailsDrawer<VM: TaskEditingViewModel>: View {
    let task: FocusTask
    let commitment: Commitment?
    let categories: [Category]
    @ObservedObject var viewModel: VM
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @State private var taskTitle: String
    @State private var showingCommitmentSheet = false
    @State private var showingRescheduleSheet = false
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var newSubtaskTitle: String = ""
    @FocusState private var isFocused: Bool
    @FocusState private var isNewSubtaskFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isSubtask: Bool {
        task.parentTaskId != nil
    }

    private var parentTask: FocusTask? {
        guard let parentId = task.parentTaskId else { return nil }
        return viewModel.findTask(byId: parentId)
    }

    private var subtasks: [FocusTask] {
        viewModel.getSubtasks(for: task.id)
    }

    private var currentCategoryName: String {
        if let categoryId = task.categoryId,
           let category = categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "None"
    }

    init(task: FocusTask, viewModel: VM, commitment: Commitment? = nil, categories: [Category] = []) {
        self.task = task
        self.viewModel = viewModel
        self.commitment = commitment
        self.categories = categories
        _taskTitle = State(initialValue: task.title)
    }

    private func nextTimeframeLabel(for timeframe: Timeframe) -> String {
        switch timeframe {
        case .daily: return "Tomorrow"
        case .weekly: return "Next Week"
        case .monthly: return "Next Month"
        case .yearly: return "Next Year"
        }
    }

    var body: some View {
        NavigationView {
            List {
                // Edit Title Section
                SwiftUI.Section("Title") {
                    TextField("Task title", text: $taskTitle)
                        .focused($isFocused)
                        .onSubmit {
                            saveTitle()
                        }
                }

                // Info Section - shows parent or subtask count
                if isSubtask {
                    SwiftUI.Section("Parent Task") {
                        if let parent = parentTask {
                            Label(parent.title, systemImage: "arrow.up.circle")
                                .foregroundColor(.secondary)
                        } else {
                            Label("Subtask", systemImage: "arrow.up.circle")
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    // Subtasks Section (for parent tasks - show even if empty to allow adding)
                    SwiftUI.Section {
                        // Summary header
                        if !subtasks.isEmpty {
                            let completedCount = subtasks.filter { $0.isCompleted }.count
                            Label("\(completedCount)/\(subtasks.count) completed", systemImage: "checklist")
                                .foregroundColor(.secondary)
                        }

                        // Editable subtask rows
                        ForEach(subtasks) { subtask in
                            DrawerSubtaskRow(subtask: subtask, parentId: task.id, viewModel: viewModel)
                        }
                        .onDelete { indexSet in
                            deleteSubtasks(at: indexSet)
                        }

                        // Add subtask row
                        HStack {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.accentColor)
                            TextField("Add subtask", text: $newSubtaskTitle)
                                .focused($isNewSubtaskFocused)
                                .onSubmit {
                                    addSubtask()
                                }
                        }
                    } header: {
                        Text("Subtasks")
                    }
                }

                // Actions Section
                SwiftUI.Section {
                    // Move to category (only for parent tasks in Library view)
                    if !isSubtask && commitment == nil {
                        Menu {
                            Button {
                                moveTask(to: nil)
                            } label: {
                                if task.categoryId == nil {
                                    Label("None", systemImage: "checkmark")
                                } else {
                                    Text("None")
                                }
                            }
                            ForEach(categories) { category in
                                Button {
                                    moveTask(to: category.id)
                                } label: {
                                    if task.categoryId == category.id {
                                        Label(category.name, systemImage: "checkmark")
                                    } else {
                                        Text(category.name)
                                    }
                                }
                            }
                            Divider()
                            Button {
                                showingNewCategoryAlert = true
                            } label: {
                                Label("New Category", systemImage: "plus")
                            }
                        } label: {
                            HStack {
                                Label("Move to", systemImage: "folder")
                                Spacer()
                                Text(currentCategoryName)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Commit to Focus (only shown when not already committed)
                    if commitment == nil {
                        Button {
                            showingCommitmentSheet = true
                        } label: {
                            Label("Commit to Focus", systemImage: "arrow.right.circle")
                        }
                    }

                    // Remove from Focus (only shown when committed - cascades to child commitments)
                    if let commitment = commitment {
                        Button(role: .destructive) {
                            Task {
                                await focusViewModel.removeCommitment(commitment)
                                dismiss()
                            }
                        } label: {
                            Label("Remove from Focus", systemImage: "minus.circle")
                        }
                    }

                    // Commit to lower timeframe (for non-daily commitments)
                    if let commitment = commitment,
                       commitment.canBreakdown,
                       let childTimeframe = commitment.childTimeframe {
                        Button {
                            focusViewModel.selectedCommitmentForCommit = commitment
                            focusViewModel.showCommitSheet = true
                            dismiss()
                        } label: {
                            Label("Commit to \(childTimeframe.displayName)", systemImage: "arrow.down.forward.circle")
                        }
                    }

                    // Commit Subtask to lower timeframe (for subtasks without their own commitment)
                    if isSubtask && commitment == nil {
                        // Find parent's commitment at current timeframe
                        if let parentId = task.parentTaskId,
                           let parentCommitment = focusViewModel.commitments.first(where: {
                               $0.taskId == parentId &&
                               focusViewModel.isSameTimeframe($0.commitmentDate, timeframe: focusViewModel.selectedTimeframe, selectedDate: focusViewModel.selectedDate)
                           }),
                           parentCommitment.timeframe != .daily {
                            Button {
                                focusViewModel.selectedSubtaskForCommit = task
                                focusViewModel.selectedParentCommitmentForSubtaskCommit = parentCommitment
                                focusViewModel.showSubtaskCommitSheet = true
                                dismiss()
                            } label: {
                                Label("Commit to \(parentCommitment.childTimeframe?.displayName ?? "...")", systemImage: "arrow.down.forward.circle")
                            }
                        }
                    }

                    // Reschedule (any non-completed parent task in Focus view)
                    if commitment != nil, !isSubtask, !task.isCompleted {
                        Button {
                            showingRescheduleSheet = true
                        } label: {
                            Label("Reschedule", systemImage: "calendar")
                        }
                    }

                    // Unschedule (remove from calendar timeline, keep commitment)
                    if let commitment = commitment, commitment.scheduledTime != nil {
                        Button {
                            _Concurrency.Task { @MainActor in
                                await focusViewModel.unscheduleCommitment(commitment.id)
                                dismiss()
                            }
                        } label: {
                            Label("Unschedule", systemImage: "calendar.badge.minus")
                        }
                    }

                    // Push to Next (any non-completed parent task in Focus view)
                    if let commitment = commitment, !isSubtask, !task.isCompleted {
                        Button {
                            Task {
                                let success = await focusViewModel.pushCommitmentToNext(commitment)
                                if success {
                                    dismiss()
                                }
                                // If failed (section full), error message shown, drawer stays open
                            }
                        } label: {
                            Label("Push to \(nextTimeframeLabel(for: commitment.timeframe))", systemImage: "arrow.turn.right.down")
                        }
                    }

                    // Delete - only show for:
                    // 1. Subtasks (always deletable)
                    // 2. Tasks in Library view (no commitment)
                    // 3. Focus-origin tasks (not from Library)
                    // Do NOT show for Library-origin tasks when viewing in Focus (use Remove from Focus instead)
                    if isSubtask {
                        Button(role: .destructive) {
                            Task {
                                if let parentId = task.parentTaskId {
                                    await viewModel.deleteSubtask(task, parentId: parentId)
                                }
                                dismiss()
                            }
                        } label: {
                            Label("Delete Subtask", systemImage: "trash")
                        }
                    } else if commitment == nil {
                        // Library view - can delete task
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteTask(task)
                                dismiss()
                            }
                        } label: {
                            Label("Delete Task", systemImage: "trash")
                        }
                    } else if !task.isInLibrary {
                        // Focus-origin task - can delete
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteTask(task)
                                dismiss()
                            }
                        } label: {
                            Label("Delete Task", systemImage: "trash")
                        }
                    }
                    // Note: Library-origin tasks in Focus view only see "Remove from Focus"
                }
            }
            .navigationTitle(isSubtask ? "Subtask Details" : "Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        saveTitle()
                        dismiss()
                    }
                }
            }
            .alert("New Category", isPresented: $showingNewCategoryAlert) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Create") { createAndMoveToCategory() }
            } message: {
                Text("Enter a name for the new category.")
            }
            .sheet(isPresented: $showingCommitmentSheet) {
                CommitmentSelectionSheet(task: task, focusViewModel: focusViewModel)
                    .drawerStyle()
            }
            .sheet(isPresented: $showingRescheduleSheet) {
                if let commitment = commitment {
                    RescheduleSheet(commitment: commitment, focusViewModel: focusViewModel)
                        .drawerStyle()
                }
            }
        }
    }

    private func saveTitle() {
        guard taskTitle != task.title else { return }
        Task {
            await viewModel.updateTask(task, newTitle: taskTitle)
        }
    }

    private func addSubtask() {
        guard !newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let title = newSubtaskTitle
        newSubtaskTitle = ""
        Task {
            // In Focus view context (when we have a commitment), pass the commitment
            // so the new subtask gets its own commitment at the same timeframe
            if let commitment = commitment {
                await focusViewModel.createSubtask(title: title, parentId: task.id, parentCommitment: commitment)
            } else {
                await viewModel.createSubtask(title: title, parentId: task.id)
            }
        }
    }

    private func moveTask(to categoryId: UUID?) {
        Task {
            await viewModel.moveTaskToCategory(task, categoryId: categoryId)
            dismiss()
        }
    }

    private func createAndMoveToCategory() {
        let name = newCategoryName
        newCategoryName = ""
        Task {
            await viewModel.createCategoryAndMove(name: name, task: task)
            dismiss()
        }
    }

    private func deleteSubtasks(at indexSet: IndexSet) {
        for index in indexSet {
            let subtask = subtasks[index]
            Task {
                await viewModel.deleteSubtask(subtask, parentId: task.id)
            }
        }
    }
}

// MARK: - Subtask Row for Drawer

struct DrawerSubtaskRow<VM: TaskEditingViewModel>: View {
    let subtask: FocusTask
    let parentId: UUID
    @ObservedObject var viewModel: VM
    @State private var editingTitle: String
    @FocusState private var isEditing: Bool

    init(subtask: FocusTask, parentId: UUID, viewModel: VM) {
        self.subtask = subtask
        self.parentId = parentId
        self.viewModel = viewModel
        _editingTitle = State(initialValue: subtask.title)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Completion toggle
            Button {
                Task {
                    await viewModel.toggleSubtaskCompletion(subtask, parentId: parentId)
                }
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(subtask.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)

            // Editable title
            TextField("Subtask", text: $editingTitle)
                .strikethrough(subtask.isCompleted)
                .foregroundColor(subtask.isCompleted ? .secondary : .primary)
                .focused($isEditing)
                .onSubmit {
                    saveSubtaskTitle()
                }
                .onChange(of: isEditing) { _, editing in
                    if !editing {
                        saveSubtaskTitle()
                    }
                }
        }
    }

    private func saveSubtaskTitle() {
        guard editingTitle != subtask.title else { return }
        Task {
            await viewModel.updateTask(subtask, newTitle: editingTitle)
        }
    }
}
