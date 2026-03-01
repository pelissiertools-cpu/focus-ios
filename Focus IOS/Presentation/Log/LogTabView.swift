//
//  LogTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI
import Auth

private enum AddBarTitleFocus: Hashable {
    case task, list, project
}

struct LogTabView: View {
    @Binding var mainTab: Int
    @EnvironmentObject var languageManager: LanguageManager
    @State private var selectedTab = 0
    @State private var searchText = ""
@State private var isSearchActive = false
    @FocusState private var isSearchFieldFocused: Bool

    // Batch create alerts (Tasks tab only)
    @State private var showCreateProjectAlert = false
    @State private var showCreateListAlert = false
    @State private var newProjectTitle = ""
    @State private var newListTitle = ""

    // Compact add-task bar state
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

    // Compact add-list bar state
    @State private var addListTitle = ""
    @State private var addListItems: [DraftSubtaskEntry] = []
    @State private var addListCategoryId: UUID? = nil
    @State private var addListCommitExpanded = false
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
    @State private var addProjectCommitExpanded = false
    @State private var addProjectTimeframe: Timeframe = .daily
    @State private var addProjectSection: Section = .todo
    @State private var addProjectDates: Set<Date> = []
    @State private var addProjectDatesSnapshot: Set<Date> = []
    @State private var addProjectOptionsExpanded = false
    @State private var addProjectPriority: Priority = .low
    @FocusState private var focusedProjectTaskId: UUID?

    // Unified title focus (single @FocusState = atomic transfer = no keyboard flicker)
    @FocusState private var addBarTitleFocus: AddBarTitleFocus?

    // View models — owned here, passed to child views
    @StateObject private var taskListVM = TaskListViewModel(authService: AuthService())
    @StateObject private var projectsVM = ProjectsViewModel(authService: AuthService())
    @StateObject private var listsVM = ListsViewModel(authService: AuthService())

    // Unified add bar state
    @State private var showingAddBar = false
    @State private var tabChangeFromAddBar = false
    @State private var addBarMode: TaskType = .task

    // Settings navigation
    @State private var showSettings = false

    // Focus view model for refreshing commitments after commit creation
    @EnvironmentObject var focusViewModel: FocusTabViewModel

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

    /// Shared pill height so the ellipsis pill matches the text pills
    private let subtaskPillHeight: CGFloat = 28

    private let tabKeys = ["Tasks", "Lists", "Projects"]

