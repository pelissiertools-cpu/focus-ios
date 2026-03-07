//
//  BacklogView.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct BacklogView: View {
    var startWithSearch: Bool = false

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

    init(authService: AuthService, startWithSearch: Bool = false) {
        self.startWithSearch = startWithSearch
        _isSearchActive = State(initialValue: startWithSearch)
        _taskListVM = StateObject(wrappedValue: TaskListViewModel(authService: authService))
        _projectsVM = StateObject(wrappedValue: ProjectsViewModel(authService: authService))
        _listsVM = StateObject(wrappedValue: ListsViewModel(authService: authService))
    }

    // Section collapse states
    @State private var isTasksSectionCollapsed = false
    @State private var isProjectsSectionCollapsed = false
    @State private var isListsSectionCollapsed = false
    @State private var isSomedaySectionCollapsed = true

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

    private var somedayCategoryId: UUID? {
        taskListVM.somedayCategory?.id
    }

    private func isSomedayItem(_ task: FocusTask) -> Bool {
        guard let somedayId = somedayCategoryId else { return false }
        return task.categoryId == somedayId
    }

    /// All uncompleted standalone tasks (not inside a project), excluding Someday
    private var standaloneTasks: [FocusTask] {
        taskListVM.uncompletedTasks.filter { $0.projectId == nil && !isSomedayItem($0) }
    }

    /// Someday tasks
    private var somedayTasks: [FocusTask] {
        taskListVM.uncompletedTasks.filter { $0.projectId == nil && isSomedayItem($0) }
    }

    /// Flattened task display items excluding project-contained tasks and Someday
    private var standaloneTaskDisplayItems: [FlatDisplayItem] {
        let projectTaskIds = Set(taskListVM.uncompletedTasks.filter { $0.projectId != nil }.map { $0.id })
        return taskListVM.flattenedDisplayItems.filter { item in
            switch item {
            case .task(let task): return task.projectId == nil && !isSomedayItem(task)
            case .addSubtaskRow(let parentId): return !projectTaskIds.contains(parentId)
            default: return true
            }
        }
    }

    private var allProjects: [FocusTask] {
        projectsVM.projects.filter { !$0.isCompleted && !$0.isCleared && !isSomedayItem($0) }
    }

    private var allLists: [FocusTask] {
        listsVM.lists.filter { !$0.isCompleted && !$0.isCleared && !isSomedayItem($0) }
    }

    private var somedayProjects: [FocusTask] {
        projectsVM.projects.filter { !$0.isCompleted && !$0.isCleared && isSomedayItem($0) }
    }

    private var somedayLists: [FocusTask] {
        listsVM.lists.filter { !$0.isCompleted && !$0.isCleared && isSomedayItem($0) }
    }

    private var somedayItemCount: Int {
        somedayTasks.count + somedayProjects.count + somedayLists.count
    }

    private var isEmpty: Bool {
        standaloneTasks.isEmpty && allProjects.isEmpty && allLists.isEmpty && somedayItemCount == 0
    }

    private var isSearching: Bool {
        isSearchActive && !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var filteredTasks: [FocusTask] {
        guard isSearching else { return standaloneTasks }
        let query = searchText.lowercased()
        return standaloneTasks.filter { $0.title.lowercased().contains(query) }
    }

    private var filteredTaskDisplayItems: [FlatDisplayItem] {
        guard isSearching else { return standaloneTaskDisplayItems }
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
        guard isSearching else { return allProjects }
        let query = searchText.lowercased()
        return allProjects.filter { $0.title.lowercased().contains(query) }
    }

    private var filteredLists: [FocusTask] {
        guard isSearching else { return allLists }
        let query = searchText.lowercased()
        return allLists.filter { $0.title.lowercased().contains(query) }
    }

    private var filteredSomedayTasks: [FocusTask] {
        guard isSearching else { return somedayTasks }
        let query = searchText.lowercased()
        return somedayTasks.filter { $0.title.lowercased().contains(query) }
    }

    private var filteredSomedayProjects: [FocusTask] {
        guard isSearching else { return somedayProjects }
        let query = searchText.lowercased()
        return somedayProjects.filter { $0.title.lowercased().contains(query) }
    }

    private var filteredSomedayLists: [FocusTask] {
        guard isSearching else { return somedayLists }
        let query = searchText.lowercased()
        return somedayLists.filter { $0.title.lowercased().contains(query) }
    }

    private var filteredSomedayCount: Int {
        filteredSomedayTasks.count + filteredSomedayProjects.count + filteredSomedayLists.count
    }

    private var searchIsEmpty: Bool {
        isSearching && filteredTasks.isEmpty && filteredProjects.isEmpty && filteredLists.isEmpty && filteredSomedayCount == 0
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "tray")
                        .font(.inter(size: 22, weight: .regular))
                        .foregroundColor(.primary)

                    Text("Backlog")
                        .font(.inter(size: 28, weight: .regular))
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
                            .frame(width: 30, height: 30)
                            .background(Color.pillBackground, in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                if isSearchActive {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)

                        TextField("Search tasks, projects, lists...", text: $searchText)
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.pillBackground, in: Capsule())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }

                if isLoading && isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchIsEmpty {
                    VStack(spacing: 4) {
                        Text("No results")
                            .font(.inter(.headline))
                            .bold()
                        Text("No items match \"\(searchText)\"")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
                } else if isEmpty {
                    VStack(spacing: 4) {
                        Text("No items yet")
                            .font(.inter(.headline))
                            .bold()
                        Text("All your tasks, projects, and lists will appear here")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
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
                        .padding(.bottom, 8)
                        .contentShape(Rectangle())
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
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
                focusViewModel: focusViewModel,
                onSomeday: {
                    _Concurrency.Task { await taskListVM.moveTaskToSomeday(task) }
                },
                isSomedayTask: task.categoryId == taskListVM.somedayCategory?.id
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
                focusViewModel: focusViewModel,
                onSomeday: {
                    _Concurrency.Task { await listsVM.moveTaskToSomeday(item) }
                },
                isSomedayTask: item.categoryId == listsVM.somedayCategory?.id
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
                focusViewModel: focusViewModel,
                onSomeday: {
                    _Concurrency.Task { await projectsVM.moveTaskToSomeday(task) }
                },
                isSomedayTask: task.categoryId == projectsVM.somedayCategory?.id
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
                            .contentShape(Circle())
                    }
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
                            .frame(width: 30, height: 30)
                            .background(Color.pillBackground, in: Circle())
                    }
                }
            }
        }
        .task {
            // No schedule filter — show ALL tasks
            isLoading = true
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
            if !filteredTasks.isEmpty || !isSearching {
                tasksSectionHeader
            }

            if !isTasksSectionCollapsed && (!filteredTasks.isEmpty || !isSearching) {
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
                            onToggleCompletion: { t in
                                taskListVM.requestToggleCompletion(t)
                            }
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
            }

            // MARK: Projects Section
            if !filteredProjects.isEmpty {
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
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }

            // MARK: Quick Lists Section
            if !filteredLists.isEmpty {
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
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }

            // MARK: Someday Section (collapsed by default, expanded when searching)
            if filteredSomedayCount > 0 {
                somedaySectionHeader

                if !isSomedaySectionCollapsed || isSearching {
                    ForEach(filteredSomedayTasks) { task in
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
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    ForEach(filteredSomedayProjects) { project in
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
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    ForEach(filteredSomedayLists) { list in
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
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }

            // Bottom spacer
            Color.clear
                .frame(height: 100)
                .listRowInsets(EdgeInsets())
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

    // MARK: - Section Headers

    private var tasksSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isTasksSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.inter(.subheadline))
                    .foregroundColor(.appRed)
                Text("Tasks")
                    .font(.inter(.headline, weight: .bold))
                    .foregroundColor(.primary)
                Text("\(filteredTasks.count)")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.inter(size: 10, weight: .semiBold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isTasksSectionCollapsed ? 0 : 90))
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var projectsSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isProjectsSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                ProjectIconShape()
                    .frame(width: 16, height: 16)
                    .foregroundColor(.appRed)
                Text("Projects")
                    .font(.inter(.headline, weight: .bold))
                    .foregroundColor(.primary)
                Text("\(filteredProjects.count)")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.inter(size: 10, weight: .semiBold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isProjectsSectionCollapsed ? 0 : 90))
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

    private var listsSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isListsSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.inter(.subheadline))
                    .foregroundColor(.appRed)
                Text("Quick Lists")
                    .font(.inter(.headline, weight: .bold))
                    .foregroundColor(.primary)
                Text("\(filteredLists.count)")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.inter(size: 10, weight: .semiBold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isListsSectionCollapsed ? 0 : 90))
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

    private var somedaySectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSomedaySectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz")
                    .font(.inter(.subheadline))
                    .foregroundColor(.appRed)
                Text("Someday")
                    .font(.inter(.headline, weight: .bold))
                    .foregroundColor(.primary)
                Text("\(isSearching ? filteredSomedayCount : somedayItemCount)")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
                if !isSearching {
                    Image(systemName: "chevron.right")
                        .font(.inter(size: 10, weight: .semiBold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isSomedaySectionCollapsed ? 0 : 90))
                }
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
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            DraftSubtaskListEditor(
                subtasks: $addTaskSubtasks,
                focusedSubtaskId: $focusedSubtaskId,
                onAddNew: { addNewSubtask() }
            )

            if addTaskScheduleExpanded {
                Divider()
                    .padding(.horizontal, 14)

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
                            .frame(width: 36, height: 36)
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
                            .frame(width: 36, height: 36)
                            .background(
                                hasDateChanges ? Color.appRed : Color(.systemGray4),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }

            if !addTaskScheduleExpanded {
                HStack(spacing: 8) {
                    Button {
                        addNewSubtask()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.inter(.caption))
                            Text("Sub-task")
                                .font(.inter(.caption))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
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
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

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
                                    .foregroundColor(!isAddTaskTitleEmpty ? .blue : .primary)
                            }
                            Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Breakdown"))
                                .font(.inter(.caption, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
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
                            .frame(width: 36, height: 36)
                            .background(
                                isAddTaskTitleEmpty ? Color(.systemGray4) : Color.completedPurple,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isAddTaskTitleEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }

            if addTaskOptionsExpanded && !addTaskScheduleExpanded {
                HStack(spacing: 8) {
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
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.inter(.caption))
                            Text(LocalizedStringKey(categoryPillLabel))
                                .font(.inter(.caption))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
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
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle")
                                .font(.inter(.caption))
                            Text("Schedule")
                                .font(.inter(.caption))
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
                                if addTaskPriority == priority {
                                    Label(priority.displayName, systemImage: "checkmark")
                                } else {
                                    Text(priority.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(addTaskPriority.dotColor)
                                .frame(width: 8, height: 8)
                            Text(addTaskPriority.displayName)
                                .font(.inter(.caption))
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

            Spacer().frame(height: 20)
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

// MARK: - Backlog Project Row

private struct BacklogProjectRow: View {
    let project: FocusTask
    var onTap: () -> Void
    var onEdit: () -> Void
    var onSchedule: () -> Void
    var onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            ProjectIconShape()
                .frame(width: 24, height: 24)
                .foregroundColor(.secondary)

            Text(project.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.inter(size: 12, weight: .semiBold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
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
        HStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(list.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.inter(size: 12, weight: .semiBold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
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
