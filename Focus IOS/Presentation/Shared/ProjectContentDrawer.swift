//
//  ProjectContentDrawer.swift
//  Focus IOS
//

import SwiftUI

struct ProjectContentView: View {
    let project: FocusTask
    @ObservedObject var viewModel: ProjectsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isInlineAddFocused = false
    @State private var projectTitle: String
    @State private var projectNotes: String
    @State private var editingSectionId: UUID?
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNotesFocused: Bool

    init(project: FocusTask, viewModel: ProjectsViewModel) {
        self.project = project
        self.viewModel = viewModel
        _projectTitle = State(initialValue: project.title)
        _projectNotes = State(initialValue: project.description ?? "")
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Project title — editable inline
                    TextField("Project name", text: $projectTitle, axis: .vertical)
                        .font(.inter(.title2, weight: .bold))
                        .foregroundColor(.primary)
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .onSubmit { saveProjectTitle() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                    // Notes
                    if isNotesFocused || projectNotes.isEmpty {
                        TextField("Notes", text: $projectNotes, axis: .vertical)
                            .font(.inter(.body))
                            .foregroundColor(.secondary)
                            .textFieldStyle(.plain)
                            .focused($isNotesFocused)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    } else {
                        Text(linkifiedText(projectNotes))
                            .font(.inter(.body))
                            .foregroundColor(.secondary)
                            .tint(.blue.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isNotesFocused = true
                            }
                    }

                    // Task/section list
                    contentList
                }
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            })

            // Edit mode action bar
            if viewModel.contentEditMode {
                ContentEditModeActionBar(viewModel: viewModel, projectId: project.id)
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
                        saveProjectTitle()
                        saveProjectNotes()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .contentShape(Circle())
                    }
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
                            viewModel.selectAllContentTasks(projectId: project.id)
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
                                    projectId: project.id
                                )
                                if let tasks = viewModel.projectTasksMap[project.id],
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
                            .frame(width: 30, height: 30)
                            .background(Color.pillBackground, in: Circle())
                    }
                }
            }
        }
        .task {
            if viewModel.projectTasksMap[project.id] == nil {
                await viewModel.fetchProjectTasks(for: project.id)
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused { saveProjectTitle() }
        }
        .onChange(of: isNotesFocused) { _, focused in
            if !focused { saveProjectNotes() }
        }
        .onDisappear {
            saveProjectNotes()
            if viewModel.contentEditMode {
                viewModel.exitContentEditMode()
            }
        }
        .alert("Delete \(viewModel.selectedContentTaskIds.count) task\(viewModel.selectedContentTaskIds.count == 1 ? "" : "s")?",
               isPresented: $viewModel.showContentBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.batchDeleteContentTasks(projectId: project.id)
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
        .sheet(isPresented: $viewModel.showContentBatchMovePicker) {
            // Placeholder — to be wired later
            Text("Move")
                .drawerStyle()
        }
        // Task edit drawer
        .sheet(item: $viewModel.selectedTaskForDetails) { task in
            TaskDetailsDrawer(task: task, viewModel: viewModel, categories: viewModel.categories)
                .drawerStyle()
        }
        // Task schedule sheet
        .sheet(item: $viewModel.selectedTaskForSchedule) { task in
            ScheduleSelectionSheet(
                task: task,
                focusViewModel: focusViewModel,
                onSomeday: {
                    _Concurrency.Task { await viewModel.moveTaskToSomeday(task) }
                },
                isSomedayTask: task.categoryId == viewModel.somedayCategory?.id
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

    private func saveProjectTitle() {
        let trimmed = projectTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != project.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(project, newTitle: trimmed)
        }
    }

    private func saveProjectNotes() {
        let newNote = projectNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = project.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard newNote != current else { return }
        _Concurrency.Task {
            await viewModel.updateTaskNote(project, newNote: newNote.isEmpty ? nil : newNote)
        }
    }

    // MARK: - Content List

    @ViewBuilder
    private var contentList: some View {
        if viewModel.isLoadingProjectTasks.contains(project.id) {
            HStack {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            }
            .padding()
        } else {
            let items = viewModel.flattenedProjectItems(for: project.id)

            if items.count <= 1 {
                // Only addTaskRow — no tasks yet
                Text("No tasks yet")
                    .font(.inter(.headline))
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                InlineAddRow(
                    placeholder: "Task title",
                    buttonLabel: "Add task",
                    onSubmit: { title in await viewModel.createProjectTask(title: title, projectId: project.id) },
                    isAnyAddFieldActive: $isInlineAddFocused,
                    verticalPadding: 8
                )
                .padding(.horizontal, 20)
            } else {
                List {
                    ForEach(items) { item in
                        switch item {
                        case .section(let section):
                            ProjectSectionRow(
                                section: section,
                                viewModel: viewModel,
                                projectId: project.id,
                                editingSectionId: $editingSectionId
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        case .task(let task):
                            Group {
                                if task.parentTaskId != nil {
                                    ProjectSubtaskRow(
                                        subtask: task,
                                        parentId: task.parentTaskId!,
                                        viewModel: viewModel
                                    )
                                    .padding(.leading, viewModel.contentEditMode ? 0 : 32)
                                } else {
                                    ContentTaskRow(
                                        task: task,
                                        projectId: project.id,
                                        viewModel: viewModel
                                    )
                                }
                            }
                            .moveDisabled(task.isCompleted || viewModel.contentEditMode)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
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
                                    verticalPadding: 6
                                )
                                .padding(.leading, 32)
                                .moveDisabled(true)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }

                        case .completedHeader(let count):
                            ProjectContentDonePill(
                                count: count,
                                isCollapsed: viewModel.isContentDoneCollapsed,
                                onToggle: { viewModel.toggleContentDoneCollapsed() }
                            )
                            .moveDisabled(true)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        case .addTaskRow:
                            if !viewModel.contentEditMode {
                                InlineAddRow(
                                    placeholder: "Task title",
                                    buttonLabel: "Add task",
                                    onSubmit: { title in await viewModel.createProjectTask(title: title, projectId: project.id) },
                                    isAnyAddFieldActive: $isInlineAddFocused,
                                    verticalPadding: 8
                                )
                                .moveDisabled(true)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .onMove { from, to in
                        if !viewModel.contentEditMode {
                            viewModel.handleProjectContentFlatMove(from: from, to: to, projectId: project.id)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .keyboardDismissOverlay(isActive: $isInlineAddFocused)
                .frame(minHeight: items.reduce(CGFloat(0)) { sum, item in
                    switch item {
                    case .section: return sum + 58
                    case .task(let t) where t.parentTaskId == nil: return sum + 56
                    case .completedHeader: return sum + 52
                    case .addTaskRow: return viewModel.contentEditMode ? sum : sum + 56
                    case .addSubtaskRow: return viewModel.contentEditMode ? sum : sum + 44
                    default: return sum + 44
                    }
                } + 20)
            }
        }
    }
}

// MARK: - Content Task Row (with selection support)

private struct ContentTaskRow: View {
    let task: FocusTask
    let projectId: UUID
    @ObservedObject var viewModel: ProjectsViewModel
    @State private var showDeleteConfirmation = false

    private var isPending: Bool { viewModel.isPendingCompletion(task.id) }
    private var displayCompleted: Bool { task.isCompleted || isPending }

    private var subtaskCount: Int {
        (viewModel.subtasksMap[task.id] ?? []).count
    }

    var body: some View {
        HStack(spacing: 12) {
            // Selection circle in edit mode
            if viewModel.contentEditMode {
                Image(systemName: viewModel.selectedContentTaskIds.contains(task.id) ? "checkmark.circle.fill" : "circle")
                    .font(.inter(.title3))
                    .foregroundColor(viewModel.selectedContentTaskIds.contains(task.id) ? .appRed : .secondary)
            }

            // Task title + subtask count
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.inter(.body))
                    .strikethrough(displayCompleted)
                    .foregroundColor(displayCompleted ? .secondary : .primary)

                if subtaskCount > 0 {
                    Text("\(subtaskCount) subtask\(subtaskCount == 1 ? "" : "s")")
                        .font(.inter(.caption))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)

            if !viewModel.contentEditMode {
                // Completion button
                Button {
                    UIImpactFeedbackGenerator(style: isPending ? .light : .medium).impactOccurred()
                    viewModel.requestToggleTaskCompletion(task, projectId: projectId)
                } label: {
                    Image(systemName: displayCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.inter(.title3))
                        .foregroundColor(displayCompleted ? Color.completedPurple.opacity(0.6) : .gray)
                        .symbolEffect(.pulse, isActive: isPending)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !viewModel.contentEditMode && !task.isCompleted {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .alert("Delete Task", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await viewModel.deleteProjectTask(task, projectId: projectId)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(task.title)\"?")
        }
    }
}

// MARK: - Content Edit Mode Action Bar

struct ContentEditModeActionBar: View {
    @ObservedObject var viewModel: ProjectsViewModel
    let projectId: UUID

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
            ActionItem(icon: "arrow.right", label: "Move", isDestructive: false) {
                viewModel.showContentBatchMovePicker = true
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

                HStack(alignment: .top, spacing: 14) {
                    // Floating labels
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(actions.reversed().enumerated()), id: \.element.id) { _, item in
                            Text(LocalizedStringKey(item.label))
                                .font(.inter(.subheadline, weight: .medium))
                                .foregroundColor(item.isDestructive ? .red : .primary)
                                .frame(height: 52)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if hasSelection { item.action() }
                                }
                        }
                    }

                    // Vertical glass capsule with icons
                    VStack(spacing: 0) {
                        ForEach(Array(actions.reversed().enumerated()), id: \.element.id) { index, item in
                            Button {
                                item.action()
                            } label: {
                                Image(systemName: item.icon)
                                    .font(.inter(.title3))
                                    .foregroundColor(item.isDestructive ? .red : .primary)
                                    .frame(width: 52, height: 52)
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
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .shadow(radius: 4, y: 2)
                }
                .opacity(hasSelection ? 1.0 : 0.5)
                .padding(.trailing, 20)
                .padding(.top, 62)
            }
            Spacer()
        }
    }
}

// MARK: - Project Section Row

struct ProjectSectionRow: View {
    let section: FocusTask
    @ObservedObject var viewModel: ProjectsViewModel
    let projectId: UUID
    @Binding var editingSectionId: UUID?
    @State private var sectionTitle: String
    @State private var showDeleteConfirmation = false
    @FocusState private var isEditing: Bool

    init(section: FocusTask, viewModel: ProjectsViewModel, projectId: UUID, editingSectionId: Binding<UUID?>) {
        self.section = section
        self.viewModel = viewModel
        self.projectId = projectId
        self._editingSectionId = editingSectionId
        _sectionTitle = State(initialValue: section.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Section name", text: $sectionTitle)
                .font(.inter(.headline, weight: .bold))
                .foregroundColor(.appRed)
                .textFieldStyle(.plain)
                .focused($isEditing)
                .onSubmit { saveSectionTitle() }
                .padding(.top, 16)

            Rectangle()
                .fill(Color.secondary.opacity(0.7))
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
                    await viewModel.deleteSection(section, projectId: projectId)
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
                await viewModel.deleteSection(section, projectId: projectId)
            }
            return
        }
        guard trimmed != section.title else { return }
        _Concurrency.Task {
            await viewModel.renameSection(section, newTitle: trimmed)
        }
    }
}

// MARK: - Project Content Done Pill

private struct ProjectContentDonePill: View {
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Completed")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("\(count)")
                        .font(.inter(size: 12))
                        .foregroundColor(.secondary)

                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.inter(size: 8, weight: .semiBold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .clipShape(Capsule())
                .glassEffect(.regular.tint(.glassTint).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.vertical, 10)
    }
}
