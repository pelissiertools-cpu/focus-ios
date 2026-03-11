//
//  BacklogView.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct BacklogView: View {
    var startWithSearch: Bool = false
    var tasksOnly: Bool = false

    /// Persists inbox filter state within the app session (resets on restart)
    private static var lastInboxFilterUnscheduled: Bool?

    @StateObject private var taskListVM: TaskListViewModel
    @StateObject private var projectsVM: ProjectsViewModel
    @StateObject private var listsVM: ListsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isInlineAddFocused = false
    @State private var isLoading = false

    // Search
    @State private var isSearchActive: Bool
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool

    init(authService: AuthService, startWithSearch: Bool = false, tasksOnly: Bool = false) {
        self.startWithSearch = startWithSearch
        self.tasksOnly = tasksOnly
        _isSearchActive = State(initialValue: startWithSearch)
        _filterUnscheduled = State(initialValue: tasksOnly
            ? (BacklogView.lastInboxFilterUnscheduled ?? true)
            : false)
        _taskListVM = StateObject(wrappedValue: TaskListViewModel(authService: authService))
        _projectsVM = StateObject(wrappedValue: ProjectsViewModel(authService: authService))
        _listsVM = StateObject(wrappedValue: ListsViewModel(authService: authService))
    }

    // Quick filters
    @State private var filterUnscheduled: Bool
    @State private var filterTasks = false
    @State private var filterProjects = false
    @State private var filterLists = false

    // Section collapse states
    @State private var isTasksSectionCollapsed = false
    @State private var isProjectsSectionCollapsed = false
    @State private var isListsSectionCollapsed = false
    // Batch create alerts
    @State private var showCreateProjectAlert = false
    @State private var showCreateListAlert = false
    @State private var newProjectTitle = ""
    @State private var newListTitle = ""

    // Navigation
    @State private var selectedProjectForNavigation: FocusTask?
    @State private var selectedListForNavigation: FocusTask?

    // Add bar state
    @State private var showingAddBar = false

    // MARK: - Computed Properties

    /// True when at least one type pill (Task / Project / Quick List) is active
    private var isAnyTypeFilterActive: Bool {
        filterTasks || filterProjects || filterLists
    }

    /// Whether the Tasks section should be visible given current type filters
    private var showTasksSection: Bool { !isAnyTypeFilterActive || filterTasks }
    /// Whether the Projects section should be visible given current type filters
    private var showProjectsSection: Bool { !tasksOnly && (!isAnyTypeFilterActive || filterProjects) }
    /// Whether the Quick Lists section should be visible given current type filters
    private var showListsSection: Bool { !tasksOnly && (!isAnyTypeFilterActive || filterLists) }

    private var isAnyFilterActive: Bool {
        filterUnscheduled || isAnyTypeFilterActive
    }

    /// All uncompleted standalone tasks (not inside a project)
    private var standaloneTasks: [FocusTask] {
        taskListVM.uncompletedTasks.filter { $0.projectId == nil }
    }

    /// Flattened task display items excluding project-contained tasks
    private var standaloneTaskDisplayItems: [FlatDisplayItem] {
        let projectTaskIds = Set(taskListVM.uncompletedTasks.filter { $0.projectId != nil }.map { $0.id })
        return taskListVM.flattenedDisplayItems.filter { item in
            switch item {
            case .task(let task): return task.projectId == nil
            case .addSubtaskRow(let parentId): return !projectTaskIds.contains(parentId)
            default: return true
            }
        }
    }

    private var allProjects: [FocusTask] {
        projectsVM.projects.filter { !$0.isCompleted && !$0.isCleared }
    }

    private var allLists: [FocusTask] {
        listsVM.lists.filter { !$0.isCompleted && !$0.isCleared }
    }

    private var isEmpty: Bool {
        if isAnyFilterActive {
            return filteredTasks.isEmpty && filteredProjects.isEmpty && filteredLists.isEmpty
        }
        return standaloneTasks.isEmpty && allProjects.isEmpty && allLists.isEmpty
    }

    private var isSearching: Bool {
        isSearchActive && !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func applyQuickFilters(_ items: [FocusTask]) -> [FocusTask] {
        guard filterUnscheduled else { return items }
        return items.filter { !taskListVM.scheduledTaskIds.contains($0.id) }
    }

    private var filteredTasks: [FocusTask] {
        var result = standaloneTasks
        result = applyQuickFilters(result)
        if isSearching {
            let query = searchText.lowercased()
            result = result.filter { $0.title.lowercased().contains(query) }
        }
        return result
    }

    private var filteredTaskDisplayItems: [FlatDisplayItem] {
        let filteredTaskIds = Set(filteredTasks.map { $0.id })
        // Count visible tasks per priority
        let standaloneFiltered = standaloneTaskDisplayItems.filter { item in
            switch item {
            case .task(let task):
                return filteredTaskIds.contains(task.id) ||
                       (task.parentTaskId != nil && filteredTaskIds.contains(task.parentTaskId!))
            case .priorityHeader:
                return true
            case .addSubtaskRow(let parentId): return filteredTaskIds.contains(parentId)
            case .addTaskRow: return true
            case .priorityDropPlaceholder: return false // Remove ViewModel placeholders; we add our own below
            }
        }

        // Determine which priorities have visible parent tasks
        var prioritiesWithTasks = Set<Priority>()
        for item in standaloneFiltered {
            if case .task(let t) = item, t.parentTaskId == nil {
                prioritiesWithTasks.insert(t.priority)
            }
        }

        // Insert placeholders for priority sections that have no visible parent tasks
        var result: [FlatDisplayItem] = []
        for item in standaloneFiltered {
            result.append(item)
            if case .priorityHeader(let priority) = item,
               !prioritiesWithTasks.contains(priority),
               !taskListVM.isPriorityCollapsed(priority) {
                result.append(.priorityDropPlaceholder(priority))
            }
        }
        return result
    }

    private var filteredProjects: [FocusTask] {
        var result = allProjects
        result = applyQuickFilters(result)
        if isSearching {
            let query = searchText.lowercased()
            result = result.filter { $0.title.lowercased().contains(query) }
        }
        return result
    }

    private var filteredLists: [FocusTask] {
        var result = allLists
        result = applyQuickFilters(result)
        if isSearching {
            let query = searchText.lowercased()
            result = result.filter { $0.title.lowercased().contains(query) }
        }
        return result
    }

    private var searchIsEmpty: Bool {
        isSearching && filteredTasks.isEmpty && filteredProjects.isEmpty && filteredLists.isEmpty
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: AppStyle.Spacing.compact) {
                    Image(systemName: tasksOnly ? "tray.and.arrow.down" : "tray")
                        .font(.helveticaNeue(size: 15, weight: .medium))
                        .foregroundColor(.inboxGreen)
                        .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                        .background(Color.inboxBadge, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))

                    Text(tasksOnly ? "Inbox" : "Backlog")
                        .pageTitleStyle()
                        .foregroundColor(.primary)

                    Spacer()

                    Button {
                        withAnimation(AppStyle.Anim.expand) {
                            isSearchActive.toggle()
                            if !isSearchActive {
                                searchText = ""
                                searchFieldFocused = false
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    searchFieldFocused = true
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: AppStyle.Layout.compactButton, height: AppStyle.Layout.compactButton)
                            .background(Color.pillBackground, in: Circle())
                    }
                }
                .padding(.horizontal, AppStyle.Spacing.page)
                .padding(.top, AppStyle.Spacing.section)
                .padding(.bottom, AppStyle.Spacing.compact)

                if isSearchActive {
                    HStack(spacing: AppStyle.Spacing.compact) {
                        Image(systemName: "magnifyingglass")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)

                        TextField(tasksOnly ? "Search tasks..." : "Search tasks, projects, lists...", text: $searchText)
                            .font(.inter(.body))
                            .textFieldStyle(.plain)
                            .focused($searchFieldFocused)
                            .submitLabel(.search)

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.inter(.subheadline))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, AppStyle.Spacing.comfortable)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(Color.pillBackground, in: Capsule())
                    .padding(.horizontal, AppStyle.Spacing.page)
                    .padding(.bottom, AppStyle.Spacing.compact)
                    .transition(.opacity)
                }

                // Quick filter pills
                quickFilterBar

                if isLoading && isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchIsEmpty {
                    VStack(spacing: AppStyle.Spacing.tiny) {
                        Text("No results")
                            .font(AppStyle.Typography.emptyTitle)
                        Text("No items match \"\(searchText)\"")
                            .font(AppStyle.Typography.emptySubtitle)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, AppStyle.Spacing.page)
                } else if isAnyFilterActive && isEmpty {
                    VStack(spacing: AppStyle.Spacing.tiny) {
                        Text("No results")
                            .font(AppStyle.Typography.emptyTitle)
                        Text("No items match the selected filters")
                            .font(AppStyle.Typography.emptySubtitle)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, AppStyle.Spacing.page)
                } else if isEmpty {
                    VStack(spacing: AppStyle.Spacing.tiny) {
                        Text("No items yet")
                            .font(AppStyle.Typography.emptyTitle)
                        Text("All your tasks, projects, and lists will appear here")
                            .font(AppStyle.Typography.emptySubtitle)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, AppStyle.Spacing.page)
                } else {
                    itemList
                }
            }

            // Edit mode action bar
            if taskListVM.isEditMode {
                EditModeActionBar(
                    viewModel: taskListVM,
                    showCreateProjectAlert: $showCreateProjectAlert,
                    showCreateListAlert: $showCreateListAlert
                )
                .transition(.scale.combined(with: .opacity))
            } else if !showingAddBar && !isSearchActive {
                // FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(AppStyle.Anim.modeSwitch) {
                                showingAddBar = true
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.inter(.title2, weight: .semiBold))
                                .foregroundColor(.appText)
                                .frame(width: AppStyle.Layout.fab, height: AppStyle.Layout.fab)
                                .background(Color.cardBackground, in: Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.cardBorder, lineWidth: AppStyle.Border.thin)
                                )
                                .fabShadow()
                        }
                        .accessibilityLabel("Add task")
                        .padding(.trailing, AppStyle.Spacing.page)
                        .padding(.bottom, AppStyle.Spacing.page)
                    }
                }
                .transition(.opacity)
            }

            // Add bar overlay
            if showingAddBar {
                Color.black.opacity(AppStyle.Opacity.scrim)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(50)

                VStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(AppStyle.Anim.modeSwitch) {
                                showingAddBar = false
                            }
                        }

                    AddBar(
                        config: .backlog,
                        categories: taskListVM.categories,
                        activeMode: .constant(.task),
                        onSave: { result in
                            guard case .task(let r) = result else { return }
                            _Concurrency.Task { @MainActor in
                                await taskListVM.createTaskWithSchedules(
                                    title: r.title,
                                    categoryId: r.categoryId,
                                    priority: r.priority,
                                    subtaskTitles: r.subtaskTitles,
                                    scheduleAfterCreate: r.schedule != nil,
                                    selectedTimeframe: r.schedule?.timeframe ?? .daily,
                                    selectedSection: r.schedule?.section ?? .todo,
                                    selectedDates: r.schedule?.dates ?? [],
                                    hasScheduledTime: false,
                                    scheduledTime: nil
                                )
                                if r.schedule != nil {
                                    await focusViewModel.fetchSchedules()
                                }
                            }
                        },
                        onDismiss: {
                            withAnimation(AppStyle.Anim.modeSwitch) {
                                showingAddBar = false
                            }
                        }
                    )
                    .padding(.bottom, AppStyle.Spacing.compact)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .onChange(of: filterUnscheduled) { _, newValue in
            if tasksOnly {
                BacklogView.lastInboxFilterUnscheduled = newValue
            }
        }
        .onChange(of: searchFieldFocused) { _, focused in
            if !focused && searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                withAnimation(AppStyle.Anim.expand) {
                    isSearchActive = false
                }
            }
        }
        // Task sheets
        .sheet(item: $taskListVM.selectedTaskForDetails) { task in
            TaskDetailsDrawer(task: task, viewModel: taskListVM, categories: taskListVM.categories)
                .drawerStyle()
        }
        .sheet(item: $taskListVM.selectedTaskForSchedule) { task in
            ScheduleSelectionSheet(
                task: task,
                focusViewModel: focusViewModel
            )
                .drawerStyle()
        }
        // List sheets
        .sheet(item: $listsVM.selectedListForDetails) { list in
            ListDetailsDrawer(list: list, viewModel: listsVM)
                .drawerStyle()
        }
        .sheet(item: $listsVM.selectedItemForSchedule) { item in
            ScheduleSelectionSheet(
                task: item,
                focusViewModel: focusViewModel
            )
                .drawerStyle()
        }
        // Project sheets
        .sheet(item: $projectsVM.selectedProjectForDetails) { project in
            ProjectDetailsDrawer(project: project, viewModel: projectsVM)
                .drawerStyle()
        }
        .sheet(item: $projectsVM.selectedTaskForSchedule) { task in
            ScheduleSelectionSheet(
                task: task,
                focusViewModel: focusViewModel
            )
                .drawerStyle()
        }
        // Batch operations
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
        .sheet(isPresented: $taskListVM.showBatchScheduleSheet) {
            BatchScheduleSheet(
                viewModel: taskListVM,
                onBatchSchedule: { tasks, timeframe, section, dates in
                    guard !dates.isEmpty else { return }
                    let repo = ScheduleRepository()
                    for task in tasks {
                        for date in dates {
                            let c = Schedule(
                                userId: task.userId, taskId: task.id,
                                timeframe: timeframe, section: section,
                                scheduleDate: Calendar.current.startOfDay(for: date),
                                sortOrder: 0
                            )
                            _Concurrency.Task { _ = try? await repo.createSchedule(c) }
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
            Text("This will permanently delete the selected items and their schedules.")
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
            ToolbarItem(placement: .navigationBarLeading) {
                if taskListVM.isEditMode {
                    Button {
                        taskListVM.exitEditMode()
                    } label: {
                        Text("Done")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.appRed)
                    }
                } else {
                    Button {
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
            ToolbarItem(placement: .navigationBarTrailing) {
                if taskListVM.isEditMode {
                    Button {
                        if taskListVM.allUncompletedSelected {
                            taskListVM.deselectAll()
                        } else {
                            taskListVM.selectAllUncompleted()
                        }
                    } label: {
                        Text(taskListVM.allUncompletedSelected ? "Deselect All" : "Select All")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.appRed)
                    }
                } else {
                    Menu {
                        Menu {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Button {
                                    withAnimation(AppStyle.Anim.toggle) {
                                        taskListVM.sortOption = option
                                    }
                                } label: {
                                    if taskListVM.sortOption == option {
                                        Label(option.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(option.displayName)
                                    }
                                }
                            }

                            Divider()

                            ForEach(taskListVM.sortOption.directionOrder, id: \.self) { direction in
                                Button {
                                    withAnimation(AppStyle.Anim.toggle) {
                                        taskListVM.sortDirection = direction
                                    }
                                } label: {
                                    if taskListVM.sortDirection == direction {
                                        Label(direction.displayName(for: taskListVM.sortOption), systemImage: "checkmark")
                                    } else {
                                        Text(direction.displayName(for: taskListVM.sortOption))
                                    }
                                }
                            }
                        } label: {
                            Label("Sort By", systemImage: "arrow.up.arrow.down")
                        }

                        Divider()

                        Button {
                            taskListVM.enterEditMode()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
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
            // No schedule filter — show ALL tasks
            // Only show loading if no cached data
            if isEmpty {
                isLoading = true
            }
            await loadAllData()
            // Auto-uncheck unscheduled filter if no unscheduled tasks exist
            if tasksOnly && filterUnscheduled {
                let hasUnscheduled = standaloneTasks.contains { !taskListVM.scheduledTaskIds.contains($0.id) }
                if !hasUnscheduled {
                    filterUnscheduled = false
                }
            }
            isLoading = false
        }
        .onAppear {
            if startWithSearch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    searchFieldFocused = true
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        async let cats: () = taskListVM.fetchCategories()
        async let cids: () = taskListVM.fetchScheduledTaskIds()
        _ = await (cats, cids)

        async let t: () = taskListVM.fetchTasks()
        async let p: () = projectsVM.fetchProjects()
        async let l: () = listsVM.fetchLists()
        _ = await (t, p, l)
    }

    private func refreshAllData() async {
        await loadAllData()
    }

    // MARK: - Drag & Drop

    private func handleFilteredMove(from source: IndexSet, to destination: Int) {
        let filtered = filteredTaskDisplayItems
        guard let fromIdx = source.first,
              fromIdx < filtered.count,
              case .task(let movedTask) = filtered[fromIdx],
              movedTask.parentTaskId == nil else { return }

        // Resolve destination priority by walking backwards from destination
        let lookupIdx = max(0, min(destination - 1, filtered.count - 1))
        var destPriority: Priority = .low
        for i in stride(from: lookupIdx, through: 0, by: -1) {
            if case .priorityHeader(let p) = filtered[i] {
                destPriority = p
                break
            }
        }

        if destPriority == movedTask.priority {
            // Same-section reorder: map indices back to ViewModel flat list
            let flat = taskListVM.flattenedDisplayItems
            func flatIndex(for filteredIdx: Int) -> Int? {
                let itemId = filtered[filteredIdx].id
                return flat.firstIndex { $0.id == itemId }
            }
            guard let flatFrom = flatIndex(for: fromIdx) else { return }
            let flatTo: Int
            if destination >= filtered.count {
                if let lastFlat = flatIndex(for: filtered.count - 1) {
                    flatTo = lastFlat + 1
                } else {
                    flatTo = flat.count
                }
            } else if let destFlat = flatIndex(for: destination) {
                flatTo = destFlat
            } else {
                return
            }
            taskListVM.handleFlatMove(from: IndexSet(integer: flatFrom), to: flatTo)
        } else {
            // Cross-section move: find insertion position within destination section
            let destParents = filtered.enumerated().compactMap { (i, item) -> (idx: Int, task: FocusTask)? in
                if case .task(let t) = item, t.parentTaskId == nil, t.priority == destPriority, t.id != movedTask.id { return (i, t) }
                return nil
            }
            var insertAt = destParents.count
            for (pi, entry) in destParents.enumerated() {
                if destination <= entry.idx {
                    insertAt = pi
                    break
                }
            }
            taskListVM.moveTaskToPriority(movedTask.id, to: destPriority, insertAt: insertAt)
        }
    }

    // MARK: - Item List

    private var itemList: some View {
        List {
            // MARK: Tasks Section
            if !tasksOnly && showTasksSection && (!filteredTasks.isEmpty || (!isSearching && !isAnyFilterActive)) {
                tasksSectionHeader
            }

            if showTasksSection && (tasksOnly || !isTasksSectionCollapsed) && (!filteredTasks.isEmpty || (!isSearching && !isAnyFilterActive)) {
                ForEach(filteredTaskDisplayItems) { item in
                    switch item {
                    case .priorityHeader(let priority):
                        PrioritySectionHeader(
                            priority: priority,
                            count: filteredTasks.filter { $0.priority == priority }.count,
                            isCollapsed: taskListVM.isPriorityCollapsed(priority),
                            onToggle: {
                                withAnimation(AppStyle.Anim.toggle) {
                                    taskListVM.togglePriorityCollapsed(priority)
                                }
                            }
                        )
                        .moveDisabled(true)
                        .listRowInsets(AppStyle.Insets.row)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    case .task(let task):
                        FlatTaskRow(
                            task: task,
                            viewModel: taskListVM,
                            isEditMode: taskListVM.isEditMode,
                            isSelected: taskListVM.selectedTaskIds.contains(task.id),
                            onSelectToggle: { taskListVM.toggleTaskSelection(task.id) },
                            onToggleCompletion: { t in
                                taskListVM.requestToggleCompletion(t)
                            },
                            scheduleDate: taskListVM.taskScheduleDates[task.id]
                        )
                        .padding(.leading, task.parentTaskId != nil ? 32 : 0)
                        .moveDisabled(task.isCompleted || taskListVM.isEditMode)
                        .listRowInsets(AppStyle.Insets.row)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(task.parentTaskId != nil ? .visible : .hidden)

                    case .addSubtaskRow(let parentId):
                        InlineAddRow(
                            placeholder: "Subtask title",
                            buttonLabel: "Add subtask",
                            onSubmit: { title in await taskListVM.createSubtask(title: title, parentId: parentId) },
                            isAnyAddFieldActive: $isInlineAddFocused,
                            verticalPadding: AppStyle.Spacing.comfortable
                        )
                        .padding(.leading, 32)
                        .moveDisabled(true)
                        .listRowInsets(AppStyle.Insets.row)
                        .listRowBackground(Color.clear)

                    case .priorityDropPlaceholder:
                        Text("No tasks")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary.opacity(0.4))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                            .listRowInsets(AppStyle.Insets.row)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                    case .addTaskRow(let priority):
                        InlineAddRow(
                            placeholder: "Task title",
                            buttonLabel: "Add task",
                            onSubmit: { title in await taskListVM.createTask(title: title, categoryId: taskListVM.selectedCategoryId, priority: priority) },
                            isAnyAddFieldActive: $isInlineAddFocused,
                            verticalPadding: AppStyle.Spacing.comfortable
                        )
                        .moveDisabled(true)
                        .listRowInsets(AppStyle.Insets.row)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .onMove { from, to in
                    handleFilteredMove(from: from, to: to)
                }
            }

            // MARK: Projects Section
            if showProjectsSection && !filteredProjects.isEmpty {
                projectsSectionHeader

                if !isProjectsSectionCollapsed {
                    ForEach(filteredProjects) { project in
                        BacklogProjectRow(
                            project: project,
                            completed: projectsVM.taskProgress(for: project.id).completed,
                            total: projectsVM.taskProgress(for: project.id).total,
                            onTap: { selectedProjectForNavigation = project },
                            onEdit: { projectsVM.selectedProjectForDetails = project },
                            onSchedule: { projectsVM.selectedTaskForSchedule = project },
                            onDelete: {
                                await projectsVM.deleteProject(project)
                                await refreshAllData()
                            }
                        )
                        .listRowInsets(AppStyle.Insets.row)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }

            // MARK: Quick Lists Section
            if showListsSection && !filteredLists.isEmpty {
                listsSectionHeader

                if !isListsSectionCollapsed {
                    ForEach(filteredLists) { list in
                        BacklogListRow(
                            list: list,
                            onTap: { selectedListForNavigation = list },
                            onEdit: { listsVM.selectedListForDetails = list },
                            onSchedule: { listsVM.selectedItemForSchedule = list },
                            onDelete: {
                                await listsVM.deleteList(list)
                                await refreshAllData()
                            }
                        )
                        .listRowInsets(AppStyle.Insets.row)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }

            // Bottom spacer
            Color.clear
                .frame(height: 100)
                .listRowInsets(AppStyle.Insets.zero)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(
            TapGesture().onEnded {
                searchFieldFocused = false
            }
        )
        .keyboardDismissOverlay(isActive: $isInlineAddFocused)
        .refreshable {
            await withCheckedContinuation { continuation in
                _Concurrency.Task { @MainActor in
                    await refreshAllData()
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Quick Filter Bar

    private var quickFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppStyle.Spacing.compact) {
                BacklogFilterPill(title: "Unscheduled", isSelected: $filterUnscheduled, selectedColor: .inboxGreen)
                if !tasksOnly {
                    BacklogFilterPill(title: "Task", isSelected: $filterTasks)
                    BacklogFilterPill(title: "Project", isSelected: $filterProjects)
                    BacklogFilterPill(title: "Quick List", isSelected: $filterLists)
                }
            }
            .padding(.horizontal, AppStyle.Spacing.page)
        }
        .padding(.bottom, AppStyle.Spacing.tiny)
    }

    // MARK: - Section Headers

    private var tasksSectionHeader: some View {
        Button {
            withAnimation(AppStyle.Anim.toggle) {
                isTasksSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: AppStyle.Spacing.compact) {
                Image(systemName: "checkmark.circle")
                    .font(.inter(.subheadline))
                    .foregroundColor(.appText)
                    .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                    .background(Color.iconBadgeBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))
                Text("Tasks")
                    .font(AppStyle.Typography.sectionHeader)
                    .foregroundColor(.primary)
                Text("\(filteredTasks.count)")
                    .font(AppStyle.Typography.countBadge)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(AppStyle.Typography.chevron)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isTasksSectionCollapsed ? 0 : 90))
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, AppStyle.Spacing.tiny)
        .padding(.bottom, AppStyle.Spacing.tiny)
        .listRowInsets(AppStyle.Insets.row)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var projectsSectionHeader: some View {
        Button {
            withAnimation(AppStyle.Anim.toggle) {
                isProjectsSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: AppStyle.Spacing.compact) {
                Image("ProjectIcon")
                    .renderingMode(.template)
                    .resizable().scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundColor(.appText)
                    .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                    .background(Color.iconBadgeBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))
                Text("Projects")
                    .font(AppStyle.Typography.sectionHeader)
                    .foregroundColor(.primary)
                Text("\(filteredProjects.count)")
                    .font(AppStyle.Typography.countBadge)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(AppStyle.Typography.chevron)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isProjectsSectionCollapsed ? 0 : 90))
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, AppStyle.Spacing.section)
        .padding(.bottom, AppStyle.Spacing.tiny)
        .listRowInsets(AppStyle.Insets.row)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var listsSectionHeader: some View {
        Button {
            withAnimation(AppStyle.Anim.toggle) {
                isListsSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: AppStyle.Spacing.compact) {
                Image(systemName: "checklist")
                    .font(.inter(.subheadline))
                    .foregroundColor(.appText)
                    .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                    .background(Color.iconBadgeBackground, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))
                Text("Quick Lists")
                    .font(AppStyle.Typography.sectionHeader)
                    .foregroundColor(.primary)
                Text("\(filteredLists.count)")
                    .font(AppStyle.Typography.countBadge)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(AppStyle.Typography.chevron)
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isListsSectionCollapsed ? 0 : 90))
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, AppStyle.Spacing.section)
        .padding(.bottom, AppStyle.Spacing.tiny)
        .listRowInsets(AppStyle.Insets.row)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

}

// MARK: - Backlog Filter Pill

private struct BacklogFilterPill: View {
    let title: String
    @Binding var isSelected: Bool
    var selectedColor: Color = .inboxGreen

    var body: some View {
        Button {
            withAnimation(AppStyle.Anim.toggle) {
                isSelected.toggle()
            }
        } label: {
            Text(title)
                .font(.helveticaNeue(size: 13, weight: .medium))
                .tracking(-0.135)
                .foregroundColor(isSelected ? selectedColor : .appText)
                .padding(.horizontal, AppStyle.Spacing.comfortable)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Color.inboxBadge : Color.categoryBackground,
                    in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card)
                        .stroke(isSelected ? Color.clear : Color.cardBorder, lineWidth: AppStyle.Border.thin)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Backlog Project Row

private struct BacklogProjectRow: View {
    let project: FocusTask
    let completed: Int
    let total: Int
    var onTap: () -> Void
    var onEdit: () -> Void
    var onSchedule: () -> Void
    var onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            ProjectProgressRing(
                completed: completed,
                total: total,
                size: AppStyle.Layout.pillButton
            )

            Text(project.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.inter(size: 12, weight: .semiBold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, AppStyle.Spacing.compact)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            ContextMenuItems.editButton { onEdit() }
            ContextMenuItems.scheduleButton { onSchedule() }
            Divider()
            ContextMenuItems.deleteButton { showDeleteConfirmation = true }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                Label("Delete", systemImage: "trash")
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

// MARK: - Backlog List Row

private struct BacklogListRow: View {
    let list: FocusTask
    var onTap: () -> Void
    var onEdit: () -> Void
    var onSchedule: () -> Void
    var onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            Circle()
                .fill(Color.todayBadge)
                .frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)

            Text(list.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.inter(size: 12, weight: .semiBold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, AppStyle.Spacing.compact)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            ContextMenuItems.editButton { onEdit() }
            ContextMenuItems.scheduleButton { onSchedule() }
            Divider()
            ContextMenuItems.deleteButton { showDeleteConfirmation = true }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                Label("Delete", systemImage: "trash")
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
