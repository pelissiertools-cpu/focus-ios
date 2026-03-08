//
//  GoalDetailsDrawer.swift
//  Focus IOS
//

import SwiftUI

struct GoalDetailsDrawer: View {
    let goal: FocusTask
    @ObservedObject var viewModel: GoalsViewModel
    @State private var goalTitle: String
    @State private var selectedCategoryId: UUID?
    @State private var selectedPriority: Priority
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var noteText: String
    @State private var showingDeleteConfirmation = false
    @State private var newTaskTitle: String = ""
    @State private var showNewTaskField = false
    @State private var isGeneratingBreakdown = false
    @State private var hasGeneratedBreakdown = false
    @State private var draftSuggestions: [DraftSubtaskEntry] = []
    @State private var pendingDeletions: Set<UUID> = []
    @State private var dueDate: Date?
    @State private var hasDueDate: Bool
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNewTaskFocused: Bool
    @FocusState private var focusedTaskId: UUID?
    @Environment(\.dismiss) private var dismiss

    init(goal: FocusTask, viewModel: GoalsViewModel) {
        self.goal = goal
        self.viewModel = viewModel
        _goalTitle = State(initialValue: goal.title)
        _noteText = State(initialValue: goal.description ?? "")
        _selectedCategoryId = State(initialValue: goal.categoryId)
        _selectedPriority = State(initialValue: goal.priority)
        _dueDate = State(initialValue: goal.dueDate)
        _hasDueDate = State(initialValue: goal.dueDate != nil)
    }

    private var goalTasks: [FocusTask] {
        (viewModel.goalTasksMap[goal.id] ?? [])
            .filter { !$0.isSection && !pendingDeletions.contains($0.id) }
    }

    private var hasNoteChanges: Bool {
        noteText != (goal.description ?? "")
    }

    private var hasChanges: Bool {
        goalTitle != goal.title || selectedCategoryId != goal.categoryId || selectedPriority != goal.priority || !pendingDeletions.isEmpty || !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty || !draftSuggestions.isEmpty || hasNoteChanges || dueDateChanged
    }

    private var dueDateChanged: Bool {
        if hasDueDate {
            return dueDate != goal.dueDate
        } else {
            return goal.dueDate != nil
        }
    }

    private var currentCategoryName: String {
        if let id = selectedCategoryId,
           let cat = viewModel.categories.first(where: { $0.id == id }) {
            return cat.name
        }
        return "Category"
    }

