//
//  ProjectDetailsDrawer.swift
//  Focus IOS
//

import SwiftUI

struct ProjectDetailsDrawer: View {
    let project: FocusTask
    @ObservedObject var viewModel: ProjectsViewModel
    @State private var projectTitle: String
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
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNewTaskFocused: Bool
    @State private var isTasksExpanded = false
    @FocusState private var focusedTaskId: UUID?
    @Environment(\.dismiss) private var dismiss

    init(project: FocusTask, viewModel: ProjectsViewModel) {
        self.project = project
        self.viewModel = viewModel
        _projectTitle = State(initialValue: project.title)
        _noteText = State(initialValue: project.description ?? "")
        _selectedCategoryId = State(initialValue: project.categoryId)
        _selectedPriority = State(initialValue: project.priority)
    }

    private var projectTasks: [FocusTask] {
        (viewModel.projectTasksMap[project.id] ?? [])
            .filter { !$0.isSection && !pendingDeletions.contains($0.id) }
    }

    private var hasNoteChanges: Bool {
        noteText != (project.description ?? "")
    }

    private var hasChanges: Bool {
        projectTitle != project.title || selectedCategoryId != project.categoryId || selectedPriority != project.priority || !pendingDeletions.isEmpty || !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty || !draftSuggestions.isEmpty || hasNoteChanges
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
            title: "Project Details",
            leadingButton: .close { dismiss() },
            trailingButton: .check(action: {
                saveTitle()
                saveNote()
                saveCategory()
                savePriority()
                addTask()
                saveDraftSuggestions()
                savePendingDeletions()
                dismiss()
            }, highlighted: hasChanges)
        ) {
            ScrollView {
                VStack(spacing: AppStyle.Spacing.comfortable) {
                    // ─── TITLE ───
                    titleCard

                    // ─── TASKS ───
                    tasksCard

                    // ─── PILL ACTIONS ───
                    actionPillsRow

                    // ─── NOTE ───
                    noteCard
                }
                .padding(.bottom, AppStyle.Spacing.page)
            }
            .background(.clear)
            .alert("New Category", isPresented: $showingNewCategoryAlert) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Create") { createAndMoveToCategory() }
            } message: {
                Text("Enter a name for the new category.")
            }
            .alert("Delete project?", isPresented: $showingDeleteConfirmation) {
                Button("Delete project only") {
                    _Concurrency.Task {
                        await viewModel.deleteProjectKeepTasks(project)
                        dismiss()
                    }
                }
                Button("Delete project and tasks", role: .destructive) {
                    _Concurrency.Task {
                        await viewModel.deleteProject(project)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("What would you like to do with the tasks inside this project?")
            }
        }
    }

    // MARK: - Title Card

