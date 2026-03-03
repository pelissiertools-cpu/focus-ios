//
//  ScheduledView.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct ScheduledView: View {
    @StateObject private var taskListVM = TaskListViewModel(authService: AuthService())
    @StateObject private var projectsVM = ProjectsViewModel(authService: AuthService())
    @StateObject private var listsVM = ListsViewModel(authService: AuthService())
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isInlineAddFocused = false
    @State private var isLoading = false

    // Pending completions (committed to DB on disappear)
    @State private var pendingCompletions: Set<UUID> = []
    @State private var isCompletedSectionCollapsed = false

    // Batch create alerts
    @State private var showCreateProjectAlert = false
    @State private var showCreateListAlert = false
    @State private var newProjectTitle = ""
    @State private var newListTitle = ""

    // Navigation
    @State private var selectedListForNavigation: FocusTask?
    @State private var selectedProjectForNavigation: FocusTask?

    // Add task bar state
    @State private var showingAddBar = false
    @State private var addTaskTitle = ""
    @State private var addTaskSubtasks: [DraftSubtaskEntry] = []
    @State private var addTaskCategoryId: UUID? = nil
    @State private var addTaskCommitExpanded = false
    @State private var addTaskTimeframe: Timeframe = .daily
    @State private var addTaskSection: Section = .todo
    @State private var addTaskDates: Set<Date> = []
    @State private var addTaskPriority: Priority = .low
    @State private var addTaskOptionsExpanded = false
    @State private var addTaskDatesSnapshot: Set<Date> = []
    @State private var isGeneratingBreakdown = false
    @State private var hasGeneratedBreakdown = false
    @FocusState private var focusedSubtaskId: UUID?
    @FocusState private var addBarTitleFocused: Bool

    private var isAddTaskTitleEmpty: Bool {
        addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Computed: Standalone committed tasks

    private var standaloneTasks: [FocusTask] {
        taskListVM.uncompletedTasks.filter {
            $0.projectId == nil && !pendingCompletions.contains($0.id)
        }
    }

    private var standaloneTaskDisplayItems: [FlatDisplayItem] {
        let pendingIds = pendingCompletions
        return taskListVM.flattenedDisplayItems.filter { item in
            switch item {
            case .task(let task): return task.projectId == nil && !pendingIds.contains(task.id)
            case .addSubtaskRow(let parentId): return !pendingIds.contains(parentId)
            default: return true
            }
        }
    }

    // MARK: - Computed: Scheduled lists

    private var scheduledLists: [FocusTask] {
        listsVM.lists
            .filter { !$0.isCompleted && !$0.isCleared }
            .filter { taskListVM.committedTaskIds.contains($0.id) }
            .filter { !pendingCompletions.contains($0.id) }
    }

    // MARK: - Computed: Projects with scheduled tasks

    private var scheduledProjects: [FocusTask] {
        projectsVM.projects
            .filter { !$0.isCompleted && !$0.isCleared }
            .filter { taskListVM.committedTaskIds.contains($0.id) }
            .filter { !pendingCompletions.contains($0.id) }
    }

    // MARK: - Computed: Completed items

    private var completedItems: [FocusTask] {
        var items: [FocusTask] = []
        for taskId in pendingCompletions {
            if let task = taskListVM.uncompletedTasks.first(where: { $0.id == taskId && $0.projectId == nil }) {
                items.append(task)
                continue
            }
            if let list = listsVM.lists.first(where: { $0.id == taskId }) {
                items.append(list)
                continue
            }
            if let project = projectsVM.projects.first(where: { $0.id == taskId }) {
                items.append(project)
                continue
            }
        }
        return items
    }

    private var isEmpty: Bool {
        standaloneTasks.isEmpty && scheduledLists.isEmpty
        && scheduledProjects.isEmpty && completedItems.isEmpty
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            mainContent
            overlayContent
        }
        .onDisappear { commitPendingCompletions() }
        .onChange(of: showingAddBar) { _, isShowing in
            if isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    addBarTitleFocused = true
                }
            }
        }
        .onChange(of: taskListVM.tasks) { _, _ in
            cleanupPendingCompletions()
        }
        .task {
            taskListVM.commitmentFilter = .committed
            isLoading = true
            await loadAllData()
            isLoading = false
        }
        // Sheets
        .sheet(item: $taskListVM.selectedTaskForDetails) { task in
            TaskDetailsDrawer(task: task, viewModel: taskListVM, categories: taskListVM.categories)
                .drawerStyle()
        }
        .sheet(item: $taskListVM.selectedTaskForSchedule) { task in
            CommitmentSelectionSheet(task: task, focusViewModel: focusViewModel)
                .drawerStyle()
        }
        .sheet(item: $listsVM.selectedListForDetails) { list in
            ListDetailsDrawer(list: list, viewModel: listsVM)
                .drawerStyle()
        }
        .sheet(item: $listsVM.selectedItemForSchedule) { item in
            CommitmentSelectionSheet(task: item, focusViewModel: focusViewModel)
                .drawerStyle()
        }
        .sheet(isPresented: $taskListVM.showBatchMovePicker) {
            BatchMoveCategorySheet(
                viewModel: taskListVM,
                onMoveToProject: { projectId in
                    await taskListVM.batchMoveToProject(projectId)
                    await refreshAllData()
                }
            )
            .drawerStyle()
        }
        .sheet(isPresented: $taskListVM.showBatchCommitSheet) {
            BatchCommitSheet(
                viewModel: taskListVM,
                onBatchSchedule: { tasks, timeframe, section, dates in
                    guard !dates.isEmpty else { return }
                    let repo = CommitmentRepository()
                    for task in tasks {
                        for date in dates {
                            let c = Commitment(
                                userId: task.userId, taskId: task.id,
                                timeframe: timeframe, section: section,
                                commitmentDate: Calendar.current.startOfDay(for: date),
                                sortOrder: 0
                            )
                            _Concurrency.Task { _ = try? await repo.createCommitment(c) }
                        }
                    }
                    _Concurrency.Task { @MainActor in await refreshAllData() }
                }
            )
            .drawerStyle()
        }
        // Alerts
        .alert("Delete \(taskListVM.selectedCount) item\(taskListVM.selectedCount == 1 ? "" : "s")?",
               isPresented: $taskListVM.showBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await taskListVM.batchDeleteTasks()
                    await refreshAllData()
                }
            }
        } message: {
            Text("This will permanently delete the selected items and their commitments.")
        }
        .alert("Create Project", isPresented: $showCreateProjectAlert) {
            TextField("Project title", text: $newProjectTitle)
            Button("Cancel", role: .cancel) { newProjectTitle = "" }
            Button("Create") {
                let title = newProjectTitle
                newProjectTitle = ""
                _Concurrency.Task { @MainActor in
                    await taskListVM.createProjectFromSelected(title: title)
                    await refreshAllData()
                }
            }
        } message: {
            Text("Enter a name for the new project")
        }
        .alert("Create List", isPresented: $showCreateListAlert) {
            TextField("List title", text: $newListTitle)
            Button("Cancel", role: .cancel) { newListTitle = "" }
            Button("Create") {
                let title = newListTitle
                newListTitle = ""
                _Concurrency.Task { @MainActor in
                    await taskListVM.createListFromSelected(title: title)
                    await refreshAllData()
                }
            }
        } message: {
            Text("Enter a name for the new list")
        }
        // Project sheets
        .sheet(item: $projectsVM.selectedProjectForDetails) { project in
            ProjectDetailsDrawer(project: project, viewModel: projectsVM)
                .drawerStyle()
        }
        .sheet(item: $projectsVM.selectedTaskForSchedule) { task in
            CommitmentSelectionSheet(task: task, focusViewModel: focusViewModel)
                .drawerStyle()
        }
        // Navigation
        .navigationDestination(item: $selectedListForNavigation) { list in
            ListContentView(list: list, viewModel: listsVM)
        }
        .navigationDestination(item: $selectedProjectForNavigation) { project in
            ProjectContentView(project: project, viewModel: projectsVM)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { leadingToolbarContent }
            ToolbarItem(placement: .navigationBarTrailing) { trailingToolbarContent }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            headerView
            if isLoading && isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isEmpty {
                emptyStateView
            } else {
                itemList
            }
        }
    }

    @ViewBuilder
    private var headerView: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "tray.full")
                .font(.inter(size: 22, weight: .regular))
                .foregroundColor(.primary)
            Text("Scheduled")
                .font(.inter(size: 28, weight: .regular))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 4) {
            Text("No scheduled items")
                .font(.inter(.headline))
                .bold()
            Text("Scheduled tasks, lists, and projects will appear here")
                .font(.inter(.subheadline))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - Overlay Content

    @ViewBuilder
    private var overlayContent: some View {
        if taskListVM.isEditMode {
            EditModeActionBar(
                viewModel: taskListVM,
                showCreateProjectAlert: $showCreateProjectAlert,
                showCreateListAlert: $showCreateListAlert
            )
            .transition(.scale.combined(with: .opacity))
        } else if !showingAddBar {
            fabButton
        }

        if showingAddBar {
            addBarOverlay
        }
    }

    @ViewBuilder
    private var fabButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingAddBar = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.inter(.title2, weight: .semiBold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular.tint(.charcoal).interactive(), in: .circle)
                        .shadow(radius: 4, y: 2)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var addBarOverlay: some View {
        Color.black.opacity(0.15)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.opacity)
            .zIndex(50)

        VStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dismissAddBar()
                    }
                }
            addTaskBar
                .padding(.bottom, 8)
                .contentShape(Rectangle())
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(100)
    }

    // MARK: - Item List

    private var itemList: some View {
        List {
            tasksSection
            listsSection
            projectsSection
            completedSection

            Color.clear
                .frame(height: 100)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissOverlay(isActive: $isInlineAddFocused)
        .refreshable {
            await withCheckedContinuation { continuation in
                _Concurrency.Task { @MainActor in
                    await loadAllData()
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Tasks Section

    @ViewBuilder
    private var tasksSection: some View {
        if !standaloneTasks.isEmpty || taskListVM.sortOption == .priority {
            sectionHeader(title: "Tasks", icon: "checkmark.circle", count: standaloneTasks.count)

            ForEach(standaloneTaskDisplayItems) { item in
                taskDisplayItemRow(item)
            }
        }
    }

    @ViewBuilder
    private func taskDisplayItemRow(_ item: FlatDisplayItem) -> some View {
        switch item {
        case .priorityHeader(let priority):
            PrioritySectionHeader(
                priority: priority,
                count: standaloneTasks.filter { $0.priority == priority }.count,
                isCollapsed: taskListVM.isPriorityCollapsed(priority),
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        taskListVM.togglePriorityCollapsed(priority)
                    }
                }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

        case .task(let task):
            FlatTaskRow(
                task: task,
                viewModel: taskListVM,
                isEditMode: taskListVM.isEditMode,
                isSelected: taskListVM.selectedTaskIds.contains(task.id),
                onSelectToggle: { taskListVM.toggleTaskSelection(task.id) },
                onToggleCompletion: { t in pendingCompletions.insert(t.id) }
            )
            .padding(.leading, task.parentTaskId != nil ? 32 : 0)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(task.parentTaskId != nil ? .visible : .hidden)

        case .addSubtaskRow(let parentId):
            InlineAddRow(
                placeholder: "Subtask title",
                buttonLabel: "Add subtask",
                onSubmit: { title in await taskListVM.createSubtask(title: title, parentId: parentId) },
                isAnyAddFieldActive: $isInlineAddFocused,
                verticalPadding: 12
            )
            .padding(.leading, 32)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(Color.clear)

        case .addTaskRow:
            EmptyView()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Lists Section

    @ViewBuilder
    private var listsSection: some View {
        if !scheduledLists.isEmpty {
            sectionHeader(title: "Lists", icon: "list.bullet", count: scheduledLists.count)

            ForEach(scheduledLists) { list in
                AssignedListRow(
                    list: list,
                    isEditMode: taskListVM.isEditMode,
                    isSelected: taskListVM.selectedTaskIds.contains(list.id),
                    onSelectToggle: { taskListVM.toggleTaskSelection(list.id) },
                    onTap: { selectedListForNavigation = list },
                    onToggleCompletion: { pendingCompletions.insert(list.id) },
                    onEdit: { listsVM.selectedListForDetails = list },
                    onSchedule: { listsVM.selectedItemForSchedule = list },
                    onDelete: {
                        await listsVM.deleteList(list)
                        await refreshAllData()
                    }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    // MARK: - Projects Section

    @ViewBuilder
    private var projectsSection: some View {
        if !scheduledProjects.isEmpty {
            sectionHeader(title: "Projects", icon: "folder", count: scheduledProjects.count)

            ForEach(scheduledProjects) { project in
                AssignedProjectRow(
                    project: project,
                    isEditMode: taskListVM.isEditMode,
                    isSelected: taskListVM.selectedTaskIds.contains(project.id),
                    onSelectToggle: { taskListVM.toggleTaskSelection(project.id) },
                    onTap: { selectedProjectForNavigation = project },
                    onToggleCompletion: { pendingCompletions.insert(project.id) },
                    onEdit: { projectsVM.selectedProjectForDetails = project },
                    onSchedule: { projectsVM.selectedTaskForSchedule = project },
                    onDelete: {
                        await projectsVM.deleteProject(project)
                        await refreshAllData()
                    }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    // MARK: - Completed Section

    @ViewBuilder
    private var completedSection: some View {
        if !completedItems.isEmpty {
            completedSectionHeader

            if !isCompletedSectionCollapsed {
                ForEach(completedItems) { item in
                    FlatTaskRow(
                        task: item,
                        viewModel: taskListVM,
                        isEditMode: false,
                        isSelected: false,
                        onSelectToggle: nil,
                        onToggleCompletion: { t in pendingCompletions.remove(t.id) },
                        appearCompleted: true
                    )
                    .opacity(0.5)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    // MARK: - Section Headers

    private func sectionHeader(title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.inter(.subheadline, weight: .semiBold))
                .foregroundColor(.appRed)
            Text(title)
                .font(.inter(.headline, weight: .bold))
                .foregroundColor(.appRed)
            Text("\(count)")
                .font(.inter(.caption))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var completedSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCompletedSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.inter(.subheadline))
                    .foregroundColor(.completedPurple)
                Text("Completed")
                    .font(.inter(.headline, weight: .bold))
                    .foregroundColor(.secondary)
                Text("\(completedItems.count)")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.inter(size: 10, weight: .semiBold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isCompletedSectionCollapsed ? 0 : 90))
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        async let c: () = taskListVM.fetchCommittedTaskIds()
        async let cats: () = taskListVM.fetchCategories()
        _ = await (c, cats)

        async let t: () = taskListVM.fetchTasks()
        async let p: () = projectsVM.fetchProjects()
        async let l: () = listsVM.fetchLists()
        _ = await (t, p, l)
    }

    private func refreshAllData() async {
        await loadAllData()
    }

    private func cleanupPendingCompletions() {
        let allKnownIds = Set(taskListVM.uncompletedTasks.map { $0.id })
            .union(Set(listsVM.lists.map { $0.id }))
            .union(Set(projectsVM.projectTasksMap.values.flatMap { $0 }.map { $0.id }))
        for taskId in pendingCompletions {
            if !allKnownIds.contains(taskId) {
                pendingCompletions.remove(taskId)
            }
        }
    }

    private func commitPendingCompletions() {
        let completionsToCommit = pendingCompletions
        guard !completionsToCommit.isEmpty else { return }

        _Concurrency.Task { @MainActor in
            let repository = TaskRepository()
            for taskId in completionsToCommit {
                if let task = taskListVM.uncompletedTasks.first(where: { $0.id == taskId }) {
                    await taskListVM.toggleCompletion(task)
                    continue
                }
                if listsVM.lists.contains(where: { $0.id == taskId }) {
                    try? await repository.completeTask(id: taskId)
                    continue
                }
                if projectsVM.projects.contains(where: { $0.id == taskId }) {
                    try? await repository.completeTask(id: taskId)
                    continue
                }
            }
            pendingCompletions.removeAll()
            await focusViewModel.fetchCommitments()
        }
    }

    // MARK: - Add Task Helpers

    private var categoryPillLabel: String {
        if let categoryId = addTaskCategoryId,
           let category = taskListVM.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private func saveTask() {
        let title = addTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let subtasksToCreate = addTaskSubtasks
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let categoryId = addTaskCategoryId
        let priority = addTaskPriority
        let commitEnabled = !addTaskDates.isEmpty
        let timeframe = addTaskTimeframe
        let section = addTaskSection
        let dates = addTaskDates

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        addBarTitleFocused = true
        focusedSubtaskId = nil
        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskDates = []
        addTaskOptionsExpanded = false
        addTaskCommitExpanded = false
        addTaskPriority = .low
        hasGeneratedBreakdown = false

        _Concurrency.Task { @MainActor in
            await taskListVM.createTaskWithCommitments(
                title: title, categoryId: categoryId, priority: priority,
                subtaskTitles: subtasksToCreate, commitAfterCreate: commitEnabled,
                selectedTimeframe: timeframe, selectedSection: section,
                selectedDates: dates, hasScheduledTime: false, scheduledTime: nil
            )
            if commitEnabled && !dates.isEmpty {
                await focusViewModel.fetchCommitments()
                await refreshAllData()
            }
        }
    }

    private func addNewSubtask() {
        addBarTitleFocused = true
        let newEntry = DraftSubtaskEntry()
        withAnimation(.easeInOut(duration: 0.15)) {
            addTaskSubtasks.append(newEntry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedSubtaskId = newEntry.id
        }
    }

    private func generateBreakdown() {
        let title = addTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        isGeneratingBreakdown = true
        _Concurrency.Task { @MainActor in
            do {
                let aiService = AIService()
                let suggestions = try await aiService.generateSubtasks(title: title, description: nil)
                withAnimation(.easeInOut(duration: 0.2)) {
                    addTaskSubtasks.append(contentsOf: suggestions.map { DraftSubtaskEntry(title: $0) })
                }
                hasGeneratedBreakdown = true
            } catch { }
            isGeneratingBreakdown = false
        }
    }

    private func dismissAddBar() {
        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskCategoryId = nil
        addTaskPriority = .low
        addTaskOptionsExpanded = false
        addTaskCommitExpanded = false
        addTaskDates = []
        hasGeneratedBreakdown = false
        focusedSubtaskId = nil
        addBarTitleFocused = false
        showingAddBar = false
    }
}

// MARK: - Add Task Bar

private extension ScheduledView {
    var addTaskBar: some View {
        VStack(spacing: 0) {
            addBarTitleField
            DraftSubtaskListEditor(
                subtasks: $addTaskSubtasks,
                focusedSubtaskId: $focusedSubtaskId,
                onAddNew: { addNewSubtask() }
            )
            if addTaskCommitExpanded {
                addBarCommitSection
            }
            if !addTaskCommitExpanded {
                addBarButtonRow
            }
            if addTaskOptionsExpanded && !addTaskCommitExpanded {
                addBarOptionsRow
            }
            Spacer().frame(height: 20)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
    }

    var addBarTitleField: some View {
        TextField("Create a new task", text: $addTaskTitle)
            .font(.inter(.title3))
            .textFieldStyle(.plain)
            .focused($addBarTitleFocused)
            .submitLabel(.return)
            .onSubmit { saveTask() }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 10)
    }

    var addBarCommitSection: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 12) {
                Picker("Section", selection: $addTaskSection) {
                    Text("Focus").tag(Section.focus)
                    Text("To-Do").tag(Section.todo)
                }
                .pickerStyle(.segmented)

                UnifiedCalendarPicker(
                    selectedDates: $addTaskDates,
                    selectedTimeframe: $addTaskTimeframe
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 14)

            addBarCommitButtons
        }
    }

    var addBarCommitButtons: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    addTaskDates.removeAll()
                    addTaskCommitExpanded = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray4), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    addTaskCommitExpanded = false
                }
            } label: {
                let hasDateChanges = addTaskDates != addTaskDatesSnapshot
                Image(systemName: "checkmark")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(hasDateChanges ? .white : .secondary)
                    .frame(width: 36, height: 36)
                    .background(hasDateChanges ? Color.appRed : Color(.systemGray4), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    var addBarButtonRow: some View {
        HStack(spacing: 8) {
            Button { addNewSubtask() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.inter(.caption))
                    Text("Sub-task").font(.inter(.caption))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { addTaskOptionsExpanded.toggle() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.inter(.caption, weight: .bold))
                    .foregroundColor(.black)
                    .frame(minHeight: UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Button { generateBreakdown() } label: {
                HStack(spacing: 6) {
                    if isGeneratingBreakdown {
                        ProgressView().tint(.primary)
                    } else {
                        Image(systemName: hasGeneratedBreakdown ? "arrow.clockwise" : "sparkles")
                            .font(.inter(.subheadline, weight: .semiBold))
                            .foregroundColor(!isAddTaskTitleEmpty ? .blue : .primary)
                    }
                    Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Breakdown"))
                        .font(.inter(.caption, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(!isAddTaskTitleEmpty ? Color.pillBackground : Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isAddTaskTitleEmpty || isGeneratingBreakdown)

            Button { saveTask() } label: {
                Image(systemName: "checkmark")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(isAddTaskTitleEmpty ? .secondary : .white)
                    .frame(width: 36, height: 36)
                    .background(isAddTaskTitleEmpty ? Color(.systemGray4) : Color.completedPurple, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isAddTaskTitleEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    var addBarOptionsRow: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    addTaskCategoryId = nil
                } label: {
                    if addTaskCategoryId == nil { Label("None", systemImage: "checkmark") } else { Text("None") }
                }
                ForEach(taskListVM.categories) { category in
                    Button {
                        addTaskCategoryId = category.id
                    } label: {
                        if addTaskCategoryId == category.id { Label(category.name, systemImage: "checkmark") } else { Text(category.name) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder").font(.inter(.caption))
                    Text(LocalizedStringKey(categoryPillLabel)).font(.inter(.caption))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white, in: Capsule())
            }

            Button {
                if !addTaskCommitExpanded { addTaskDatesSnapshot = addTaskDates }
                withAnimation(.easeInOut(duration: 0.2)) { addTaskCommitExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle").font(.inter(.caption))
                    Text("Schedule").font(.inter(.caption))
                }
                .foregroundColor(!addTaskDates.isEmpty ? .white : .black)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(!addTaskDates.isEmpty ? Color.appRed : Color.white, in: Capsule())
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Button {
                        addTaskPriority = priority
                    } label: {
                        if addTaskPriority == priority { Label(priority.displayName, systemImage: "checkmark") } else { Text(priority.displayName) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle().fill(addTaskPriority.dotColor).frame(width: 8, height: 8)
                    Text(addTaskPriority.displayName).font(.inter(.caption))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white, in: Capsule())
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }
}

// MARK: - Toolbar Content

private extension ScheduledView {
    @ViewBuilder
    var leadingToolbarContent: some View {
        if taskListVM.isEditMode {
            Button { taskListVM.exitEditMode() } label: {
                Text("Done")
                    .font(.inter(.body, weight: .medium))
                    .foregroundColor(.appRed)
            }
        } else {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(.primary)
            }
        }
    }

    @ViewBuilder
    var trailingToolbarContent: some View {
        if taskListVM.isEditMode {
            Button {
                if taskListVM.allUncompletedSelected { taskListVM.deselectAll() }
                else { taskListVM.selectAllUncompleted() }
            } label: {
                Text(taskListVM.allUncompletedSelected ? "Deselect All" : "Select All")
                    .font(.inter(.body, weight: .medium))
                    .foregroundColor(.appRed)
            }
        } else {
            trailingMenu
        }
    }

    var trailingMenu: some View {
        Menu {
            Menu {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { taskListVM.sortOption = option }
                    } label: {
                        if taskListVM.sortOption == option { Label(option.displayName, systemImage: "checkmark") }
                        else { Text(option.displayName) }
                    }
                }
                Divider()
                ForEach(taskListVM.sortOption.directionOrder, id: \.self) { direction in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { taskListVM.sortDirection = direction }
                    } label: {
                        if taskListVM.sortDirection == direction { Label(direction.displayName(for: taskListVM.sortOption), systemImage: "checkmark") }
                        else { Text(direction.displayName(for: taskListVM.sortOption)) }
                    }
                }
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
            Divider()
            Button { taskListVM.enterEditMode() } label: {
                Label("Select", systemImage: "checkmark.circle")
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

// MARK: - Assigned Project Row

private struct AssignedProjectRow: View {
    let project: FocusTask
    var isEditMode: Bool
    var isSelected: Bool
    var onSelectToggle: () -> Void
    var onTap: () -> Void
    var onToggleCompletion: () -> Void
    var onEdit: () -> Void
    var onSchedule: () -> Void
    var onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(isSelected ? .appRed : .secondary)
            }
            ProjectIconShape()
                .frame(width: 24, height: 24)
                .foregroundColor(.secondary)
            Text(project.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            if !isEditMode {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onToggleCompletion()
                } label: {
                    Image(systemName: "circle")
                        .font(.inter(.title3))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if isEditMode { onSelectToggle() } else { onTap() } }
        .contextMenu {
            if !isEditMode {
                ContextMenuItems.editButton { onEdit() }
                ContextMenuItems.scheduleButton { onSchedule() }
                Divider()
                ContextMenuItems.deleteButton { showDeleteConfirmation = true }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isEditMode {
                Button(role: .destructive) { showDeleteConfirmation = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .alert("Delete Project", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { _Concurrency.Task { await onDelete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(project.title)\"?")
        }
    }
}

// MARK: - Assigned List Row

private struct AssignedListRow: View {
    let list: FocusTask
    var isEditMode: Bool
    var isSelected: Bool
    var onSelectToggle: () -> Void
    var onTap: () -> Void
    var onToggleCompletion: () -> Void
    var onEdit: () -> Void
    var onSchedule: () -> Void
    var onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(isSelected ? .appRed : .secondary)
            }
            Image(systemName: "list.bullet")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24)
            Text(list.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            if !isEditMode {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onToggleCompletion()
                } label: {
                    Image(systemName: "circle")
                        .font(.inter(.title3))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if isEditMode { onSelectToggle() } else { onTap() } }
        .contextMenu {
            if !isEditMode {
                ContextMenuItems.editButton { onEdit() }
                ContextMenuItems.scheduleButton { onSchedule() }
                Divider()
                ContextMenuItems.deleteButton { showDeleteConfirmation = true }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isEditMode {
                Button(role: .destructive) { showDeleteConfirmation = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .alert("Delete List", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { _Concurrency.Task { await onDelete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(list.title)\"?")
        }
    }
}
