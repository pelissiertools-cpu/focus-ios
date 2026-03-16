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
    @State private var activeAddRowId: String?
    @State private var scrollToAddTrigger = 0
    @State private var projectTitle: String
    @State private var projectNotes: String
    @State private var editingSectionId: UUID?
    @State private var scrollToSectionId: UUID?
    @State private var showManageSharing = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNotesFocused: Bool

    private var isProjectCompleted: Bool {
        viewModel.projects.first(where: { $0.id == project.id })?.isCompleted ?? project.isCompleted
    }

    init(project: FocusTask, viewModel: ProjectsViewModel) {
        self.project = project
        self.viewModel = viewModel
        _projectTitle = State(initialValue: project.title)
        _projectNotes = State(initialValue: project.description ?? "")
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollViewReader { proxy in
                List {
                    // Project title
                    HStack(spacing: AppStyle.Spacing.medium) {
                        if isProjectCompleted {
                            Text(projectTitle)
                                .font(.inter(.title2, weight: .bold))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            TextField("Project name", text: $projectTitle, axis: .vertical)
                                .font(.inter(.title2, weight: .bold))
                                .foregroundColor(.primary)
                                .textFieldStyle(.plain)
                                .focused($isTitleFocused)
                                .onSubmit { saveProjectTitle() }
                        }

                        if viewModel.sharedTaskIds.contains(project.id) {
                            Image(systemName: "person.2.fill")
                                .font(.inter(.subheadline))
                                .foregroundColor(.secondary)
                        }

                        let progress = viewModel.taskProgress(for: project.id)
                        if progress.total > 0 {
                            Text("\(Int(Double(progress.completed) / Double(progress.total) * 100))%")
                                .font(.inter(.subheadline))
                                .foregroundColor(.secondary)
                            ProjectProgressRing(
                                completed: progress.completed,
                                total: progress.total,
                                size: 28
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: AppStyle.Spacing.section, leading: AppStyle.Spacing.page, bottom: 0, trailing: AppStyle.Spacing.page))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                    // Task count
                    let totalTasks = (viewModel.projectTasksMap[project.id] ?? []).filter { !$0.isSection }.count
                    if totalTasks > 0 {
                        Text("\(totalTasks) task\(totalTasks == 1 ? "" : "s")")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)
                            .listRowInsets(EdgeInsets(top: 0, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.tiny, trailing: AppStyle.Spacing.page))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .moveDisabled(true)
                    }

                    // Notes
                    Group {
                        if isProjectCompleted {
                            if !projectNotes.isEmpty {
                                Text(linkifiedText(projectNotes))
                                    .font(.inter(.body))
                                    .foregroundColor(.secondary)
                                    .tint(.blue.opacity(0.5))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if isNotesFocused || projectNotes.isEmpty {
                            TextField("Notes", text: $projectNotes, axis: .vertical)
                                .font(.inter(.body))
                                .foregroundColor(.secondary)
                                .textFieldStyle(.plain)
                                .focused($isNotesFocused)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(linkifiedText(projectNotes))
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
                    if viewModel.isLoadingProjectTasks.contains(project.id) && viewModel.projectTasksMap[project.id] == nil {
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
                        let items = viewModel.flattenedProjectItems(for: project.id)
                        let hasRealTasks = items.contains { if case .task = $0 { return true }; return false }

                        if !hasRealTasks && !isProjectCompleted {
                            Text("No tasks yet")
                                .font(AppStyle.Typography.emptyTitle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .listRowInsets(EdgeInsets(top: 0, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.compact, trailing: AppStyle.Spacing.page))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .moveDisabled(true)
                        }

                        ForEach(items) { item in
                            switch item {
                            case .section(let section):
                                ProjectSectionRow(
                                    section: section,
                                    viewModel: viewModel,
                                    projectId: project.id,
                                    editingSectionId: $editingSectionId
                                )
                                .id(section.id)
                                .listRowInsets(AppStyle.Insets.row)
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
                                .listRowInsets(AppStyle.Insets.row)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            case .addSubtaskRow(let parentId):
                                if !viewModel.contentEditMode {
                                    let rowId = "add-subtask-\(parentId.uuidString)"
                                    InlineAddRow(
                                        placeholder: "Subtask title",
                                        buttonLabel: "Add subtask",
                                        onSubmit: { title in
                                            await viewModel.createSubtask(title: title, parentId: parentId)
                                            scrollToAddTrigger += 1
                                        },
                                        isAnyAddFieldActive: Binding(
                                            get: { isInlineAddFocused },
                                            set: { newValue in
                                                isInlineAddFocused = newValue
                                                if newValue { activeAddRowId = rowId }
                                            }
                                        ),
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
                                ProjectContentDonePill(
                                    count: count,
                                    isCollapsed: viewModel.isContentDoneCollapsed,
                                    onToggle: { viewModel.toggleContentDoneCollapsed() }
                                )
                                .moveDisabled(true)
                                .listRowInsets(AppStyle.Insets.row)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            case .addTaskRow(let sectionId):
                                if !viewModel.contentEditMode {
                                    let rowId = item.id
                                    InlineAddRow(
                                        placeholder: "Task title",
                                        buttonLabel: "Add task",
                                        onSubmit: { title in
                                            await viewModel.createProjectTaskInSection(title: title, projectId: project.id, sectionId: sectionId)
                                            scrollToAddTrigger += 1
                                        },
                                        isAnyAddFieldActive: Binding(
                                            get: { isInlineAddFocused },
                                            set: { newValue in
                                                isInlineAddFocused = newValue
                                                if newValue { activeAddRowId = rowId }
                                            }
                                        ),
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
                                viewModel.handleProjectContentFlatMove(from: from, to: to, projectId: project.id)
                            }
                        }
                    }

                    Color.clear
                        .frame(height: 500)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil, from: nil, for: nil
                            )
                        }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.never)
                .keyboardDismissOverlay(isActive: $isInlineAddFocused)
                .onChange(of: isInlineAddFocused) { _, focused in
                    if focused, let targetId = activeAddRowId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(targetId, anchor: UnitPoint(x: 0.5, y: 0.5))
                            }
                        }
                    }
                }
                .onChange(of: scrollToAddTrigger) { _, _ in
                    guard isInlineAddFocused, let targetId = activeAddRowId else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(targetId, anchor: UnitPoint(x: 0.5, y: 0.5))
                        }
                    }
                }
                .onChange(of: scrollToSectionId) { _, newId in
                    if let sectionId = newId {
                        scrollToSectionId = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(sectionId, anchor: UnitPoint(x: 0.5, y: 0.75))
                            }
                        }
                    }
                }
            }

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
                            .foregroundColor(.focusBlue)
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
                            .frame(width: AppStyle.Layout.touchTarget, height: AppStyle.Layout.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Back")
                }
            }
            ToolbarItem(placement: .principal) {
                Text("Project")
                    .font(.inter(.subheadline, weight: .medium))
                    .foregroundColor(.secondary)
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
                if isProjectCompleted {
                    EmptyView()
                } else if viewModel.contentEditMode {
                    Button {
                        if viewModel.allContentTasksSelected {
                            viewModel.deselectAllContentTasks()
                        } else {
                            viewModel.selectAllContentTasks(projectId: project.id)
                        }
                    } label: {
                        Text(viewModel.allContentTasksSelected ? "Deselect All" : "Select All")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.focusBlue)
                    }
                } else {
                    Menu {
                        if viewModel.sharedTaskIds.contains(project.id) {
                            Button {
                                showManageSharing = true
                            } label: {
                                Label("Manage Sharing", systemImage: "person.2")
                            }
                        }

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
                                    scrollToSectionId = newSection.id
                                }
                            }
                        } label: {
                            Label("Add section", systemImage: "plus")
                        }

                        Button {
                            ShareSheetHelper.share(task: project)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        ContextMenuItems.pinButton(isPinned: project.isPinned) {
                            _Concurrency.Task { await viewModel.toggleProjectPin(project) }
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
            saveProjectTitle()
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
                tasks: (viewModel.projectTasksMap[project.id] ?? []).filter { viewModel.selectedContentTaskIds.contains($0.id) },
                onComplete: { viewModel.exitContentEditMode() }
            )
            .drawerStyle()
        }
        .sheet(isPresented: $viewModel.showContentBatchMovePicker) {
            ContentBatchMoveSheet(source: .project(id: project.id, viewModel: viewModel))
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
                focusViewModel: focusViewModel
            )
                .drawerStyle()
        }
        .sheet(isPresented: $showManageSharing) {
            ManageSharingSheet(task: project)
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

    private var isScheduled: Bool {
        viewModel.scheduledTaskIds.contains(task.id)
    }

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            if viewModel.contentEditMode {
                Image(systemName: viewModel.selectedContentTaskIds.contains(task.id) ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(viewModel.selectedContentTaskIds.contains(task.id) ? .appRed : .secondary)
                    .accessibilityLabel(viewModel.selectedContentTaskIds.contains(task.id) ? "Selected" : "Select")
            }

            VStack(alignment: .leading, spacing: AppStyle.Spacing.tiny) {
                Text(task.title)
                    .font(AppStyle.Typography.itemTitle)
                    .strikethrough(displayCompleted)
                    .foregroundColor(displayCompleted ? .secondary : .primary)

                if subtaskCount > 0 || isScheduled {
                    HStack(spacing: AppStyle.Spacing.small) {
                        if subtaskCount > 0 {
                            Text("\(subtaskCount) subtask\(subtaskCount == 1 ? "" : "s")")
                                .font(.inter(.caption))
                                .foregroundColor(.secondary)
                        }
                        if isScheduled {
                            Image(systemName: "calendar")
                                .font(.inter(.caption2))
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: AppStyle.Layout.iconButton, alignment: .leading)

            if !viewModel.contentEditMode {
                Button {
                    UIImpactFeedbackGenerator(style: isPending ? .light : .medium).impactOccurred()
                    viewModel.requestToggleTaskCompletion(task, projectId: projectId)
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

                if isScheduled {
                    ContextMenuItems.unscheduleButton {
                        _Concurrency.Task {
                            try? await ScheduleRepository().deleteSchedules(forTask: task.id)
                            await viewModel.fetchScheduledTaskIds()
                        }
                    }
                }

                ContextMenuItems.pinButton(isPinned: task.isPinned) {
                    _Concurrency.Task { await viewModel.togglePin(task, projectId: projectId) }
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
                    await viewModel.deleteProjectTask(task, projectId: projectId)
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
                        await viewModel.deleteProjectTask(task, projectId: projectId)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
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

                HStack(alignment: .top, spacing: AppStyle.Spacing.content) {
                    // Floating labels
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

                    // Vertical glass capsule with icons
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

    private var taskCount: Int {
        viewModel.sectionTaskCount(sectionId: section.id, projectId: projectId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            HStack {
                TextField("Section name", text: $sectionTitle)
                    .font(.inter(.headline, weight: .bold))
                    .foregroundColor(.focusBlue)
                    .textFieldStyle(.plain)
                    .focused($isEditing)
                    .onSubmit { saveSectionTitle() }
                    .allowsHitTesting(isEditing)

                Spacer()

                if taskCount > 0 {
                    Text("\(taskCount)")
                        .font(.inter(.caption, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, AppStyle.Spacing.section)

            Rectangle()
                .fill(Color.cardBorder)
                .frame(height: AppStyle.Border.thin)
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
        .onAppear {
            if editingSectionId == section.id {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isEditing = true
                    editingSectionId = nil
                }
            }
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
        .onChange(of: section.title) { _, newTitle in
            if !isEditing { sectionTitle = newTitle }
        }
    }

    private func saveSectionTitle() {
        let trimmed = sectionTitle.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
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
