//
//  GoalContentView.swift
//  Focus IOS
//

import SwiftUI

struct GoalContentView: View {
    let goal: FocusTask
    @ObservedObject var viewModel: GoalsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isInlineAddFocused = false
    @State private var goalTitle: String
    @State private var goalNotes: String
    @State private var editingSectionId: UUID?
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNotesFocused: Bool

    init(goal: FocusTask, viewModel: GoalsViewModel) {
        self.goal = goal
        self.viewModel = viewModel
        _goalTitle = State(initialValue: goal.title)
        _goalNotes = State(initialValue: goal.description ?? "")
    }

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                List {
                    // Goal title — editable inline
                    TextField("Goal name", text: $goalTitle, axis: .vertical)
                        .font(.inter(.title2, weight: .bold))
                        .foregroundColor(.primary)
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .onSubmit { saveGoalTitle() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: AppStyle.Spacing.section, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.tiny, trailing: AppStyle.Spacing.page))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)

                    // Deadline
                    if let dueDate = goal.dueDate {
                        HStack(spacing: AppStyle.Spacing.small) {
                            Image(systemName: "calendar")
                                .font(.inter(.caption))
                            Text(dueDate, style: .date)
                                .font(.inter(.subheadline))
                        }
                        .foregroundColor(dueDate < Date() ? .red : .secondary)
                        .listRowInsets(EdgeInsets(top: 0, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.compact, trailing: AppStyle.Spacing.page))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                    }

                    // Notes
                    Group {
                        if isNotesFocused || goalNotes.isEmpty {
                            TextField("Notes", text: $goalNotes, axis: .vertical)
                                .font(.inter(.body))
                                .foregroundColor(.secondary)
                                .textFieldStyle(.plain)
                                .focused($isNotesFocused)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(linkifiedText(goalNotes))
                                .font(.inter(.body))
                                .foregroundColor(.secondary)
                                .tint(.blue.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    isNotesFocused = true
                                }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.comfortable, trailing: AppStyle.Spacing.page))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                    // Content
                    if viewModel.isLoadingGoalTasks.contains(goal.id) {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                            Spacer()
                        }
                        .padding()
                        .listRowInsets(AppStyle.Insets.row)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                    } else {
                        let items = viewModel.flattenedGoalItems(for: goal.id)

                        if items.count <= 1 {
                            Text("No tasks yet")
                                .font(AppStyle.Typography.emptyTitle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .listRowInsets(EdgeInsets(top: 0, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.compact, trailing: AppStyle.Spacing.page))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .moveDisabled(true)

                            InlineAddRow(
                                placeholder: "Task title",
                                buttonLabel: "Add task",
                                onSubmit: { title in await viewModel.createGoalTask(title: title, goalId: goal.id) },
                                isAnyAddFieldActive: $isInlineAddFocused,
                                verticalPadding: AppStyle.Spacing.compact
                            )
                            .listRowInsets(AppStyle.Insets.row)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .moveDisabled(true)
                        } else {
                            ForEach(items) { item in
                                switch item {
                                case .section(let section):
                                    GoalSectionRow(
                                        section: section,
                                        viewModel: viewModel,
                                        goalId: goal.id,
                                        editingSectionId: $editingSectionId
                                    )
                                    .listRowInsets(AppStyle.Insets.row)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)

                                case .task(let task):
                                    Group {
                                        if task.parentTaskId != nil {
                                            GoalSubtaskRow(
                                                subtask: task,
                                                parentId: task.parentTaskId!,
                                                viewModel: viewModel
                                            )
                                            .padding(.leading, viewModel.contentEditMode ? 0 : 32)
                                        } else {
                                            GoalContentTaskRow(
                                                task: task,
                                                goalId: goal.id,
                                                viewModel: viewModel
                                            )
                                        }
                                    }
                                    .moveDisabled(task.isCompleted || viewModel.contentEditMode)
                                    .listRowInsets(AppStyle.Insets.row)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)

                                case .addSubtaskRow(let parentId):
                                    if !viewModel.contentEditMode {
                                        InlineAddRow(
                                            placeholder: "Subtask title",
                                            buttonLabel: "Add subtask",
                                            onSubmit: { title in await viewModel.createSubtask(title: title, parentId: parentId) },
                                            isAnyAddFieldActive: $isInlineAddFocused,
                                            iconFont: .inter(.caption),
                                            verticalPadding: AppStyle.Spacing.small
                                        )
                                        .padding(.leading, 32)
                                        .moveDisabled(true)
                                        .listRowInsets(AppStyle.Insets.row)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                    }

                                case .completedHeader(let count):
                                    GoalContentDonePill(
                                        count: count,
                                        isCollapsed: viewModel.isContentDoneCollapsed,
                                        onToggle: { viewModel.toggleContentDoneCollapsed() }
                                    )
                                    .moveDisabled(true)
                                    .listRowInsets(AppStyle.Insets.row)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)

                                case .addTaskRow:
                                    if !viewModel.contentEditMode {
                                        InlineAddRow(
                                            placeholder: "Task title",
                                            buttonLabel: "Add task",
                                            onSubmit: { title in await viewModel.createGoalTask(title: title, goalId: goal.id) },
                                            isAnyAddFieldActive: $isInlineAddFocused,
                                            verticalPadding: AppStyle.Spacing.compact
                                        )
                                        .moveDisabled(true)
                                        .listRowInsets(AppStyle.Insets.row)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                    }
                                }
                            }
                            .onMove { from, to in
                                if !viewModel.contentEditMode {
                                    viewModel.handleGoalContentFlatMove(from: from, to: to, goalId: goal.id)
                                }
                            }
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("inline-add-anchor")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)

                    Color.clear
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: isInlineAddFocused) { _, focused in
                    if focused {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo("inline-add-anchor", anchor: .bottom)
                            }
                        }
                    }
                }
            }

            // Edit mode action bar
            if viewModel.contentEditMode {
                GoalContentEditModeActionBar(viewModel: viewModel, goalId: goal.id)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if viewModel.contentEditMode {
                    Button {
                        viewModel.exitContentEditMode()
                    } label: {
                        Text("Done")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.appRed)
                    }
                } else {
                    Button {
                        saveGoalTitle()
                        saveGoalNotes()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: AppStyle.Layout.touchTarget, height: AppStyle.Layout.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Back")
                }
            }
            ToolbarItem(placement: .principal) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.contentEditMode {
                    Button {
                        if viewModel.allContentTasksSelected {
                            viewModel.deselectAllContentTasks()
                        } else {
                            viewModel.selectAllContentTasks(goalId: goal.id)
                        }
                    } label: {
                        Text(viewModel.allContentTasksSelected ? "Deselect All" : "Select All")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.appRed)
                    }
                } else {
                    Menu {
                        Button {
                            viewModel.enterContentEditMode()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }

                        Button {
                            _Concurrency.Task {
                                await viewModel.createSection(
                                    title: "",
                                    goalId: goal.id
                                )
                                if let tasks = viewModel.goalTasksMap[goal.id],
                                   let newSection = tasks.last(where: { $0.isSection }) {
                                    editingSectionId = newSection.id
                                }
                            }
                        } label: {
                            Label("Add section", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: AppStyle.Layout.compactButton, height: AppStyle.Layout.compactButton)
                            .background(Color.pillBackground, in: Circle())
                    }
                }
            }
        }
        .task {
            if viewModel.goalTasksMap[goal.id] == nil {
                await viewModel.fetchGoalTasks(for: goal.id)
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused { saveGoalTitle() }
        }
        .onChange(of: isNotesFocused) { _, focused in
            if !focused { saveGoalNotes() }
        }
        .onDisappear {
            saveGoalNotes()
            if viewModel.contentEditMode {
                viewModel.exitContentEditMode()
            }
        }
        .alert("Delete \(viewModel.selectedContentTaskIds.count) task\(viewModel.selectedContentTaskIds.count == 1 ? "" : "s")?",
               isPresented: $viewModel.showContentBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.batchDeleteContentTasks(goalId: goal.id)
                }
            }
        }
        .sheet(isPresented: $viewModel.showContentBatchScheduleSheet) {
            BatchScheduleSheet(
                viewModel: viewModel,
                tasks: viewModel.selectedContentTasks,
                onComplete: { viewModel.exitContentEditMode() }
            )
            .drawerStyle()
        }
        .sheet(item: $viewModel.selectedTaskForDetails) { task in
            TaskDetailsDrawer(task: task, viewModel: viewModel, categories: viewModel.categories)
                .drawerStyle()
        }
        .sheet(item: $viewModel.selectedTaskForSchedule) { task in
            ScheduleSelectionSheet(
                task: task,
                focusViewModel: focusViewModel
            )
                .drawerStyle()
        }
    }

    private func linkifiedText(_ string: String) -> AttributedString {
        var result = AttributedString(string)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return result
        }
        let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
        for match in detector.matches(in: string, range: nsRange) {
            guard let url = match.url,
                  let range = Range(match.range, in: string) else { continue }
            if let lower = AttributedString.Index(range.lowerBound, within: result),
               let upper = AttributedString.Index(range.upperBound, within: result) {
                result[lower..<upper].link = url
            }
        }
        return result
    }

    private func saveGoalTitle() {
        let trimmed = goalTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != goal.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(goal, newTitle: trimmed)
        }
    }

    private func saveGoalNotes() {
        let newNote = goalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = goal.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard newNote != current else { return }
        _Concurrency.Task {
            await viewModel.updateTaskNote(goal, newNote: newNote.isEmpty ? nil : newNote)
        }
    }

}