    var body: some View {
        DrawerContainer(
            title: "Goal Details",
            leadingButton: .close { dismiss() },
            trailingButton: .check(action: {
                saveTitle()
                saveNote()
                saveCategory()
                savePriority()
                saveDueDate()
                addTask()
                saveDraftSuggestions()
                savePendingDeletions()
                dismiss()
            }, highlighted: hasChanges)
        ) {
            ScrollView {
                VStack(spacing: 12) {
                    titleCard
                    deadlineCard
                    tasksCard
                    actionPillsRow
                    noteCard
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
            .alert("Delete goal?", isPresented: $showingDeleteConfirmation) {
                Button("Delete goal only") {
                    _Concurrency.Task {
                        await viewModel.deleteGoalKeepTasks(goal)
                        dismiss()
                    }
                }
                Button("Delete goal and tasks", role: .destructive) {
                    _Concurrency.Task {
                        await viewModel.deleteGoal(goal)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("What would you like to do with the tasks inside this goal?")
            }
        }
    }

    // MARK: - Title Card

    @ViewBuilder
    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Goal title", text: $goalTitle, axis: .vertical)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .onSubmit { saveTitle() }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
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

    // MARK: - Deadline Card

    @ViewBuilder
    private var deadlineCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "calendar")
                    .font(.inter(.subheadline))
                    .foregroundColor(.secondary)
                Text("Deadline")
                    .font(.inter(.subheadline, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Toggle("", isOn: $hasDueDate)
                    .labelsHidden()
                    .tint(.appRed)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if hasDueDate {
                DatePicker(
                    "Due date",
                    selection: Binding(
                        get: { dueDate ?? Date() },
                        set: { dueDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(.appRed)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .onChange(of: hasDueDate) { _, newValue in
            if newValue && dueDate == nil {
                dueDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date()) ?? Date()
            }
        }
    }

    // MARK: - Tasks Card

    @ViewBuilder
    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tasks")
                    .font(.inter(.subheadline, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                if !goal.isCompleted {
                    Button {
                        generateBreakdown()
                    } label: {
                        HStack(spacing: 6) {
                            if isGeneratingBreakdown {
                                ProgressView()
                                    .tint(.primary)
                            } else {
                                Image(systemName: hasGeneratedBreakdown ? "arrow.clockwise" : "sparkles")
                                    .font(.inter(.subheadline, weight: .semiBold))
                            }
                            Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Steps"))
                                .font(.inter(.caption, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingBreakdown)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            VStack(spacing: 14) {
                ForEach(goalTasks) { task in
                    compactTaskRow(task)
                }

                ForEach(draftSuggestions) { draft in
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.inter(.caption2))
                            .foregroundColor(.purple.opacity(0.6))

                        TextField("Task", text: draftBinding(for: draft.id))
                            .font(.inter(.body))
                            .textFieldStyle(.plain)

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                draftSuggestions.removeAll { $0.id == draft.id }
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.inter(.caption))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if showNewTaskField || !newTaskTitle.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .font(.inter(.caption2))
                            .foregroundColor(.secondary.opacity(0.5))

                        TextField("Task", text: $newTaskTitle)
                            .font(.inter(.body))
                            .textFieldStyle(.plain)
                            .focused($isNewTaskFocused)
                            .onAppear { isNewTaskFocused = true }
                            .onSubmit { addTask() }

                        Button {
                            newTaskTitle = ""
                            showNewTaskField = false
                            isNewTaskFocused = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.inter(.caption))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !goal.isCompleted {
                    HStack {
                        Button {
                            if !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                                addTask()
                            }
                            showNewTaskField = true
                            isNewTaskFocused = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.inter(.caption))
                                Text("Task")
                                    .font(.inter(.caption))
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

    // MARK: - Compact Task Row

    @ViewBuilder
    private func compactTaskRow(_ task: FocusTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.inter(.caption2))
                .foregroundColor(task.isCompleted ? Color.focusBlue.opacity(0.6) : .secondary.opacity(0.5))

            GoalTaskTextField(task: task, viewModel: viewModel, focusedId: $focusedTaskId)

            if !task.isCompleted {
                Button {
                    pendingDeletions.insert(task.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.inter(.caption))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Action Pills Row

    @ViewBuilder
    private var actionPillsRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Button {
                        selectedPriority = priority
                    } label: {
                        if selectedPriority == priority {
                            Label(priority.displayName, systemImage: "checkmark")
                        } else {
                            Text(priority.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(selectedPriority.dotColor)
                        .frame(width: 8, height: 8)
                    Text(LocalizedStringKey(selectedPriority.displayName))
                        .font(.inter(.subheadline, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            Menu {
                Button {
                    selectedCategoryId = nil
                } label: {
                    if selectedCategoryId == nil {
                        Label("None", systemImage: "checkmark")
                    } else {
                        Text("None")
                    }
                }
                ForEach(viewModel.categories) { category in
                    Button {
                        selectedCategoryId = category.id
                    } label: {
                        if selectedCategoryId == category.id {
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
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.inter(.subheadline))
                    Text(LocalizedStringKey(currentCategoryName))
                        .font(.inter(.subheadline, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            Spacer()

            Button {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(.red)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Note Card

    @ViewBuilder
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Note")
                .font(.inter(.subheadline, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text("Add a note...")
                        .font(.inter(.body))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $noteText)
                    .font(.inter(.body))
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func saveTitle() {
        let trimmed = goalTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != goal.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(goal, newTitle: trimmed)
        }
    }

    private func saveNote() {
        guard hasNoteChanges else { return }
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        _Concurrency.Task {
            await viewModel.updateTaskNote(goal, newNote: note.isEmpty ? nil : note)
        }
    }

    private func savePriority() {
        guard selectedPriority != goal.priority else { return }
        _Concurrency.Task {
            await viewModel.updateTaskPriority(goal, priority: selectedPriority)
        }
    }

    private func saveCategory() {
        guard selectedCategoryId != goal.categoryId else { return }
        _Concurrency.Task {
            await viewModel.moveTaskToCategory(goal, categoryId: selectedCategoryId)
        }
    }

    private func saveDueDate() {
        let newDueDate: Date? = hasDueDate ? dueDate : nil
        guard newDueDate != goal.dueDate else { return }
        _Concurrency.Task {
            await viewModel.updateGoalDueDate(goal, dueDate: newDueDate)
        }
    }

    private func addTask() {
        guard !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let title = newTaskTitle
        newTaskTitle = ""
        isNewTaskFocused = true
        _Concurrency.Task {
            await viewModel.createGoalTask(title: title, goalId: goal.id)
        }
    }

    private func generateBreakdown() {
        isGeneratingBreakdown = true
        let existingTitles = goalTasks.map { $0.title } + draftSuggestions.map { $0.title }

        _Concurrency.Task { @MainActor in
            do {
                let suggestions = try await AIService().generateSubtasks(
                    title: goal.title,
                    description: goal.description,
                    existingSubtasks: existingTitles.isEmpty ? nil : existingTitles
                )
                withAnimation(.easeInOut(duration: 0.2)) {
                    let manualDrafts = draftSuggestions.filter { !$0.isAISuggested }
                    draftSuggestions = manualDrafts + suggestions.map {
                        DraftSubtaskEntry(title: $0, isAISuggested: true)
                    }
                }
                hasGeneratedBreakdown = true
            } catch {
                // Silently fail — user can retry or add manually
            }
            isGeneratingBreakdown = false
        }
    }

    private func saveDraftSuggestions() {
        for draft in draftSuggestions {
            let title = draft.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            _Concurrency.Task {
                await viewModel.createGoalTask(title: title, goalId: goal.id)
            }
        }
    }

    private func savePendingDeletions() {
        let allTasks = viewModel.goalTasksMap[goal.id] ?? []
        for taskId in pendingDeletions {
            if let task = allTasks.first(where: { $0.id == taskId }) {
                _Concurrency.Task {
                    await viewModel.deleteGoalTask(task, goalId: goal.id)
                }
            }
        }
    }

    private func draftBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { draftSuggestions.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let idx = draftSuggestions.firstIndex(where: { $0.id == id }) {
                    draftSuggestions[idx].title = newValue
                }
            }
        )
    }

    private func createAndMoveToCategory() {
        let name = newCategoryName
        newCategoryName = ""
        _Concurrency.Task {
            await viewModel.createCategoryAndMove(name: name, task: goal)
            dismiss()
        }
    }
}

// MARK: - Goal Task TextField

private struct GoalTaskTextField: View {
    let task: FocusTask
    @ObservedObject var viewModel: GoalsViewModel
    var focusedId: FocusState<UUID?>.Binding
    @State private var editingTitle: String

    init(task: FocusTask, viewModel: GoalsViewModel, focusedId: FocusState<UUID?>.Binding) {
        self.task = task
        self.viewModel = viewModel
        self.focusedId = focusedId
        _editingTitle = State(initialValue: task.title)
    }

    var body: some View {
        TextField("Task", text: $editingTitle)
            .font(.inter(.body))
            .textFieldStyle(.plain)
            .strikethrough(task.isCompleted)
            .foregroundColor(task.isCompleted ? .secondary : .primary)
            .focused(focusedId, equals: task.id)
            .onSubmit { saveTitle() }
            .onChange(of: focusedId.wrappedValue) { _, newValue in
                if newValue != task.id {
                    saveTitle()
                }
            }
    }

    private func saveTitle() {
        guard editingTitle != task.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(task, newTitle: editingTitle)
        }
    }
}
