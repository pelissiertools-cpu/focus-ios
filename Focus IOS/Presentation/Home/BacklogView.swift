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

    // Add task bar state
    @State private var showingAddBar = false
    @State private var addTaskTitle = ""
    @State private var addTaskSubtasks: [DraftSubtaskEntry] = []
    @State private var addTaskCategoryId: UUID? = nil
    @State private var addTaskScheduleExpanded = false
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
        return standaloneTaskDisplayItems.filter { item in
            switch item {
            case .task(let task): return filteredTaskIds.contains(task.id)
            case .priorityHeader(let priority):
                return filteredTasks.contains { $0.priority == priority }
            case .addSubtaskRow(let parentId): return filteredTaskIds.contains(parentId)
            case .addTaskRow: return false
            }
        }
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
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: AppStyle.Spacing.compact) {
                    Image(systemName: tasksOnly ? "tray.and.arrow.down" : "tray")
                        .font(.inter(size: 22, weight: .regular))
                        .foregroundColor(.primary)

                    Text(tasksOnly ? "Inbox" : "Backlog")
                        .pageTitleStyle()
                        .foregroundColor(.primary)

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
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
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showingAddBar = true
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.inter(.title2, weight: .semiBold))
                                .foregroundColor(.white)
                                .frame(width: AppStyle.Layout.fab, height: AppStyle.Layout.fab)
                                .glassEffect(.regular.tint(.charcoal).interactive(), in: .circle)
                                .shadow(radius: 4, y: 2)
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
                        .padding(.bottom, AppStyle.Spacing.compact)
                        .contentShape(Rectangle())
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
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSearchActive = false
                }
            }
        }
        .onChange(of: showingAddBar) { _, isShowing in
            if isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    addBarTitleFocused = true
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
                                    withAnimation(.easeInOut(duration: 0.2)) {
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
                                    withAnimation(.easeInOut(duration: 0.2)) {
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
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    taskListVM.togglePriorityCollapsed(priority)
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: AppStyle.Spacing.section, bottom: 0, trailing: AppStyle.Spacing.section))
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
                            }
                        )
                        .padding(.leading, task.parentTaskId != nil ? 32 : 0)
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
                        .listRowInsets(AppStyle.Insets.row)
                        .listRowBackground(Color.clear)

                    case .addTaskRow:
                        EmptyView()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }

            // MARK: Projects Section
            if showProjectsSection && !filteredProjects.isEmpty {
                projectsSectionHeader

                if !isProjectsSectionCollapsed {
                    ForEach(filteredProjects) { project in
                        BacklogProjectRow(
                            project: project,
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
                BacklogFilterPill(title: "Unscheduled", isSelected: $filterUnscheduled)
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
            withAnimation(.easeInOut(duration: 0.2)) {
                isTasksSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: AppStyle.Spacing.compact) {
                Image(systemName: "checkmark.circle")
                    .font(.inter(.subheadline))
                    .foregroundColor(.appRed)
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
            withAnimation(.easeInOut(duration: 0.2)) {
                isProjectsSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: AppStyle.Spacing.compact) {
                Image(systemName: "folder")
                    .font(.system(size: 14))
                    .foregroundColor(.appRed)
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
            withAnimation(.easeInOut(duration: 0.2)) {
                isListsSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: AppStyle.Spacing.compact) {
                Image(systemName: "list.bullet")
                    .font(.inter(.subheadline))
                    .foregroundColor(.appRed)
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

// MARK: - Add Task Bar

private extension BacklogView {
    var categoryPillLabel: String {
        if let categoryId = addTaskCategoryId,
           let category = taskListVM.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    var addTaskBar: some View {
        VStack(spacing: 0) {
            TextField("Create a new task", text: $addTaskTitle)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocused)
                .submitLabel(.return)
                .onSubmit { saveTask() }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.page)
                .padding(.bottom, AppStyle.Spacing.medium)

            DraftSubtaskListEditor(
                subtasks: $addTaskSubtasks,
                focusedSubtaskId: $focusedSubtaskId,
                onAddNew: { addNewSubtask() }
            )

            if addTaskScheduleExpanded {
                Divider()
                    .padding(.horizontal, AppStyle.Spacing.content)

                VStack(alignment: .leading, spacing: AppStyle.Spacing.comfortable) {
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
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.small)
                .padding(.bottom, AppStyle.Spacing.content)

                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            addTaskDates.removeAll()
                            addTaskScheduleExpanded = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(.primary)
                            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                            .background(Color(.systemGray4), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    let hasDateChanges = addTaskDates != addTaskDatesSnapshot
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            addTaskScheduleExpanded = false
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(hasDateChanges ? .white : .secondary)
                            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                            .background(
                                hasDateChanges ? Color.appRed : Color(.systemGray4),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.bottom, AppStyle.Spacing.tiny)
            }

            if !addTaskScheduleExpanded {
                HStack(spacing: AppStyle.Spacing.compact) {
                    Button {
                        addNewSubtask()
                    } label: {
                        HStack(spacing: AppStyle.Spacing.tiny) {
                            Image(systemName: "plus")
                                .font(.inter(.caption))
                            Text("Sub-task")
                                .font(.inter(.caption))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .background(Color.black, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            addTaskOptionsExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.inter(.caption, weight: .bold))
                            .foregroundColor(.black)
                            .frame(minHeight: UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
                            .padding(.horizontal, AppStyle.Spacing.medium)
                            .padding(.vertical, AppStyle.Spacing.compact)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

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
                                    .foregroundColor(!isAddTaskTitleEmpty ? .blue : .primary)
                            }
                            Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Breakdown"))
                                .font(.inter(.caption, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, AppStyle.Spacing.content)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .background(
                            !isAddTaskTitleEmpty ? Color.pillBackground : Color.clear,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isAddTaskTitleEmpty || isGeneratingBreakdown)

                    Button {
                        saveTask()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.inter(.body, weight: .semiBold))
                            .foregroundColor(isAddTaskTitleEmpty ? .secondary : .white)
                            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                            .background(
                                isAddTaskTitleEmpty ? Color(.systemGray4) : Color.focusBlue,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isAddTaskTitleEmpty)
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.bottom, AppStyle.Spacing.tiny)
            }

            if addTaskOptionsExpanded && !addTaskScheduleExpanded {
                HStack(spacing: AppStyle.Spacing.compact) {
                    Menu {
                        Button {
                            addTaskCategoryId = nil
                        } label: {
                            if addTaskCategoryId == nil {
                                Label("None", systemImage: "checkmark")
                            } else {
                                Text("None")
                            }
                        }
                        ForEach(taskListVM.categories) { category in
                            Button {
                                addTaskCategoryId = category.id
                            } label: {
                                if addTaskCategoryId == category.id {
                                    Label(category.name, systemImage: "checkmark")
                                } else {
                                    Text(category.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: AppStyle.Spacing.tiny) {
                            Image(systemName: "folder")
                                .font(.inter(.caption))
                            Text(LocalizedStringKey(categoryPillLabel))
                                .font(.inter(.caption))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .background(Color.white, in: Capsule())
                    }

                    Button {
                        if !addTaskScheduleExpanded {
                            addTaskDatesSnapshot = addTaskDates
                        }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            addTaskScheduleExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: AppStyle.Spacing.tiny) {
                            Image(systemName: "arrow.right.circle")
                                .font(.inter(.caption))
                            Text("Schedule")
                                .font(.inter(.caption))
                        }
                        .foregroundColor(!addTaskDates.isEmpty ? .white : .black)
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .background(!addTaskDates.isEmpty ? Color.appRed : Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(Priority.allCases, id: \.self) { priority in
                            Button {
                                addTaskPriority = priority
                            } label: {
                                if addTaskPriority == priority {
                                    Label(priority.displayName, systemImage: "checkmark")
                                } else {
                                    Text(priority.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: AppStyle.Spacing.tiny) {
                            Circle()
                                .fill(addTaskPriority.dotColor)
                                .frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)
                            Text(addTaskPriority.displayName)
                                .font(.inter(.caption))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .background(Color.white, in: Capsule())
                    }

                    Spacer()
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.small)
            }

            Spacer().frame(height: AppStyle.Spacing.page)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
    }

    // MARK: - Add Task Helpers

    func saveTask() {
        let title = addTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let subtasksToCreate = addTaskSubtasks
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let categoryId = addTaskCategoryId
        let priority = addTaskPriority
        let scheduleEnabled = !addTaskDates.isEmpty
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
        addTaskScheduleExpanded = false
        addTaskPriority = .low
        hasGeneratedBreakdown = false

        _Concurrency.Task { @MainActor in
            await taskListVM.createTaskWithSchedules(
                title: title,
                categoryId: categoryId,
                priority: priority,
                subtaskTitles: subtasksToCreate,
                scheduleAfterCreate: scheduleEnabled,
                selectedTimeframe: timeframe,
                selectedSection: section,
                selectedDates: dates,
                hasScheduledTime: false,
                scheduledTime: nil
            )

            if scheduleEnabled && !dates.isEmpty {
                await focusViewModel.fetchSchedules()
            }
        }
    }

    func addNewSubtask() {
        addBarTitleFocused = true
        let newEntry = DraftSubtaskEntry()
        withAnimation(.easeInOut(duration: 0.15)) {
            addTaskSubtasks.append(newEntry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedSubtaskId = newEntry.id
        }
    }

    func generateBreakdown() {
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

    func dismissAddBar() {
        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskCategoryId = nil
        addTaskPriority = .low
        addTaskOptionsExpanded = false
        addTaskScheduleExpanded = false
        addTaskDates = []
        hasGeneratedBreakdown = false
        focusedSubtaskId = nil
        addBarTitleFocused = false
        showingAddBar = false
    }
}

// MARK: - Backlog Filter Pill

private struct BacklogFilterPill: View {
    let title: String
    @Binding var isSelected: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSelected.toggle()
            }
        } label: {
            Text(title)
                .font(.inter(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, AppStyle.Spacing.comfortable)
                .padding(.vertical, 7)
                .background(isSelected ? Color.focusBlue : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Backlog Project Row

private struct BacklogProjectRow: View {
    let project: FocusTask
    var onTap: () -> Void
    var onEdit: () -> Void
    var onSchedule: () -> Void
    var onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            Image(systemName: "folder")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: AppStyle.Layout.pillButton)

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
            Image(systemName: "list.bullet")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: AppStyle.Layout.pillButton)

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