// MARK: - Goal Content Task Row

private struct GoalContentTaskRow: View {
    let task: FocusTask
    let goalId: UUID
    @ObservedObject var viewModel: GoalsViewModel
    @State private var showDeleteConfirmation = false

    private var isPending: Bool { viewModel.isPendingCompletion(task.id) }
    private var displayCompleted: Bool { task.isCompleted || isPending }

    private var subtaskCount: Int {
        (viewModel.subtasksMap[task.id] ?? []).count
    }

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            if viewModel.contentEditMode {
                Image(systemName: viewModel.selectedContentTaskIds.contains(task.id) ? "checkmark.circle.fill" : "circle")
                    .font(.inter(.title3))
                    .foregroundColor(viewModel.selectedContentTaskIds.contains(task.id) ? .appRed : .secondary)
                    .accessibilityLabel(viewModel.selectedContentTaskIds.contains(task.id) ? "Selected" : "Select")
            }

            VStack(alignment: .leading, spacing: AppStyle.Spacing.tiny) {
                Text(task.title)
                    .font(AppStyle.Typography.itemTitle)
                    .strikethrough(displayCompleted)
                    .foregroundColor(displayCompleted ? .secondary : .primary)

                if subtaskCount > 0 {
                    Text("\(subtaskCount) subtask\(subtaskCount == 1 ? "" : "s")")
                        .font(.inter(.caption))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.iconButton, alignment: .leading)

            if !viewModel.contentEditMode {
                Button {
                    UIImpactFeedbackGenerator(style: isPending ? .light : .medium).impactOccurred()
                    viewModel.requestToggleTaskCompletion(task, goalId: goalId)
                } label: {
                    Image(systemName: displayCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.inter(.title3))
                        .foregroundColor(displayCompleted ? Color.focusBlue.opacity(0.6) : .gray)
                        .symbolEffect(.pulse, isActive: isPending)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(displayCompleted ? "Completed" : "Mark complete")
            }
        }
        .padding(.vertical, AppStyle.Spacing.compact)
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.contentEditMode {
                if !task.isCompleted {
                    viewModel.toggleContentTaskSelection(task.id)
                }
            } else {
                _Concurrency.Task {
                    await viewModel.toggleTaskExpanded(task.id)
                }
            }
        }
        .contextMenu {
            if !viewModel.contentEditMode && !task.isCompleted {
                ContextMenuItems.editButton {
                    viewModel.selectedTaskForDetails = task
                }
                ContextMenuItems.scheduleButton {
                    viewModel.selectedTaskForSchedule = task
                }
                Divider()
                ContextMenuItems.deleteButton {
                    showDeleteConfirmation = true
                }
            }
        }
        .alert("Delete Task", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.deleteGoalTask(task, goalId: goalId)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(task.title)\"?")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !viewModel.contentEditMode && !task.isCompleted {
                Button(role: .destructive) {
                    _Concurrency.Task {
                        await viewModel.deleteGoalTask(task, goalId: goalId)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Goal Subtask Row

private struct GoalSubtaskRow: View {
    let subtask: FocusTask
    let parentId: UUID
    @ObservedObject var viewModel: GoalsViewModel

    private var isPending: Bool { viewModel.isPendingCompletion(subtask.id) }
    private var displayCompleted: Bool { subtask.isCompleted || isPending }

    var body: some View {
        HStack(spacing: AppStyle.Spacing.compact) {
            Text(subtask.title)
                .font(AppStyle.Typography.itemSubtitle)
                .strikethrough(displayCompleted)
                .foregroundColor(displayCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                UIImpactFeedbackGenerator(style: isPending ? .light : .medium).impactOccurred()
                viewModel.requestToggleSubtaskCompletion(subtask, parentId: parentId)
            } label: {
                Image(systemName: displayCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.inter(.body))
                    .foregroundColor(displayCompleted ? Color.focusBlue.opacity(0.6) : .gray)
                    .symbolEffect(.pulse, isActive: isPending)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayCompleted ? "Completed" : "Mark complete")
        }
        .padding(.vertical, AppStyle.Spacing.small)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                _Concurrency.Task {
                    await viewModel.deleteSubtask(subtask, parentId: parentId)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Goal Content Edit Mode Action Bar

struct GoalContentEditModeActionBar: View {
    @ObservedObject var viewModel: GoalsViewModel
    let goalId: UUID

    private var hasSelection: Bool { !viewModel.selectedContentTaskIds.isEmpty }

    private struct ActionItem: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let isDestructive: Bool
        let action: () -> Void
    }

    private var actions: [ActionItem] {
        [
            ActionItem(icon: "trash", label: "Delete", isDestructive: true) {
                viewModel.showContentBatchDeleteConfirmation = true
            },
            ActionItem(icon: "calendar", label: "Schedule", isDestructive: false) {
                viewModel.showContentBatchScheduleSheet = true
            },
        ]
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()

                HStack(alignment: .top, spacing: AppStyle.Spacing.content) {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(actions.reversed().enumerated()), id: \.element.id) { _, item in
                            Text(LocalizedStringKey(item.label))
                                .font(.inter(.subheadline, weight: .medium))
                                .foregroundColor(item.isDestructive ? .red : .primary)
                                .frame(height: AppStyle.Layout.largeButton)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if hasSelection { item.action() }
                                }
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(actions.reversed().enumerated()), id: \.element.id) { index, item in
                            Button {
                                item.action()
                            } label: {
                                Image(systemName: item.icon)
                                    .font(.inter(.title3))
                                    .foregroundColor(item.isDestructive ? .red : .primary)
                                    .frame(width: AppStyle.Layout.largeButton, height: AppStyle.Layout.largeButton)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasSelection)

                            if index < actions.count - 1 {
                                Divider()
                                    .frame(width: 28)
                            }
                        }
                    }
                    .padding(.vertical, AppStyle.Spacing.small)
                    .glassEffect(.regular, in: .capsule)
                    .shadow(radius: 4, y: 2)
                }
                .opacity(hasSelection ? 1.0 : 0.5)
                .padding(.trailing, AppStyle.Spacing.page)
                .padding(.top, 62)
            }
            Spacer()
        }
    }
}

// MARK: - Goal Section Row

struct GoalSectionRow: View {
    let section: FocusTask
    @ObservedObject var viewModel: GoalsViewModel
    let goalId: UUID
    @Binding var editingSectionId: UUID?
    @State private var sectionTitle: String
    @State private var showDeleteConfirmation = false
    @FocusState private var isEditing: Bool