    @ViewBuilder
    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Project title", text: $projectTitle, axis: .vertical)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .onSubmit { saveTitle() }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.vertical, AppStyle.Spacing.section)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, AppStyle.Spacing.section)
        .padding(.top, AppStyle.Spacing.compact)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTitleFocused = true
            }
        }
    }

    // MARK: - Tasks Card

    @ViewBuilder
    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: "Tasks" label + count + collapse toggle + "Suggest Breakdown" button
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTasksExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.small) {
                        Text("Tasks")
                            .font(.inter(.subheadline, weight: .medium))
                            .foregroundColor(.primary)

                        if !projectTasks.isEmpty {
                            Text("\(projectTasks.count)")
                                .font(.inter(.caption, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Image(systemName: "chevron.down")
                            .font(.inter(.caption2, weight: .semiBold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isTasksExpanded ? 0 : -90))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if !project.isCompleted && projectTasks.isEmpty && draftSuggestions.isEmpty {
                    Button {
                        generateBreakdown()
                    } label: {
                        HStack(spacing: AppStyle.Spacing.small) {
                            if isGeneratingBreakdown {
                                ProgressView()
                                    .tint(.primary)
                            } else {
                                Image(systemName: hasGeneratedBreakdown ? "arrow.clockwise" : "sparkles")
                                    .font(.inter(.subheadline, weight: .semiBold))
                            }
                            Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Breakdown"))
                                .font(.inter(.caption, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, AppStyle.Spacing.content)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingBreakdown)
                }
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.top, AppStyle.Spacing.comfortable)
            .padding(.bottom, AppStyle.Spacing.medium)

            if isTasksExpanded {
                VStack(spacing: AppStyle.Spacing.content) {
                    ForEach(projectTasks) { task in
                        compactTaskRow(task)
                    }

                    // Draft AI suggestions (not yet saved)
                    ForEach(draftSuggestions) { draft in
                        HStack(spacing: AppStyle.Spacing.compact) {
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

                    // New task entry (shown when focused)
                    if showNewTaskField || !newTaskTitle.isEmpty {
                        HStack(spacing: AppStyle.Spacing.compact) {
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

                    // "+ Task" pill button
                    if !project.isCompleted {
                        HStack {
                            Button {
                                if !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                                    addTask()
                                }
                                showNewTaskField = true
                                isNewTaskFocused = true
                            } label: {
                                HStack(spacing: AppStyle.Spacing.tiny) {
                                    Image(systemName: "plus")
                                        .font(.inter(size: 14, weight: .semiBold))
                                    Text("Task")
                                        .font(.inter(size: 14, weight: .semiBold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, AppStyle.Spacing.comfortable)
                                .padding(.vertical, AppStyle.Spacing.medium)
                                .glassEffect(.regular.tint(.black).interactive(), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.vertical, AppStyle.Spacing.medium)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - Compact Task Row

    @ViewBuilder
    private func compactTaskRow(_ task: FocusTask) -> some View {
        HStack(spacing: AppStyle.Spacing.compact) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.inter(.caption2))
                .foregroundColor(task.isCompleted ? Color.focusBlue.opacity(0.6) : .secondary.opacity(0.5))

            ProjectTaskTextField(task: task, viewModel: viewModel, focusedId: $focusedTaskId)

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
        HStack(spacing: AppStyle.Spacing.compact) {
            // Priority pill
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
                HStack(spacing: AppStyle.Spacing.small) {
                    Circle()
                        .fill(selectedPriority.dotColor)
                        .frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)
                    Text(LocalizedStringKey(selectedPriority.displayName))
                        .font(.inter(.subheadline, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, AppStyle.Spacing.comfortable)
                .padding(.vertical, AppStyle.Spacing.medium)
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            // Category pill
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
                HStack(spacing: AppStyle.Spacing.small) {
                    Image(systemName: "folder")
                        .font(.inter(.subheadline))
                    Text(LocalizedStringKey(currentCategoryName))
                        .font(.inter(.subheadline, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, AppStyle.Spacing.comfortable)
                .padding(.vertical, AppStyle.Spacing.medium)
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            Spacer()

            // Delete circle
            Button {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(.red)
                    .frame(width: AppStyle.Layout.touchTarget, height: AppStyle.Layout.touchTarget)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - Note Card

    @ViewBuilder
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Note")
                .font(.inter(.subheadline, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.comfortable)
                .padding(.bottom, AppStyle.Spacing.small)

            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text("Add a note...")
                        .font(.inter(.body))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                }
                TextEditor(text: $noteText)
                    .font(.inter(.body))
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, AppStyle.Spacing.small)
                    .padding(.vertical, AppStyle.Spacing.micro)
            }
            .padding(.horizontal, AppStyle.Spacing.compact)
            .padding(.bottom, AppStyle.Spacing.medium)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - Actions

    private func saveTitle() {
        let trimmed = projectTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != project.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(project, newTitle: trimmed)
        }
    }

    private func saveNote() {
        guard hasNoteChanges else { return }
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        _Concurrency.Task {
            await viewModel.updateTaskNote(project, newNote: note.isEmpty ? nil : note)
        }
    }

    private func savePriority() {
        guard selectedPriority != project.priority else { return }
        _Concurrency.Task {
            await viewModel.updateTaskPriority(project, priority: selectedPriority)
        }
    }

    private func saveCategory() {
        guard selectedCategoryId != project.categoryId else { return }
        _Concurrency.Task {
            await viewModel.moveTaskToCategory(project, categoryId: selectedCategoryId)
        }
    }

    private func addTask() {
        guard !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let title = newTaskTitle
        newTaskTitle = ""
        isNewTaskFocused = true
        _Concurrency.Task {
            await viewModel.createProjectTask(title: title, projectId: project.id)
        }
    }

    private func generateBreakdown() {
        isGeneratingBreakdown = true
        let existingTitles = projectTasks.map { $0.title } + draftSuggestions.map { $0.title }

        _Concurrency.Task { @MainActor in
            do {
                let suggestions = try await AIService().generateSubtasks(
                    title: project.title,
                    description: project.description,
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
                await viewModel.createProjectTask(title: title, projectId: project.id)
            }
        }
    }

    private func savePendingDeletions() {
        let allTasks = viewModel.projectTasksMap[project.id] ?? []
        for taskId in pendingDeletions {
            if let task = allTasks.first(where: { $0.id == taskId }) {
                _Concurrency.Task {
                    await viewModel.deleteProjectTask(task, projectId: project.id)
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
            await viewModel.createCategoryAndMove(name: name, task: project)
            dismiss()
        }
    }
}

// MARK: - Project Task TextField

private struct ProjectTaskTextField: View {
    let task: FocusTask
    @ObservedObject var viewModel: ProjectsViewModel
    var focusedId: FocusState<UUID?>.Binding
    @State private var editingTitle: String

    init(task: FocusTask, viewModel: ProjectsViewModel, focusedId: FocusState<UUID?>.Binding) {
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