    var body: some View {
        NavigationStack {
            logContentStack
                .logTabHandlers(
                    selectedTab: $selectedTab,
                    tabChangeFromAddBar: $tabChangeFromAddBar,
                    taskListVM: taskListVM,
                    listsVM: listsVM,
                    projectsVM: projectsVM,
                    addBarTitleFocus: $addBarTitleFocus,
                    addTaskCommitExpanded: $addTaskCommitExpanded,
                    focusedSubtaskId: $focusedSubtaskId,
                    addListCommitExpanded: $addListCommitExpanded,
                    focusedListItemId: $focusedListItemId,
                    addProjectCommitExpanded: $addProjectCommitExpanded,
                    focusedProjectTaskId: $focusedProjectTaskId,
                    showCreateProjectAlert: $showCreateProjectAlert,
                    showCreateListAlert: $showCreateListAlert,
                    newProjectTitle: $newProjectTitle,
                    newListTitle: $newListTitle,
                    dismissSearch: dismissSearch,
                    dismissActiveAddBar: dismissActiveAddBar
                )
                .navigationDestination(isPresented: $showSettings) {
                    SettingsView()
                }
                .onChange(of: mainTab) {
                    showSettings = false
                }
                .onChange(of: taskListVM.selectedCategoryId) { _, newId in
                    if listsVM.selectedCategoryId != newId { listsVM.selectedCategoryId = newId }
                    if projectsVM.selectedCategoryId != newId { projectsVM.selectedCategoryId = newId }
                }
                .onChange(of: listsVM.selectedCategoryId) { _, newId in
                    if taskListVM.selectedCategoryId != newId { taskListVM.selectedCategoryId = newId }
                    if projectsVM.selectedCategoryId != newId { projectsVM.selectedCategoryId = newId }
                }
                .onChange(of: projectsVM.selectedCategoryId) { _, newId in
                    if taskListVM.selectedCategoryId != newId { taskListVM.selectedCategoryId = newId }
                    if listsVM.selectedCategoryId != newId { listsVM.selectedCategoryId = newId }
                }
                .onChange(of: taskListVM.categories.count) { _, _ in
                    syncCategories(from: 0)
                }
                .onChange(of: listsVM.categories.count) { _, _ in
                    syncCategories(from: 1)
                }
                .onChange(of: projectsVM.categories.count) { _, _ in
                    syncCategories(from: 2)
                }
                // Unified add bar: auto-focus on open
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
                // Unified add bar: focus transfer on mode switch
                .onChange(of: addBarMode) { _, newMode in
                    guard showingAddBar else { return }
                    // Clear secondary focus states
                    focusedSubtaskId = nil
                    focusedListItemId = nil
                    focusedProjectTaskId = nil
                    // Atomic focus transfer — single @FocusState, no keyboard flicker
                    switch newMode {
                    case .task: addBarTitleFocus = .task
                    case .list: addBarTitleFocus = .list
                    case .project: addBarTitleFocus = .project
                    }
                }
                // Bridge per-VM showingAddItem flags (from empty-state taps in child views)
                .onChange(of: taskListVM.showingAddTask) { _, show in
                    if show && !showingAddBar {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            addBarMode = .task
                            showingAddBar = true
                        }
                    }
                }
                .onChange(of: listsVM.showingAddList) { _, show in
                    if show && !showingAddBar {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            addBarMode = .list
                            showingAddBar = true
                        }
                    }
                }
                .onChange(of: projectsVM.showingAddProject) { _, show in
                    if show && !showingAddBar {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            addBarMode = .project
                            showingAddBar = true
                        }
                    }
                }
        }
    }

    private var logContentStack: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Row 0: Profile button — own row, right-aligned
                HStack {
                    Spacer()
                    profilePillButton
                }
                .padding(.trailing, 25)
                .padding(.top, 2)
                .padding(.bottom, 8)

                // Picker row
                Picker("", selection: $selectedTab) {
                    ForEach(Array(tabKeys.enumerated()), id: \.offset) { index, key in
                        Text(LocalizedStringKey(key)).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 14)

                // Tab content with shared controls overlay
                ZStack(alignment: .topLeading) {
                    // Tab content — all views stay alive to preserve scroll/state
                    ZStack {
                        TasksListView(viewModel: taskListVM, searchText: searchText, onSearchTap: activateSearch)
                            .opacity(selectedTab == 0 ? 1 : 0)
                            .allowsHitTesting(selectedTab == 0)

                        ListsView(viewModel: listsVM, searchText: searchText, onSearchTap: activateSearch)
                            .opacity(selectedTab == 1 ? 1 : 0)
                            .allowsHitTesting(selectedTab == 1)

                        ProjectsListView(viewModel: projectsVM, searchText: searchText, onSearchTap: activateSearch)
                            .opacity(selectedTab == 2 ? 1 : 0)
                            .allowsHitTesting(selectedTab == 2)
                    }

                    // Shared floating bottom area (FAB or EditModeActionBar)
                    floatingBottomArea
                        .opacity(isSearchActive ? 0 : 1)
                        .allowsHitTesting(!isSearchActive)
                        .animation(.none, value: isSearchActive)
                        .zIndex(5)
                }
                .frame(maxHeight: .infinity)
            }

            // Tap-to-dismiss overlay when search is active
            if isSearchActive {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            dismissSearch()
                        }
                    }
                    .zIndex(50)

                searchBarOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }

            // Add-item scrim + bar (unified)
            if showingAddBar {
                // Scrim — visual only, fades in
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(50)

                // All tap handling in one layer
                VStack(spacing: 0) {
                    // Tap-to-dismiss area
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                dismissActiveAddBar()
                            }
                        }

                    // Floating mode selector + add bar
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
    }

    private var profilePillButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "person")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.tint(.glassTint).interactive(), in: .circle)
        }
    }

    // MARK: - Search Bar Overlay (Above Keyboard)

    private var searchBarOverlay: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($isSearchFieldFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    dismissSearch()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.inter(.body, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal)
    }

    private func activateSearch() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isSearchActive = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isSearchFieldFocused = true
        }
    }

    private func dismissSearch() {
        searchText = ""
        isSearchActive = false
        isSearchFieldFocused = false
    }

    // MARK: - Shared Floating Bottom Area (FAB / Edit Action Bar)

    @ViewBuilder
    private var floatingBottomArea: some View {
        if selectedTab == 0 && taskListVM.isEditMode {
            EditModeActionBar(
                viewModel: taskListVM,
                showCreateProjectAlert: $showCreateProjectAlert,
                showCreateListAlert: $showCreateListAlert
            )
            .transition(.scale.combined(with: .opacity))
        } else if selectedTab == 1 && listsVM.isEditMode {
            EditModeActionBar(viewModel: listsVM)
                .transition(.scale.combined(with: .opacity))
        } else if selectedTab == 2 && projectsVM.isEditMode {
            EditModeActionBar(viewModel: projectsVM)
                .transition(.scale.combined(with: .opacity))
        } else if !showingAddBar {
            fabButton {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    switch selectedTab {
                    case 0: addBarMode = .task
                    case 1: addBarMode = .list
                    case 2: addBarMode = .project
                    default: addBarMode = .task
                    }
                    showingAddBar = true
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var activeAddBar: some View {
        switch addBarMode {
        case .task: logAddTaskBar
        case .list: logAddListBar
        case .project: logAddProjectBar
        }
    }

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
                // Sync background tab to match
                let tabIndex: Int
                switch mode {
                case .task: tabIndex = 0
                case .list: tabIndex = 1
                case .project: tabIndex = 2
                }
                if selectedTab != tabIndex {
                    tabChangeFromAddBar = true
                    selectedTab = tabIndex
                }
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

    // MARK: - Compact Add Task Bar

    private var logAddTaskBar: some View {
        VStack(spacing: 0) {
            // Task title row
            TextField("Create a new task", text: $addTaskTitle)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .task)
                .submitLabel(.return)
                .onSubmit {
                    saveLogTask()
                }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            // Subtasks (expand when present)
            DraftSubtaskListEditor(
                subtasks: $addTaskSubtasks,
                focusedSubtaskId: $focusedSubtaskId,
                onAddNew: { addNewSubtask() }
            )

            // Commit expansion (calendar section)
            if addTaskCommitExpanded {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 12) {
                    // Section picker
                    Picker("Section", selection: $addTaskSection) {
                        Text("Focus").tag(Section.focus)
                        Text("To-Do").tag(Section.todo)
                    }
                    .pickerStyle(.segmented)

                    // Calendar picker
                    UnifiedCalendarPicker(
                        selectedDates: $addTaskDates,
                        selectedTimeframe: $addTaskTimeframe
                    )
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 14)

                // Commit mode action row
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

                    // Submit button — highlighted only when dates changed
                    let hasDateChanges = addTaskDates != addTaskDatesSnapshot
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            addTaskCommitExpanded = false
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

            // Sub-task row: [Sub-task] ... [AI Breakdown (compact)]
            if !addTaskCommitExpanded {
            HStack(spacing: 8) {
                // Add sub-task button
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

                // AI Breakdown (compact, sized like Suggest Breakdown in TaskDetails)
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
                    saveLogTask()
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

            // Bottom row: [Category pill] [Commit pill] [Priority pill] — toggled by ellipsis
            if addTaskOptionsExpanded && !addTaskCommitExpanded {
            HStack(spacing: 8) {
                // Category pill
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

                // Commit toggle pill
                Button {
                    if !addTaskCommitExpanded {
                        addTaskDatesSnapshot = addTaskDates
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addTaskCommitExpanded.toggle()
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

                // Priority pill
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

    private var logAddListBar: some View {
        VStack(spacing: 0) {
            // List title row
            TextField("Create a new list", text: $addListTitle)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .list)
                .submitLabel(.return)
                .onSubmit {
                    saveLogList()
                }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            // Items (expand when present) — reuses DraftSubtaskListEditor for identical behavior
            DraftSubtaskListEditor(
                subtasks: $addListItems,
                focusedSubtaskId: $focusedListItemId,
                onAddNew: { addNewListItem() },
                placeholder: "Item"
            )

            // Commit expansion (calendar section)
            if addListCommitExpanded {
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

                // Commit mode action row
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            addListDates.removeAll()
                            addListCommitExpanded = false
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
                            addListCommitExpanded = false
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
            if !addListCommitExpanded {
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

                // More options pill
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

                // Submit button (checkmark)
                Button {
                    saveLogList()
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

            // Row 2: [Category] [Commit] [Priority] — toggled by ellipsis
            if addListOptionsExpanded && !addListCommitExpanded {
            HStack(spacing: 8) {
                // Category pill
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
                    ForEach(listsVM.categories) { category in
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

                // Commit toggle pill
                Button {
                    addListDatesSnapshot = addListDates
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addListCommitExpanded.toggle()
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

                // Priority pill
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

    private var logAddProjectBar: some View {
        VStack(spacing: 0) {
            // Project title row
            TextField("Create a new project", text: $addProjectTitle)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .project)
                .submitLabel(.return)
                .onSubmit {
                    saveLogProject()
                }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            // Tasks + subtasks area (always visible — seeded with one empty task)
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

            // Commit expansion (calendar section)
            if addProjectCommitExpanded {
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

                // Commit mode action row
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            addProjectDates.removeAll()
                            addProjectCommitExpanded = false
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
                            addProjectCommitExpanded = false
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
            if !addProjectCommitExpanded {
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

                // More options pill
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

                // Submit button (checkmark)
                Button {
                    saveLogProject()
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

            // Row 2: [Category] [Commit] [Priority] — toggled by ellipsis
            if addProjectOptionsExpanded && !addProjectCommitExpanded {
            HStack(spacing: 8) {
                // Category pill
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
                    ForEach(projectsVM.categories) { category in
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

                // Commit toggle pill
                Button {
                    addProjectDatesSnapshot = addProjectDates
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addProjectCommitExpanded.toggle()
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

                // Priority pill
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

    // MARK: - Project Task Draft Row (task + its subtasks + add subtask button)

    @ViewBuilder
    private func projectTaskDraftRow(task: DraftTask) -> some View {
        // Task row
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

    private var categoryPillLabel: String {
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
                // Silently fail — user can tap again or add subtasks manually
            }
            isGeneratingBreakdown = false
        }
    }

    private func saveLogTask() {
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

        // Transfer focus to title before removing subtask fields
        addBarTitleFocus = .task
        focusedSubtaskId = nil

        // Clear fields for rapid entry (keep category setting)
        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskDates = []
        addTaskOptionsExpanded = false
        addTaskCommitExpanded = false
        addTaskPriority = .low
        hasGeneratedBreakdown = false

        _Concurrency.Task { @MainActor in
            await taskListVM.createTaskWithCommitments(
                title: title,
                categoryId: categoryId,
                priority: priority,
                subtaskTitles: subtasksToCreate,
                commitAfterCreate: commitEnabled,
                selectedTimeframe: timeframe,
                selectedSection: section,
                selectedDates: dates,
                hasScheduledTime: false,
                scheduledTime: nil
            )

            // Refresh focus view if commitments were created
            if commitEnabled && !dates.isEmpty {
                await focusViewModel.fetchCommitments()
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
        addTaskCommitExpanded = false
        addTaskDates = []
        hasGeneratedBreakdown = false
        taskListVM.showingAddTask = false
        addBarTitleFocus = nil
        focusedSubtaskId = nil
    }

    // MARK: - Add List Helpers

    private var listCategoryPillLabel: String {
        if let categoryId = addListCategoryId,
           let category = listsVM.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private func saveLogList() {
        let title = addListTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let itemTitles = addListItems
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let categoryId = addListCategoryId
        let priority = addListPriority
        let commitEnabled = !addListDates.isEmpty
        let timeframe = addListTimeframe
        let section = addListSection
        let dates = addListDates

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Transfer focus to title for rapid entry
        addBarTitleFocus = .list
        focusedListItemId = nil

        // Clear fields (keep category)
        addListTitle = ""
        addListItems = []
        addListDates = []
        addListCommitExpanded = false
        addListOptionsExpanded = false
        addListPriority = .low

        _Concurrency.Task { @MainActor in
            await listsVM.createList(title: title, categoryId: categoryId, priority: priority)

            // Get the newly created list (inserted at index 0)
            if let createdList = listsVM.lists.first {
                for itemTitle in itemTitles {
                    await listsVM.createItem(title: itemTitle, listId: createdList.id)
                }
                if !itemTitles.isEmpty {
                    listsVM.expandedLists.insert(createdList.id)
                }

                // Create commitments if enabled
                if commitEnabled && !dates.isEmpty {
                    for date in dates {
                        let commitment = Commitment(
                            userId: createdList.userId,
                            taskId: createdList.id,
                            timeframe: timeframe,
                            section: section,
                            commitmentDate: date,
                            sortOrder: 0,
                            scheduledTime: nil,
                            durationMinutes: nil
                        )
                        _ = try? await listsVM.commitmentRepository.createCommitment(commitment)
                    }
                    await focusViewModel.fetchCommitments()
                    await listsVM.fetchCommittedTaskIds()
                }
            }
        }
    }

    private func listItemBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { addListItems.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let idx = addListItems.firstIndex(where: { $0.id == id }) {
                    addListItems[idx].title = newValue
                }
            }
        )
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

    private func removeListItem(id: UUID) {
        addBarTitleFocus = .list
        withAnimation(.easeInOut(duration: 0.15)) {
            addListItems.removeAll { $0.id == id }
        }
    }

    private func dismissAddList() {
        addListTitle = ""
        addListItems = []
        addListCategoryId = nil
        addListCommitExpanded = false
        addListOptionsExpanded = false
        addListPriority = .low
        addListDates = []
        listsVM.showingAddList = false
        addBarTitleFocus = nil
        focusedListItemId = nil
    }

    // MARK: - Add Project Helpers

    private var projectCategoryPillLabel: String {
        if let categoryId = addProjectCategoryId,
           let category = projectsVM.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private func saveLogProject() {
        let title = addProjectTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        // Pass nested DraftTask array directly (saveNewProject handles trimming/filtering)
        let draftTasks = addProjectDraftTasks.filter {
            !$0.title.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let categoryId = addProjectCategoryId
        let priority = addProjectPriority
        let commitEnabled = !addProjectDates.isEmpty
        let timeframe = addProjectTimeframe
        let section = addProjectSection
        let dates = addProjectDates

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        addBarTitleFocus = .project
        focusedProjectTaskId = nil

        // Clear fields (keep category)
        addProjectTitle = ""
        addProjectDraftTasks = []
        addProjectDates = []
        addProjectCommitExpanded = false
        addProjectOptionsExpanded = false
        addProjectPriority = .low

        _Concurrency.Task { @MainActor in
            guard let projectId = await projectsVM.saveNewProject(
                title: title,
                categoryId: categoryId,
                priority: priority,
                draftTasks: draftTasks
            ) else { return }

            if commitEnabled && !dates.isEmpty {
                guard let userId = projectsVM.authService.currentUser?.id else { return }
                for date in dates {
                    let commitment = Commitment(
                        userId: userId,
                        taskId: projectId,
                        timeframe: timeframe,
                        section: section,
                        commitmentDate: date,
                        sortOrder: 0,
                        scheduledTime: nil,
                        durationMinutes: nil
                    )
                    _ = try? await projectsVM.commitmentRepository.createCommitment(commitment)
                }
                await focusViewModel.fetchCommitments()
                await projectsVM.fetchCommittedTaskIds()
            }
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
        addProjectCommitExpanded = false
        addProjectOptionsExpanded = false
        addProjectPriority = .low
        addProjectDates = []
        projectsVM.showingAddProject = false
        addBarTitleFocus = nil
        focusedProjectTaskId = nil
    }

    // MARK: - Shared Dismiss

    private func dismissActiveAddBar() {
        guard showingAddBar else { return }
        // Dismiss all modes to clear any partial input across modes
        dismissAddTask()
        dismissAddList()
        dismissAddProject()
        showingAddBar = false
    }

    // MARK: - Category Sync

    /// Copy the active tab's categories to the other VMs so all tabs share the same list.
    private func syncCategories(from sourceTab: Int) {
        let sourceCategories: [Category]
        switch sourceTab {
        case 0: sourceCategories = taskListVM.categories
        case 1: sourceCategories = listsVM.categories
        case 2: sourceCategories = projectsVM.categories
        default: return
        }
        if sourceTab != 0 { taskListVM.categories = sourceCategories }
        if sourceTab != 1 { listsVM.categories = sourceCategories }
        if sourceTab != 2 { projectsVM.categories = sourceCategories }
    }
}

#Preview {
    LogTabView(mainTab: .constant(1))
}

// MARK: - LogTab onChange Modifiers (split into small groups for type-checker)

private struct LogTabChangeModifier: ViewModifier {
    @Binding var selectedTab: Int
    @Binding var tabChangeFromAddBar: Bool
    @ObservedObject var taskListVM: TaskListViewModel
    @ObservedObject var listsVM: ListsViewModel
    @ObservedObject var projectsVM: ProjectsViewModel
    var dismissSearch: () -> Void
    var dismissActiveAddBar: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: selectedTab) { _, _ in
                if tabChangeFromAddBar {
                    tabChangeFromAddBar = false
                    return
                }
                dismissSearch()
                taskListVM.exitEditMode()
                projectsVM.exitEditMode()
                listsVM.exitEditMode()
                dismissActiveAddBar()
            }
    }
}

private struct LogTaskBarHandlersModifier: ViewModifier {
    var addBarTitleFocus: FocusState<AddBarTitleFocus?>.Binding
    @Binding var addTaskCommitExpanded: Bool
    var focusedSubtaskId: FocusState<UUID?>.Binding

    func body(content: Content) -> some View {
        content
            .onChange(of: addTaskCommitExpanded) { _, isExpanded in
                if isExpanded {
                    addBarTitleFocus.wrappedValue = nil
                    focusedSubtaskId.wrappedValue = nil
                }
            }
            .onChange(of: addBarTitleFocus.wrappedValue) { _, focus in
                if focus == .task && addTaskCommitExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addTaskCommitExpanded = false
                    }
                }
            }
            .onChange(of: focusedSubtaskId.wrappedValue) { _, subtaskId in
                if subtaskId != nil && addTaskCommitExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addTaskCommitExpanded = false
                    }
                }
            }
    }
}

private struct LogListBarHandlersModifier: ViewModifier {
    var addBarTitleFocus: FocusState<AddBarTitleFocus?>.Binding
    @Binding var addListCommitExpanded: Bool
    var focusedListItemId: FocusState<UUID?>.Binding

    func body(content: Content) -> some View {
        content
            .onChange(of: addListCommitExpanded) { _, isExpanded in
                if isExpanded {
                    addBarTitleFocus.wrappedValue = nil
                    focusedListItemId.wrappedValue = nil
                }
            }
            .onChange(of: addBarTitleFocus.wrappedValue) { _, focus in
                if focus == .list && addListCommitExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addListCommitExpanded = false
                    }
                }
            }
            .onChange(of: focusedListItemId.wrappedValue) { _, itemId in
                if itemId != nil && addListCommitExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addListCommitExpanded = false
                    }
                }
            }
    }
}

private struct LogProjectBarHandlersModifier: ViewModifier {
    var addBarTitleFocus: FocusState<AddBarTitleFocus?>.Binding
    @Binding var addProjectCommitExpanded: Bool
    var focusedProjectTaskId: FocusState<UUID?>.Binding

    func body(content: Content) -> some View {
        content
            .onChange(of: addProjectCommitExpanded) { _, isExpanded in
                if isExpanded {
                    addBarTitleFocus.wrappedValue = nil
                    focusedProjectTaskId.wrappedValue = nil
                }
            }
            .onChange(of: addBarTitleFocus.wrappedValue) { _, focus in
                if focus == .project && addProjectCommitExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addProjectCommitExpanded = false
                    }
                }
            }
            .onChange(of: focusedProjectTaskId.wrappedValue) { _, taskId in
                if taskId != nil && addProjectCommitExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addProjectCommitExpanded = false
                    }
                }
            }
    }
}

private struct LogTabAlertsModifier: ViewModifier {
    @ObservedObject var taskListVM: TaskListViewModel
    @Binding var selectedTab: Int
    @Binding var showCreateProjectAlert: Bool
    @Binding var showCreateListAlert: Bool
    @Binding var newProjectTitle: String
    @Binding var newListTitle: String

    func body(content: Content) -> some View {
        content
            .alert("Create Project", isPresented: $showCreateProjectAlert) {
                TextField("Project title", text: $newProjectTitle)
                Button("Cancel", role: .cancel) { newProjectTitle = "" }
                Button("Create") {
                    let title = newProjectTitle
                    newProjectTitle = ""
                    _Concurrency.Task { @MainActor in
                        await taskListVM.createProjectFromSelected(title: title)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            selectedTab = 2
                        }
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
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            selectedTab = 1
                        }
                    }
                }
            } message: {
                Text("Enter a name for the new list")
            }
    }
}

private extension View {
    func logTabHandlers(
        selectedTab: Binding<Int>,
        tabChangeFromAddBar: Binding<Bool>,
        taskListVM: TaskListViewModel,
        listsVM: ListsViewModel,
        projectsVM: ProjectsViewModel,
        addBarTitleFocus: FocusState<AddBarTitleFocus?>.Binding,
        addTaskCommitExpanded: Binding<Bool>,
        focusedSubtaskId: FocusState<UUID?>.Binding,
        addListCommitExpanded: Binding<Bool>,
        focusedListItemId: FocusState<UUID?>.Binding,
        addProjectCommitExpanded: Binding<Bool>,
        focusedProjectTaskId: FocusState<UUID?>.Binding,
        showCreateProjectAlert: Binding<Bool>,
        showCreateListAlert: Binding<Bool>,
        newProjectTitle: Binding<String>,
        newListTitle: Binding<String>,
        dismissSearch: @escaping () -> Void,
        dismissActiveAddBar: @escaping () -> Void
    ) -> some View {
        self
            .modifier(LogTabChangeModifier(
                selectedTab: selectedTab,
                tabChangeFromAddBar: tabChangeFromAddBar,
                taskListVM: taskListVM,
                listsVM: listsVM,
                projectsVM: projectsVM,
                dismissSearch: dismissSearch,
                dismissActiveAddBar: dismissActiveAddBar
            ))
            .modifier(LogTaskBarHandlersModifier(
                addBarTitleFocus: addBarTitleFocus,
                addTaskCommitExpanded: addTaskCommitExpanded,
                focusedSubtaskId: focusedSubtaskId
            ))
            .modifier(LogListBarHandlersModifier(
                addBarTitleFocus: addBarTitleFocus,
                addListCommitExpanded: addListCommitExpanded,
                focusedListItemId: focusedListItemId
            ))
            .modifier(LogProjectBarHandlersModifier(
                addBarTitleFocus: addBarTitleFocus,
                addProjectCommitExpanded: addProjectCommitExpanded,
                focusedProjectTaskId: focusedProjectTaskId
            ))
            .modifier(LogTabAlertsModifier(
                taskListVM: taskListVM,
                selectedTab: selectedTab,
                showCreateProjectAlert: showCreateProjectAlert,
                showCreateListAlert: showCreateListAlert,
                newProjectTitle: newProjectTitle,
                newListTitle: newListTitle
            ))
    }
}