    init(section: FocusTask, viewModel: GoalsViewModel, goalId: UUID, editingSectionId: Binding<UUID?>) {
        self.section = section
        self.viewModel = viewModel
        self.goalId = goalId
        self._editingSectionId = editingSectionId
        _sectionTitle = State(initialValue: section.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            TextField("Section name", text: $sectionTitle)
                .font(.inter(.headline, weight: .bold))
                .foregroundColor(.focusBlue)
                .textFieldStyle(.plain)
                .focused($isEditing)
                .onSubmit { saveSectionTitle() }
                .allowsHitTesting(isEditing)
                .padding(.top, AppStyle.Spacing.section)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isEditing = true
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Section?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.deleteSection(section, goalId: goalId)
                }
            }
        } message: {
            Text("This will remove the section header. Tasks will not be deleted.")
        }
        .onChange(of: editingSectionId) { _, newId in
            if newId == section.id {
                isEditing = true
                editingSectionId = nil
            }
        }
        .onChange(of: isEditing) { _, focused in
            if !focused { saveSectionTitle() }
        }
    }

    private func saveSectionTitle() {
        let trimmed = sectionTitle.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            _Concurrency.Task {
                await viewModel.deleteSection(section, goalId: goalId)
            }
            return
        }
        guard trimmed != section.title else { return }
        _Concurrency.Task {
            await viewModel.renameSection(section, newTitle: trimmed)
        }
    }
}

// MARK: - Goal Content Done Pill

private struct GoalContentDonePill: View {
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: AppStyle.Spacing.compact) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggle()
                }
            } label: {
                HStack(spacing: AppStyle.Spacing.tiny) {
                    Text("Completed")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("\(count)")
                        .font(.inter(size: 12))
                        .foregroundColor(.secondary)

                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(AppStyle.Typography.chevron)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, AppStyle.Spacing.medium)
                .padding(.vertical, AppStyle.Spacing.small)
                .clipShape(Capsule())
                .glassEffect(.regular.tint(.glassTint).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.vertical, AppStyle.Spacing.medium)
    }
}
