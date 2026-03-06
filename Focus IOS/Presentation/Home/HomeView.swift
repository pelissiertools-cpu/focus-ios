//
//  HomeView.swift
//  Focus IOS
//

import SwiftUI
import Auth

private enum HomeAddBarTitleFocus: Hashable {
    case task, list, project
}

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @StateObject private var projectsViewModel: ProjectsViewModel
    @StateObject private var listsViewModel: ListsViewModel
    @State private var showSettings = false
    @State private var showSearch = false

    // Task list VM for add bar task creation
    @StateObject private var taskListVM: TaskListViewModel

    private let authService: AuthService

    // Unified add bar state
    @State private var showingAddBar = false
    @State private var addBarMode: TaskType = .task

    // Compact add-task bar state
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

    // Compact add-list bar state
    @State private var addListTitle = ""
    @State private var addListItems: [DraftSubtaskEntry] = []
    @State private var addListCategoryId: UUID? = nil
    @State private var addListScheduleExpanded = false
    @State private var addListTimeframe: Timeframe = .daily
    @State private var addListSection: Section = .todo
    @State private var addListDates: Set<Date> = []
    @State private var addListDatesSnapshot: Set<Date> = []
    @State private var addListOptionsExpanded = false
    @State private var addListPriority: Priority = .low
    @FocusState private var focusedListItemId: UUID?

    // Compact add-project bar state
    @State private var addProjectTitle = ""
    @State private var addProjectDraftTasks: [DraftTask] = []
    @State private var addProjectCategoryId: UUID? = nil
    @State private var addProjectScheduleExpanded = false
    @State private var addProjectTimeframe: Timeframe = .daily
    @State private var addProjectSection: Section = .todo
    @State private var addProjectDates: Set<Date> = []
    @State private var addProjectDatesSnapshot: Set<Date> = []
    @State private var addProjectOptionsExpanded = false
    @State private var addProjectPriority: Priority = .low
    @FocusState private var focusedProjectTaskId: UUID?

    // Unified title focus
    @FocusState private var addBarTitleFocus: HomeAddBarTitleFocus?

    // Pre-computed title emptiness checks
    private var isAddTaskTitleEmpty: Bool {
        addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isAddListTitleEmpty: Bool {
        addListTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isAddProjectTitleEmpty: Bool {
        addProjectTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var braindumpCount: Int {
        taskListVM.tasks.filter {
            !$0.isCompleted && $0.projectId == nil && $0.parentTaskId == nil
            && !taskListVM.scheduledTaskIds.contains($0.id)
        }.count
    }

    init(viewModel: HomeViewModel, authService: AuthService) {
        self.viewModel = viewModel
        self.authService = authService
        _projectsViewModel = StateObject(wrappedValue: ProjectsViewModel(authService: authService))
        _listsViewModel = StateObject(wrappedValue: ListsViewModel(authService: authService))
        _taskListVM = StateObject(wrappedValue: TaskListViewModel(authService: authService))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // MARK: - Top Bar
                        HStack {
                            Button(action: { showSettings = true }) {
                                Image(systemName: "person")
                                    .font(.inter(.body, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(width: 36, height: 36)
                                    .glassEffect(.regular.tint(.glassTint).interactive(), in: .circle)
                            }

                            Spacer()

                            Button(action: { showSearch = true }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.inter(.body, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(width: 36, height: 36)
                                    .glassEffect(.regular.tint(.glassTint).interactive(), in: .circle)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 24)

                        // MARK: - Menu Items (Today, Scheduled)
                        ForEach([HomeMenuItem.today, .assign], id: \.self) { item in
                            homeMenuButton(item)
                        }

                        // MARK: - Divider
                        Rectangle()
                            .fill(Color.appRed.opacity(0.4))
                            .frame(height: 1)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        // MARK: - Menu Items (Braindump, Backlog, Archive)
                        ForEach([HomeMenuItem.braindump, .backlog, .archive], id: \.self) { item in
                            homeMenuButton(item)
                        }

                        // MARK: - Divider before Projects/Lists
                        Rectangle()
                            .fill(Color.appRed.opacity(0.4))
                            .frame(height: 1)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        // MARK: - Projects & Quick Lists Menu Items
                        ForEach([HomeMenuItem.projects, .quickLists], id: \.self) { item in
                            homeMenuButton(item)
                        }
                    }
                    .padding(.bottom, 120)
                }

                // MARK: - FAB Button
                if !showingAddBar {
                    fabButton {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            addBarMode = .task
                            showingAddBar = true
                        }
                    }
                    .transition(.opacity)
                }

                // MARK: - Add Bar Overlay
                if showingAddBar {
                    // Scrim
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(50)

                    // Tap-to-dismiss + add bar
                    VStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    dismissActiveAddBar()
                                }
                            }

                        VStack(spacing: 0) {
                            addBarModeSelector
                                .padding(.vertical, 12)

                            activeAddBar
                                .padding(.bottom, 8)
                        }
                        .contentShape(Rectangle())
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
                }
            }
            .navigationDestination(item: $viewModel.selectedMenuItem) { menuItem in
                if menuItem == .archive {
                    ArchiveView()
                } else if menuItem == .braindump {
                    BraindumpView(authService: authService)
                } else if menuItem == .assign {
                    ScheduledView(authService: authService)
                } else if menuItem == .backlog {
                    BacklogView(authService: authService)
                } else if menuItem == .today {
                    TodayView(authService: authService)
                } else if menuItem == .projects {
                    ProjectsListPage(viewModel: viewModel, authService: authService)
                } else if menuItem == .quickLists {
                    QuickListsPage(viewModel: viewModel, authService: authService)
                } else {
                    HomePlaceholderPage(title: menuItem.rawValue)
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(isPresented: $showSearch) {
                BacklogView(authService: authService, startWithSearch: true)
            }
            .navigationBarHidden(true)
            .task {
                // Fetch projects/lists for count badges
                if viewModel.projects.isEmpty {
                    await viewModel.fetchProjects(showLoading: true)
                }
                if viewModel.lists.isEmpty {
                    await viewModel.fetchLists()
                }
                await taskListVM.fetchScheduledTaskIds()
                await taskListVM.fetchTasks()
                // Pre-load categories for add bar
                await projectsViewModel.fetchProjects()
                await listsViewModel.fetchLists()
            }
            // Add bar: auto-focus on open
            .onChange(of: showingAddBar) { _, isShowing in
                if isShowing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        switch addBarMode {
                        case .task: addBarTitleFocus = .task
                        case .list: addBarTitleFocus = .list
                        case .project: addBarTitleFocus = .project
                        }
                    }
                }
            }
            // Add bar: focus transfer on mode switch
            .onChange(of: addBarMode) { _, newMode in
                guard showingAddBar else { return }
                focusedSubtaskId = nil
                focusedListItemId = nil
                focusedProjectTaskId = nil
                switch newMode {
                case .task: addBarTitleFocus = .task
                case .list: addBarTitleFocus = .list
                case .project: addBarTitleFocus = .project
                }
            }
            // Task schedule expansion focus management
            .onChange(of: addTaskScheduleExpanded) { _, isExpanded in
                if isExpanded {
                    addBarTitleFocus = nil
                    focusedSubtaskId = nil
                }
            }
            .onChange(of: addBarTitleFocus) { _, focus in
                if focus == .task && addTaskScheduleExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addTaskScheduleExpanded = false
                    }
                }
            }
            .onChange(of: focusedSubtaskId) { _, subtaskId in
                if subtaskId != nil && addTaskScheduleExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addTaskScheduleExpanded = false
                    }
                }
            }
            // List schedule expansion focus management
            .onChange(of: addListScheduleExpanded) { _, isExpanded in
                if isExpanded {
                    addBarTitleFocus = nil
                    focusedListItemId = nil
                }
            }
            .onChange(of: focusedListItemId) { _, itemId in
                if itemId != nil && addListScheduleExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addListScheduleExpanded = false
                    }
                }
            }
            // Project schedule expansion focus management
            .onChange(of: addProjectScheduleExpanded) { _, isExpanded in
                if isExpanded {
                    addBarTitleFocus = nil
                    focusedProjectTaskId = nil
                }
            }
            .onChange(of: focusedProjectTaskId) { _, taskId in
                if taskId != nil && addProjectScheduleExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addProjectScheduleExpanded = false
                    }
                }
            }
        }
    }

    // MARK: - Home Menu Button

    private func homeMenuButton(_ item: HomeMenuItem) -> some View {
        Button {
            viewModel.selectedMenuItem = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.iconName)
                    .font(.inter(.body, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 24)

                Text(item.rawValue)
                    .font(.inter(.body))
                    .foregroundColor(.primary)

                if item == .braindump {
                    let count = braindumpCount
                    if count > 0 {
                        Text("\(count)")
                            .font(.inter(.footnote, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else if item == .projects {
                    let count = viewModel.projects.filter({ !$0.isSection }).count
                    if count > 0 {
                        Text("\(count)")
                            .font(.inter(.footnote, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else if item == .quickLists {
                    let count = viewModel.lists.filter({ !$0.isSection }).count
                    if count > 0 {
                        Text("\(count)")
                            .font(.inter(.footnote, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - FAB Button

    private func fabButton(action: @escaping () -> Void) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    action()
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
    }

    // MARK: - Add Bar Mode Selector

    private var addBarModeSelector: some View {
        HStack(spacing: 12) {
            addBarModeCircle(mode: .task, icon: "checklist")
            addBarModeCircle(mode: .list, icon: "list.bullet")
            addBarModeCircle(mode: .project, icon: "folder")
            Spacer()
        }
        .padding(.horizontal)
    }

    private func addBarModeCircle(mode: TaskType, icon: String) -> some View {
        let isActive = addBarMode == mode
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                addBarMode = mode
            }
        } label: {
            Image(systemName: isActive && mode == .project ? "folder.fill" : icon)
                .font(.inter(.body, weight: .medium))
                .foregroundColor(isActive ? .white : .primary)
                .frame(width: 36, height: 36)
                .glassEffect(
                    isActive
                        ? .regular.tint(.black).interactive()
                        : .regular.interactive(),
                    in: .circle
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Active Add Bar

    @ViewBuilder
    private var activeAddBar: some View {
        switch addBarMode {
        case .task: addTaskBar
        case .list: addListBar
        case .project: addProjectBar
        }
    }

    // MARK: - Compact Add Task Bar

    private var addTaskBar: some View {
        VStack(spacing: 0) {
            // Task title row
            TextField("Create a new task", text: $addTaskTitle)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .task)
                .submitLabel(.return)
                .onSubmit {
                    saveTask()
                }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            // Subtasks
            DraftSubtaskListEditor(
                subtasks: $addTaskSubtasks,
                focusedSubtaskId: $focusedSubtaskId,
                onAddNew: { addNewSubtask() }
            )

            // Schedule expansion (calendar section)
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

                // Schedule mode action row
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
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
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

            // Sub-task row: [Sub-task] ... [AI Breakdown] [Checkmark]
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

                // More options pill
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

                // AI Breakdown
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

                // Submit button (checkmark)
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

            // Bottom row: [Category] [Schedule] [Priority]
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
                        Text(LocalizedStringKey(taskCategoryPillLabel))
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

    // MARK: - Compact Add List Bar

    private var addListBar: some View {
        VStack(spacing: 0) {
            TextField("Create a new list", text: $addListTitle)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .list)
                .submitLabel(.return)
                .onSubmit {
                    saveList()
                }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            DraftSubtaskListEditor(
                subtasks: $addListItems,
                focusedSubtaskId: $focusedListItemId,
                onAddNew: { addNewListItem() },
                placeholder: "Item"
            )

            // Schedule expansion
            if addListScheduleExpanded {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Section", selection: $addListSection) {
                        Text("Focus").tag(Section.focus)
                        Text("To-Do").tag(Section.todo)
                    }
                    .pickerStyle(.segmented)

                    UnifiedCalendarPicker(
                        selectedDates: $addListDates,
                        selectedTimeframe: $addListTimeframe
                    )
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 14)

                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            addListDates.removeAll()
                            addListScheduleExpanded = false
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

                    let hasDateChanges = addListDates != addListDatesSnapshot
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            addListScheduleExpanded = false
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

            // Row 1: [Item] [...] Spacer [Checkmark]
            if !addListScheduleExpanded {
            HStack(spacing: 8) {
                Button {
                    addNewListItem()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.inter(.caption))
                        Text("Item")
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
                        addListOptionsExpanded.toggle()
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
                    saveList()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(isAddListTitleEmpty ? .secondary : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            isAddListTitleEmpty ? Color(.systemGray4) : Color.completedPurple,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAddListTitleEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
            }

            // Row 2: [Category] [Schedule] [Priority]
            if addListOptionsExpanded && !addListScheduleExpanded {
            HStack(spacing: 8) {
                Menu {
                    Button {
                        addListCategoryId = nil
                    } label: {
                        if addListCategoryId == nil {
                            Label("None", systemImage: "checkmark")
                        } else {
                            Text("None")
                        }
                    }
                    ForEach(listsViewModel.categories) { category in
                        Button {
                            addListCategoryId = category.id
                        } label: {
                            if addListCategoryId == category.id {
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
                        Text(LocalizedStringKey(listCategoryPillLabel))
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white, in: Capsule())
                }

                Button {
                    addListDatesSnapshot = addListDates
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addListScheduleExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.inter(.caption))
                        Text("Schedule")
                            .font(.inter(.caption))
                    }
                    .foregroundColor(!addListDates.isEmpty ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(!addListDates.isEmpty ? Color.appRed : Color.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Button {
                            addListPriority = priority
                        } label: {
                            if addListPriority == priority {
                                Label(priority.displayName, systemImage: "checkmark")
                            } else {
                                Text(priority.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(addListPriority.dotColor)
                            .frame(width: 8, height: 8)
                        Text(addListPriority.displayName)
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

    // MARK: - Compact Add Project Bar

    private var addProjectBar: some View {
        VStack(spacing: 0) {
            TextField("Create a new project", text: $addProjectTitle)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .project)
                .submitLabel(.return)
                .onSubmit {
                    saveProject()
                }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            // Tasks + subtasks area
            if !addProjectDraftTasks.isEmpty {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(addProjectDraftTasks) { task in
                        projectTaskDraftRow(task: task)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }

            // Schedule expansion
            if addProjectScheduleExpanded {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Section", selection: $addProjectSection) {
                        Text("Focus").tag(Section.focus)
                        Text("To-Do").tag(Section.todo)
                    }
                    .pickerStyle(.segmented)

                    UnifiedCalendarPicker(
                        selectedDates: $addProjectDates,
                        selectedTimeframe: $addProjectTimeframe
                    )
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 14)

                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            addProjectDates.removeAll()
                            addProjectScheduleExpanded = false
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

                    let hasDateChanges = addProjectDates != addProjectDatesSnapshot
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            addProjectScheduleExpanded = false
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

            // Row 1: [Task] [...] Spacer [Checkmark]
            if !addProjectScheduleExpanded {
            HStack(spacing: 8) {
                Button {
                    addNewProjectTask()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.inter(.caption))
                        Text("Task")
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
                        addProjectOptionsExpanded.toggle()
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
                    saveProject()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(isAddProjectTitleEmpty ? .secondary : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            isAddProjectTitleEmpty ? Color(.systemGray4) : Color.completedPurple,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAddProjectTitleEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
            }

            // Row 2: [Category] [Schedule] [Priority]
            if addProjectOptionsExpanded && !addProjectScheduleExpanded {
            HStack(spacing: 8) {
                Menu {
                    Button {
                        addProjectCategoryId = nil
                    } label: {
                        if addProjectCategoryId == nil {
                            Label("None", systemImage: "checkmark")
                        } else {
                            Text("None")
                        }
                    }
                    ForEach(projectsViewModel.categories) { category in
                        Button {
                            addProjectCategoryId = category.id
                        } label: {
                            if addProjectCategoryId == category.id {
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
                        Text(LocalizedStringKey(projectCategoryPillLabel))
                            .font(.inter(.caption))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white, in: Capsule())
                }

                Button {
                    addProjectDatesSnapshot = addProjectDates
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addProjectScheduleExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.inter(.caption))
                        Text("Schedule")
                            .font(.inter(.caption))
                    }
                    .foregroundColor(!addProjectDates.isEmpty ? .white : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(!addProjectDates.isEmpty ? Color.appRed : Color.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Button {
                            addProjectPriority = priority
                        } label: {
                            if addProjectPriority == priority {
                                Label(priority.displayName, systemImage: "checkmark")
                            } else {
                                Text(priority.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(addProjectPriority.dotColor)
                            .frame(width: 8, height: 8)
                        Text(addProjectPriority.displayName)
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

    // MARK: - Project Task Draft Row

    @ViewBuilder
    private func projectTaskDraftRow(task: DraftTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.inter(.caption2))
                .foregroundColor(.secondary.opacity(0.5))

            TextField("Task", text: projectTaskBinding(for: task.id), axis: .vertical)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($focusedProjectTaskId, equals: task.id)
                .lineLimit(1...3)
                .onChange(of: projectTaskBinding(for: task.id).wrappedValue) { _, newValue in
                    if newValue.contains("\n") {
                        if let idx = addProjectDraftTasks.firstIndex(where: { $0.id == task.id }) {
                            addProjectDraftTasks[idx].title = newValue.replacingOccurrences(of: "\n", with: "")
                        }
                        addNewProjectSubtask(toTask: task.id)
                    }
                }

            Button {
                removeProjectTask(id: task.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }

        // Subtask rows
        ForEach(task.subtasks) { subtask in
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .font(.inter(.caption2))
                    .foregroundColor(.secondary.opacity(0.5))

                TextField("Sub-task", text: projectSubtaskBinding(forSubtask: subtask.id, inTask: task.id), axis: .vertical)
                    .font(.inter(.body))
                    .textFieldStyle(.plain)
                    .focused($focusedProjectTaskId, equals: subtask.id)
                    .lineLimit(1...3)
                    .onChange(of: projectSubtaskBinding(forSubtask: subtask.id, inTask: task.id).wrappedValue) { _, newValue in
                        if newValue.contains("\n") {
                            if let tIdx = addProjectDraftTasks.firstIndex(where: { $0.id == task.id }),
                               let sIdx = addProjectDraftTasks[tIdx].subtasks.firstIndex(where: { $0.id == subtask.id }) {
                                addProjectDraftTasks[tIdx].subtasks[sIdx].title = newValue.replacingOccurrences(of: "\n", with: "")
                            }
                            addNewProjectSubtask(toTask: task.id)
                        }
                    }

                Button {
                    removeProjectSubtask(id: subtask.id, fromTask: task.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.inter(.caption))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 28)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
        }
        .padding(.top, 12)

        // "+ Sub-task" button
        Button {
            addNewProjectSubtask(toTask: task.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.inter(.subheadline))
                Text("Sub-task")
                    .font(.inter(.subheadline))
            }
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .padding(.leading, 28)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Add Task Helpers

    private var taskCategoryPillLabel: String {
        if let categoryId = addTaskCategoryId,
           let category = taskListVM.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
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
            } catch {
                // Silently fail
            }
            isGeneratingBreakdown = false
        }
    }

    private func saveTask() {
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

        addBarTitleFocus = .task
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

    private func addNewSubtask() {
        addBarTitleFocus = .task
        let newEntry = DraftSubtaskEntry()
        withAnimation(.easeInOut(duration: 0.15)) {
            addTaskSubtasks.append(newEntry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedSubtaskId = newEntry.id
        }
    }

    private func dismissAddTask() {
        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskCategoryId = nil
        addTaskPriority = .low
        addTaskOptionsExpanded = false
        addTaskScheduleExpanded = false
        addTaskDates = []
        hasGeneratedBreakdown = false
        addBarTitleFocus = nil
        focusedSubtaskId = nil
    }

    // MARK: - Add List Helpers

    private var listCategoryPillLabel: String {
        if let categoryId = addListCategoryId,
           let category = listsViewModel.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private func saveList() {
        let title = addListTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let itemTitles = addListItems
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let categoryId = addListCategoryId
        let priority = addListPriority
        let scheduleEnabled = !addListDates.isEmpty
        let timeframe = addListTimeframe
        let section = addListSection
        let dates = addListDates

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        addBarTitleFocus = .list
        focusedListItemId = nil

        addListTitle = ""
        addListItems = []
        addListDates = []
        addListScheduleExpanded = false
        addListOptionsExpanded = false
        addListPriority = .low

        _Concurrency.Task { @MainActor in
            await listsViewModel.createList(title: title, categoryId: categoryId, priority: priority)

            if let createdList = listsViewModel.lists.first {
                for itemTitle in itemTitles {
                    await listsViewModel.createItem(title: itemTitle, listId: createdList.id)
                }
                if !itemTitles.isEmpty {
                    listsViewModel.expandedLists.insert(createdList.id)
                }

                if scheduleEnabled && !dates.isEmpty {
                    for date in dates {
                        let schedule = Schedule(
                            userId: createdList.userId,
                            taskId: createdList.id,
                            timeframe: timeframe,
                            section: section,
                            scheduleDate: date,
                            sortOrder: 0,
                            scheduledTime: nil,
                            durationMinutes: nil
                        )
                        _ = try? await listsViewModel.scheduleRepository.createSchedule(schedule)
                    }
                    await focusViewModel.fetchSchedules()
                    await listsViewModel.fetchScheduledTaskIds()
                }
            }

            // Refresh Home's list display
            await viewModel.fetchLists()
        }
    }

    private func addNewListItem() {
        addBarTitleFocus = .list
        let newEntry = DraftSubtaskEntry()
        withAnimation(.easeInOut(duration: 0.15)) {
            addListItems.append(newEntry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedListItemId = newEntry.id
        }
    }

    private func dismissAddList() {
        addListTitle = ""
        addListItems = []
        addListCategoryId = nil
        addListScheduleExpanded = false
        addListOptionsExpanded = false
        addListPriority = .low
        addListDates = []
        addBarTitleFocus = nil
        focusedListItemId = nil
    }

    // MARK: - Add Project Helpers

    private var projectCategoryPillLabel: String {
        if let categoryId = addProjectCategoryId,
           let category = projectsViewModel.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private func saveProject() {
        let title = addProjectTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let draftTasks = addProjectDraftTasks.filter {
            !$0.title.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let categoryId = addProjectCategoryId
        let priority = addProjectPriority
        let scheduleEnabled = !addProjectDates.isEmpty
        let timeframe = addProjectTimeframe
        let section = addProjectSection
        let dates = addProjectDates

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        addBarTitleFocus = .project
        focusedProjectTaskId = nil

        addProjectTitle = ""
        addProjectDraftTasks = []
        addProjectDates = []
        addProjectScheduleExpanded = false
        addProjectOptionsExpanded = false
        addProjectPriority = .low

        _Concurrency.Task { @MainActor in
            guard let projectId = await projectsViewModel.saveNewProject(
                title: title,
                categoryId: categoryId,
                priority: priority,
                draftTasks: draftTasks
            ) else { return }

            if scheduleEnabled && !dates.isEmpty {
                guard let userId = projectsViewModel.authService.currentUser?.id else { return }
                for date in dates {
                    let schedule = Schedule(
                        userId: userId,
                        taskId: projectId,
                        timeframe: timeframe,
                        section: section,
                        scheduleDate: date,
                        sortOrder: 0,
                        scheduledTime: nil,
                        durationMinutes: nil
                    )
                    _ = try? await projectsViewModel.scheduleRepository.createSchedule(schedule)
                }
                await focusViewModel.fetchSchedules()
                await projectsViewModel.fetchScheduledTaskIds()
            }

            // Refresh Home's project display
            await viewModel.fetchProjects()
        }
    }

    private func projectTaskBinding(for taskId: UUID) -> Binding<String> {
        Binding(
            get: { addProjectDraftTasks.first(where: { $0.id == taskId })?.title ?? "" },
            set: { newValue in
                if let idx = addProjectDraftTasks.firstIndex(where: { $0.id == taskId }) {
                    addProjectDraftTasks[idx].title = newValue
                }
            }
        )
    }

    private func projectSubtaskBinding(forSubtask subtaskId: UUID, inTask taskId: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let tIdx = addProjectDraftTasks.firstIndex(where: { $0.id == taskId }),
                      let s = addProjectDraftTasks[tIdx].subtasks.first(where: { $0.id == subtaskId })
                else { return "" }
                return s.title
            },
            set: { newValue in
                if let tIdx = addProjectDraftTasks.firstIndex(where: { $0.id == taskId }),
                   let sIdx = addProjectDraftTasks[tIdx].subtasks.firstIndex(where: { $0.id == subtaskId }) {
                    addProjectDraftTasks[tIdx].subtasks[sIdx].title = newValue
                }
            }
        )
    }

    private func addNewProjectTask() {
        let newTask = DraftTask()
        withAnimation(.easeInOut(duration: 0.15)) {
            addProjectDraftTasks.append(newTask)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedProjectTaskId = newTask.id
        }
    }

    private func addNewProjectSubtask(toTask taskId: UUID) {
        guard let tIdx = addProjectDraftTasks.firstIndex(where: { $0.id == taskId }) else { return }
        let newSubtask = DraftSubtask(title: "")
        withAnimation(.easeInOut(duration: 0.15)) {
            addProjectDraftTasks[tIdx].subtasks.append(newSubtask)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedProjectTaskId = newSubtask.id
        }
    }

    private func removeProjectTask(id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            addProjectDraftTasks.removeAll { $0.id == id }
        }
    }

    private func removeProjectSubtask(id: UUID, fromTask taskId: UUID) {
        guard let tIdx = addProjectDraftTasks.firstIndex(where: { $0.id == taskId }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            addProjectDraftTasks[tIdx].subtasks.removeAll { $0.id == id }
        }
    }

    private func dismissAddProject() {
        addProjectTitle = ""
        addProjectDraftTasks = []
        addProjectCategoryId = nil
        addProjectScheduleExpanded = false
        addProjectOptionsExpanded = false
        addProjectPriority = .low
        addProjectDates = []
        addBarTitleFocus = nil
        focusedProjectTaskId = nil
    }

    // MARK: - Shared Dismiss

    private func dismissActiveAddBar() {
        guard showingAddBar else { return }
        dismissAddTask()
        dismissAddList()
        dismissAddProject()
        showingAddBar = false
    }
}

// MARK: - Home Project Row

struct HomeProjectRow: View {
    let project: FocusTask
    let onTap: () -> Void
    let onEdit: () -> Void
    let onSchedule: () -> Void
    let onRequestDelete: () -> Void

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
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            ContextMenuItems.editButton { onEdit() }
            ContextMenuItems.scheduleButton { onSchedule() }
            Divider()
            ContextMenuItems.deleteButton { onRequestDelete() }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onRequestDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Home List Row

struct HomeListRow: View {
    let list: FocusTask
    let onTap: () -> Void
    let onEdit: () -> Void
    let onSchedule: () -> Void
    let onRequestDelete: () -> Void

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
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .contextMenu {
            ContextMenuItems.editButton { onEdit() }
            ContextMenuItems.scheduleButton { onSchedule() }
            Divider()
            ContextMenuItems.deleteButton { onRequestDelete() }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onRequestDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Placeholder Page

private struct HomePlaceholderPage: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text(title)
                .font(.inter(.title2, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
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
    }
}
