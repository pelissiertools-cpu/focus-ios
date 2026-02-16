//
//  TaskDetailsDrawer.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI
import Auth

struct TaskDetailsDrawer<VM: TaskEditingViewModel>: View {
    let task: FocusTask
    let commitment: Commitment?
    let categories: [Category]
    @ObservedObject var viewModel: VM
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @EnvironmentObject var authService: AuthService
    @State private var taskTitle: String
    @State private var showingCommitmentSheet = false
    @State private var showingRescheduleSheet = false
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var newSubtaskTitle: String = ""
    @State private var showNewSubtaskField = false
    @State private var showingDeleteConfirmation = false
    @State private var showingBreakdownDrawer = false
    @State private var pendingDeletions: Set<UUID> = []
    @FocusState private var isTitleFocused: Bool
    @FocusState private var focusedSubtaskId: UUID?
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
            .filter { !pendingDeletions.contains($0.id) }
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

    private var hasChanges: Bool {
        taskTitle != task.title || !pendingDeletions.isEmpty || !newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        DrawerContainer(
            title: isSubtask ? "Subtask Details" : "Task Details",
            leadingButton: .close { dismiss() },
            trailingButton: .check(action: {
                saveTitle()
                addSubtask()
                commitPendingDeletions()
                dismiss()
            }, highlighted: hasChanges)
        ) {
            ScrollView {
                VStack(spacing: 12) {
                    // ─── TITLE ───
                    titleCard

                    // ─── SUBTASKS ───
                    if !isSubtask {
                        subtasksCard
                    }

                    // ─── ACTIONS ───
                    actionsCard
                }
                .padding(.bottom, 20)
            }
            .background(.clear)
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
            .alert("Delete task?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    _Concurrency.Task { @MainActor in
                        await focusViewModel.permanentlyDeleteTask(task)
                        dismiss()
                    }
                }
            } message: {
                Text("This will permanently delete this task and all its commitments.")
            }
            .sheet(isPresented: $showingBreakdownDrawer) {
                if let userId = authService.currentUser?.id {
                    BreakdownDrawer(parentTask: task, userId: userId) {
                        _Concurrency.Task { @MainActor in
                            await viewModel.refreshSubtasks(for: task.id)
                        }
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    // MARK: - Title Card

    @ViewBuilder
    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Task title", text: $taskTitle, axis: .vertical)
                .font(.title3)
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .onSubmit { saveTitle() }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)

            if isSubtask, let parent = parentTask {
                Text(parent.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, -8)
                    .padding(.bottom, 12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTitleFocused = true
            }
        }
    }

    // MARK: - Subtasks Card

    @ViewBuilder
    private var subtasksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: "Subtasks" label + "Break Down" button
            HStack {
                Text("Subtasks")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                Spacer()
                if !task.isCompleted {
                    Button {
                        showingBreakdownDrawer = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.subheadline.weight(.semibold))
                            Text("Suggest Breakdown")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            Capsule()
                                .stroke(
                                    AngularGradient(
                                        colors: [
                                            Color(red: 0.85, green: 0.25, blue: 0.2),
                                            Color(red: 0.7, green: 0.3, blue: 0.5),
                                            Color(red: 0.35, green: 0.45, blue: 0.85),
                                            Color(red: 0.3, green: 0.55, blue: 0.7),
                                            Color(red: 0.55, green: 0.65, blue: 0.3),
                                            Color(red: 0.9, green: 0.75, blue: 0.15),
                                            Color(red: 0.9, green: 0.45, blue: 0.15),
                                            Color(red: 0.85, green: 0.25, blue: 0.2),
                                        ],
                                        center: .center
                                    ),
                                    lineWidth: 2.5
                                )
                                .blur(radius: 6)
                        }
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.5), lineWidth: 1.5)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            VStack(spacing: 14) {
                ForEach(subtasks) { subtask in
                    compactSubtaskRow(subtask)
                }

                // New subtask entry (shown when focused)
                if showNewSubtaskField || !newSubtaskTitle.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))

                        TextField("Subtask", text: $newSubtaskTitle)
                            .font(.body)
                            .textFieldStyle(.plain)
                            .focused($isNewSubtaskFocused)
                            .onAppear { isNewSubtaskFocused = true }
                            .onSubmit { addSubtask() }

                        Button {
                            newSubtaskTitle = ""
                            showNewSubtaskField = false
                            isNewSubtaskFocused = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // "+ Sub-task" pill button
                if !task.isCompleted {
                    HStack {
                        Button {
                            if !newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                                addSubtask()
                            }
                            showNewSubtaskField = true
                            isNewSubtaskFocused = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.caption)
                                Text("Sub-task")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.tint(.black).interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Compact Subtask Row

    @ViewBuilder
    private func compactSubtaskRow(_ subtask: FocusTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundColor(subtask.isCompleted ? .green : .secondary.opacity(0.5))

            // Editable title
            SubtaskTextField(subtask: subtask, viewModel: viewModel, focusedId: $focusedSubtaskId)

            // Delete X button (staged — committed on save)
            if !subtask.isCompleted {
                Button {
                    pendingDeletions.insert(subtask.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions Card

    @ViewBuilder
    private var actionsCard: some View {
        VStack(spacing: 0) {
            // Category (only in Log view, parent tasks)
            if !isSubtask && commitment == nil {
                DrawerCategoryMenu(
                    currentCategoryId: task.categoryId,
                    categories: categories,
                    onSelect: { categoryId in moveTask(to: categoryId) },
                    onCreateNew: { showingNewCategoryAlert = true }
                )
            }

            // Commit (only when not committed)
            if commitment == nil {
                DrawerActionRow(icon: "arrow.right.circle", text: "Commit") {
                    showingCommitmentSheet = true
                }
            }

            // Remove from Focus (when committed)
            if let commitment = commitment {
                DrawerActionRow(
                    icon: "minus.circle",
                    text: {
                        switch commitment.timeframe {
                        case .daily: return "Remove from Today"
                        case .weekly: return "Remove from This Week"
                        case .monthly: return "Remove from This Month"
                        case .yearly: return "Remove from This Year"
                        }
                    }()
                ) {
                    _Concurrency.Task {
                        await focusViewModel.removeCommitment(commitment)
                        dismiss()
                    }
                }
            }

            // Commit to lower timeframe (non-daily commitments)
            if let commitment = commitment,
               commitment.canBreakdown,
               let childTimeframe = commitment.childTimeframe {
                DrawerActionRow(icon: "arrow.down.forward.circle", text: "Commit to \(childTimeframe.displayName)") {
                    focusViewModel.selectedCommitmentForCommit = commitment
                    focusViewModel.showCommitSheet = true
                    dismiss()
                }
            }

            // Commit Subtask to lower timeframe
            if isSubtask && commitment == nil {
                if let parentId = task.parentTaskId,
                   let parentCommitment = focusViewModel.commitments.first(where: {
                       $0.taskId == parentId &&
                       focusViewModel.isSameTimeframe($0.commitmentDate, timeframe: focusViewModel.selectedTimeframe, selectedDate: focusViewModel.selectedDate)
                   }),
                   parentCommitment.timeframe != .daily {
                    DrawerActionRow(icon: "arrow.down.forward.circle", text: "Commit to \(parentCommitment.childTimeframe?.displayName ?? "...")") {
                        focusViewModel.selectedSubtaskForCommit = task
                        focusViewModel.selectedParentCommitmentForSubtaskCommit = parentCommitment
                        focusViewModel.showSubtaskCommitSheet = true
                        dismiss()
                    }
                }
            }

            // Reschedule (committed, non-completed parent task)
            if commitment != nil, !isSubtask, !task.isCompleted {
                DrawerActionRow(icon: "calendar", text: "Reschedule") {
                    showingRescheduleSheet = true
                }
            }

            // Unschedule (remove from timeline, keep commitment)
            if let commitment = commitment, commitment.scheduledTime != nil {
                DrawerActionRow(icon: "calendar.badge.minus", text: "Unschedule") {
                    _Concurrency.Task { @MainActor in
                        await focusViewModel.timelineVM.unscheduleCommitment(commitment.id)
                        dismiss()
                    }
                }
            }

            // Push to Next (committed, non-completed parent task)
            if let commitment = commitment, !isSubtask, !task.isCompleted {
                DrawerActionRow(icon: "arrow.turn.right.down", text: "Push to \(nextTimeframeLabel(for: commitment.timeframe))") {
                    _Concurrency.Task {
                        let success = await focusViewModel.pushCommitmentToNext(commitment)
                        if success { dismiss() }
                    }
                }
            }

            Divider()
                .padding(.horizontal, 14)

            // Delete
            if isSubtask {
                DrawerActionRow(icon: "trash", text: "Delete Subtask", iconColor: .red) {
                    _Concurrency.Task {
                        if let parentId = task.parentTaskId {
                            await viewModel.deleteSubtask(task, parentId: parentId)
                        }
                        dismiss()
                    }
                }
            } else if commitment != nil {
                DrawerActionRow(icon: "trash", text: "Delete Task", iconColor: .red) {
                    showingDeleteConfirmation = true
                }
            } else {
                DrawerActionRow(icon: "trash", text: "Delete Task", iconColor: .red) {
                    _Concurrency.Task {
                        await viewModel.deleteTask(task)
                        dismiss()
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func saveTitle() {
        guard taskTitle != task.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(task, newTitle: taskTitle)
        }
    }

    private func commitPendingDeletions() {
        let allSubtasks = viewModel.getSubtasks(for: task.id)
        for subtaskId in pendingDeletions {
            if let subtask = allSubtasks.first(where: { $0.id == subtaskId }) {
                _Concurrency.Task {
                    await viewModel.deleteSubtask(subtask, parentId: task.id)
                }
            }
        }
    }

    private func addSubtask() {
        guard !newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let title = newSubtaskTitle
        newSubtaskTitle = ""
        isNewSubtaskFocused = true
        _Concurrency.Task {
            if let commitment = commitment {
                await focusViewModel.createSubtask(title: title, parentId: task.id, parentCommitment: commitment)
            } else {
                await viewModel.createSubtask(title: title, parentId: task.id)
            }
        }
    }

    private func moveTask(to categoryId: UUID?) {
        _Concurrency.Task {
            await viewModel.moveTaskToCategory(task, categoryId: categoryId)
            dismiss()
        }
    }

    private func createAndMoveToCategory() {
        let name = newCategoryName
        newCategoryName = ""
        _Concurrency.Task {
            await viewModel.createCategoryAndMove(name: name, task: task)
            dismiss()
        }
    }
}

// MARK: - Inline Subtask TextField

private struct SubtaskTextField<VM: TaskEditingViewModel>: View {
    let subtask: FocusTask
    @ObservedObject var viewModel: VM
    var focusedId: FocusState<UUID?>.Binding
    @State private var editingTitle: String

    init(subtask: FocusTask, viewModel: VM, focusedId: FocusState<UUID?>.Binding) {
        self.subtask = subtask
        self.viewModel = viewModel
        self.focusedId = focusedId
        _editingTitle = State(initialValue: subtask.title)
    }

    var body: some View {
        TextField("Subtask", text: $editingTitle)
            .font(.body)
            .textFieldStyle(.plain)
            .strikethrough(subtask.isCompleted)
            .foregroundColor(subtask.isCompleted ? .secondary : .primary)
            .focused(focusedId, equals: subtask.id)
            .onSubmit { saveTitle() }
            .onChange(of: focusedId.wrappedValue) { _, newValue in
                if newValue != subtask.id {
                    saveTitle()
                }
            }
    }

    private func saveTitle() {
        guard editingTitle != subtask.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(subtask, newTitle: editingTitle)
        }
    }
}
