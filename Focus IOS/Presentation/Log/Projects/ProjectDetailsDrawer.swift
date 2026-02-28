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
            .filter { !pendingDeletions.contains($0.id) }
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
                commitDraftSuggestions()
                commitPendingDeletions()
                dismiss()
            }, highlighted: hasChanges)
        ) {
            ScrollView {
                VStack(spacing: 12) {
                    // ─── TITLE ───
                    titleCard

                    // ─── TASKS ───
                    tasksCard

                    // ─── PILL ACTIONS ───
                    actionPillsRow

                    // ─── NOTE ───
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

    // MARK: - Tasks Card

    @ViewBuilder
    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: "Tasks" label + "Suggest Breakdown" button
            HStack {
                Text("Tasks")
                    .font(.inter(.subheadline, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                if !project.isCompleted {
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
                            Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Breakdown"))
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
                ForEach(projectTasks) { task in
                    compactTaskRow(task)
                }

                // Draft AI suggestions (not yet saved)
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

                // New task entry (shown when focused)
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
                .foregroundColor(task.isCompleted ? Color.completedPurple.opacity(0.6) : .secondary.opacity(0.5))

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
        HStack(spacing: 8) {
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

            // Delete circle
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

    private func commitDraftSuggestions() {
        for draft in draftSuggestions {
            let title = draft.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            _Concurrency.Task {
                await viewModel.createProjectTask(title: title, projectId: project.id)
            }
        }
    }

    private func commitPendingDeletions() {
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
