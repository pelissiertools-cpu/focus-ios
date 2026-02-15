//
//  LogTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI
import Auth

struct LogTabView: View {
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var isSearchFieldFocused: Bool

    // Shared filter state
    @State private var showCategoryDropdown = false

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
    @State private var addTaskSection: Section = .focus
    @State private var addTaskDates: Set<Date> = []
    @FocusState private var isAddTaskFieldFocused: Bool
    @FocusState private var focusedSubtaskId: UUID?

    // Compact add-list bar state
    @State private var addListTitle = ""
    @State private var addListItems: [DraftSubtaskEntry] = []
    @State private var addListCategoryId: UUID? = nil
    @State private var addListCommitExpanded = false
    @State private var addListTimeframe: Timeframe = .daily
    @State private var addListSection: Section = .focus
    @State private var addListDates: Set<Date> = []
    @FocusState private var isAddListFieldFocused: Bool
    @FocusState private var focusedListItemId: UUID?

    // Compact add-project bar state
    @State private var addProjectTitle = ""
    @State private var addProjectDraftTasks: [DraftTask] = []
    @State private var addProjectCategoryId: UUID? = nil
    @State private var addProjectCommitExpanded = false
    @State private var addProjectTimeframe: Timeframe = .daily
    @State private var addProjectSection: Section = .focus
    @State private var addProjectDates: Set<Date> = []
    @FocusState private var isAddProjectFieldFocused: Bool
    @FocusState private var focusedProjectTaskId: UUID?

    // View models — owned here, passed to child views
    @StateObject private var taskListVM = TaskListViewModel(authService: AuthService())
    @StateObject private var projectsVM = ProjectsViewModel(authService: AuthService())
    @StateObject private var listsVM = ListsViewModel(authService: AuthService())

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

    var body: some View {
        NavigationView {
            logContentStack
                .logTabHandlers(
                    selectedTab: $selectedTab,
                    taskListVM: taskListVM,
                    listsVM: listsVM,
                    projectsVM: projectsVM,
                    isAddTaskFieldFocused: $isAddTaskFieldFocused,
                    addTaskCommitExpanded: $addTaskCommitExpanded,
                    focusedSubtaskId: $focusedSubtaskId,
                    isAddListFieldFocused: $isAddListFieldFocused,
                    addListCommitExpanded: $addListCommitExpanded,
                    focusedListItemId: $focusedListItemId,
                    isAddProjectFieldFocused: $isAddProjectFieldFocused,
                    addProjectCommitExpanded: $addProjectCommitExpanded,
                    focusedProjectTaskId: $focusedProjectTaskId,
                    addProjectDraftTasks: $addProjectDraftTasks,
                    showCategoryDropdown: $showCategoryDropdown,
                    showCreateProjectAlert: $showCreateProjectAlert,
                    showCreateListAlert: $showCreateListAlert,
                    newProjectTitle: $newProjectTitle,
                    newListTitle: $newListTitle,
                    dismissSearch: dismissSearch,
                    dismissAddTask: dismissAddTask,
                    dismissAddList: dismissAddList,
                    dismissAddProject: dismissAddProject
                )
        }
    }

    private var logContentStack: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Picker row with search pill
                HStack(spacing: 12) {
                    Picker("Log Type", selection: $selectedTab) {
                        Text("Tasks").tag(0)
                        Text("Lists").tag(1)
                        Text("Projects").tag(2)
                    }
                    .pickerStyle(.segmented)

                    searchPillButton
                }
                .padding(.horizontal)
                .padding(.top, 40)
                .padding(.bottom, 14)

                // Tab content with shared controls overlay
                ZStack(alignment: .topLeading) {
                    // Tab content — all views stay alive to preserve scroll/state
                    ZStack {
                        TasksListView(viewModel: taskListVM, searchText: searchText, isSearchFocused: .constant(false))
                            .opacity(selectedTab == 0 ? 1 : 0)
                            .allowsHitTesting(selectedTab == 0)

                        ListsView(viewModel: listsVM, searchText: searchText)
                            .opacity(selectedTab == 1 ? 1 : 0)
                            .allowsHitTesting(selectedTab == 1)

                        ProjectsListView(viewModel: projectsVM, searchText: searchText)
                            .opacity(selectedTab == 2 ? 1 : 0)
                            .allowsHitTesting(selectedTab == 2)
                    }

                    // Shared filter bar (floats on top)
                    filterBar
                        .zIndex(10)

                    // Shared category dropdown overlay
                    categoryDropdown
                        .zIndex(20)

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

            // Add-item scrim + bar (any tab)
            if (taskListVM.showingAddTask && selectedTab == 0) ||
               (listsVM.showingAddList && selectedTab == 1) ||
               (projectsVM.showingAddProject && selectedTab == 2) {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            dismissActiveAddBar()
                        }
                    }
                    .allowsHitTesting(true)
                    .zIndex(50)

                VStack {
                    Spacer()
                    activeAddBar
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
    }

    // MARK: - Search Pill Button

    private var searchPillButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isSearchActive = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundColor(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray5))
                .clipShape(Circle())
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
                    .font(.body.weight(.medium))
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

    private func dismissSearch() {
        searchText = ""
        isSearchActive = false
        isSearchFieldFocused = false
    }

    // MARK: - Shared Filter Bar

    @ViewBuilder
    private var filterBar: some View {
        switch selectedTab {
        case 0:
            LogFilterBar(viewModel: taskListVM, showCategoryDropdown: $showCategoryDropdown)
        case 1:
            LogFilterBar(viewModel: listsVM, showCategoryDropdown: $showCategoryDropdown)
        case 2:
            LogFilterBar(viewModel: projectsVM, showCategoryDropdown: $showCategoryDropdown)
        default:
            EmptyView()
        }
    }

    // MARK: - Shared Category Dropdown

    @ViewBuilder
    private var categoryDropdown: some View {
        if showCategoryDropdown {
            switch selectedTab {
            case 0:
                SharedCategoryDropdownMenu(viewModel: taskListVM, showDropdown: $showCategoryDropdown)
            case 1:
                SharedCategoryDropdownMenu(viewModel: listsVM, showDropdown: $showCategoryDropdown)
            case 2:
                SharedCategoryDropdownMenu(viewModel: projectsVM, showDropdown: $showCategoryDropdown)
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Shared Floating Bottom Area (FAB / Edit Action Bar)

    @ViewBuilder
    private var floatingBottomArea: some View {
        switch selectedTab {
        case 0:
            taskTabBottomArea
        case 1:
            listTabBottomArea
        case 2:
            projectTabBottomArea
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var taskTabBottomArea: some View {
        if taskListVM.isEditMode {
            EditModeActionBar(
                viewModel: taskListVM,
                showCreateProjectAlert: $showCreateProjectAlert,
                showCreateListAlert: $showCreateListAlert
            )
            .transition(.scale.combined(with: .opacity))
        } else if !taskListVM.showingAddTask {
            fabButton {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    taskListVM.showingAddItem = true
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var projectTabBottomArea: some View {
        if projectsVM.isEditMode {
            EditModeActionBar(viewModel: projectsVM)
                .transition(.scale.combined(with: .opacity))
        } else if !projectsVM.showingAddProject {
            fabButton {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    projectsVM.showingAddItem = true
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var listTabBottomArea: some View {
        if listsVM.isEditMode {
            EditModeActionBar(viewModel: listsVM)
                .transition(.scale.combined(with: .opacity))
        } else if !listsVM.showingAddList {
            fabButton {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    listsVM.showingAddItem = true
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var activeAddBar: some View {
        switch selectedTab {
        case 0: logAddTaskBar
        case 1: logAddListBar
        case 2: logAddProjectBar
        default: EmptyView()
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
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.black, in: Circle())
                        .shadow(radius: 4, y: 2)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Compact Add Task Bar

    private var logAddTaskBar: some View {
        VStack(spacing: 0) {
            // Task title row
            TextField("Create a new task", text: $addTaskTitle)
                .font(.title3)
                .textFieldStyle(.plain)
                .focused($isAddTaskFieldFocused)
                .submitLabel(.return)
                .onSubmit {
                    saveLogTask()
                }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            // Subtasks (expand when present)
            if !addTaskSubtasks.isEmpty {
                Divider()
                    .padding(.horizontal, 14)

                VStack(spacing: 8) {
                    ForEach(addTaskSubtasks) { subtask in
                        HStack(spacing: 8) {
                            Image(systemName: "circle")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.5))

                            TextField("Subtask", text: subtaskBinding(for: subtask.id), axis: .vertical)
                                .font(.subheadline)
                                .textFieldStyle(.plain)
                                .focused($focusedSubtaskId, equals: subtask.id)
                                .lineLimit(1)
                                .onChange(of: subtaskBinding(for: subtask.id).wrappedValue) { _, newValue in
                                    if newValue.contains("\n") {
                                        if let idx = addTaskSubtasks.firstIndex(where: { $0.id == subtask.id }) {
                                            addTaskSubtasks[idx].title = newValue.replacingOccurrences(of: "\n", with: "")
                                        }
                                        addNewSubtask()
                                    }
                                }

                            Button {
                                removeSubtask(id: subtask.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 10)
            }

            // Commit expansion (calendar section)
            if addTaskCommitExpanded {
                Divider()
                    .padding(.horizontal, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Section picker
                        Picker("Section", selection: $addTaskSection) {
                            Text("Focus").tag(Section.focus)
                            Text("Extra").tag(Section.extra)
                        }
                        .pickerStyle(.segmented)

                        // Calendar picker
                        UnifiedCalendarPicker(
                            selectedDates: $addTaskDates,
                            selectedTimeframe: $addTaskTimeframe
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 350)
            }

            // Bottom row: [Sub-task] ... [Category pill] [Commit pill] [Checkmark]
            HStack(spacing: 8) {
                // Add sub-task button
                Button {
                    addNewSubtask()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption)
                        Text("Sub-task")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

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
                            .font(.caption)
                        Text(categoryPillLabel)
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(addTaskCategoryId != nil ? Color.blue : Color.black, in: Capsule())
                }

                // Commit toggle pill
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addTaskCommitExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.caption)
                        Text("Commit")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(!addTaskDates.isEmpty ? Color.blue : Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                // Submit button (checkmark)
                Button {
                    saveLogTask()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundColor(isAddTaskTitleEmpty ? .secondary : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            isAddTaskTitleEmpty ? Color(.systemGray4) : Color.blue,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAddTaskTitleEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 20)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
    }

    // MARK: - Compact Add List Bar

    private var logAddListBar: some View {
        VStack(spacing: 0) {
            // List title row
            TextField("Create a new list", text: $addListTitle)
                .font(.title3)
                .textFieldStyle(.plain)
                .focused($isAddListFieldFocused)
                .submitLabel(.return)
                .onSubmit {
                    saveLogList()
                }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            // Items (expand when present)
            if !addListItems.isEmpty {
                Divider()
                    .padding(.horizontal, 14)

                VStack(spacing: 8) {
                    ForEach(addListItems) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "circle")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.5))

                            TextField("Item", text: listItemBinding(for: item.id), axis: .vertical)
                                .font(.subheadline)
                                .textFieldStyle(.plain)
                                .focused($focusedListItemId, equals: item.id)
                                .lineLimit(1)
                                .onChange(of: listItemBinding(for: item.id).wrappedValue) { _, newValue in
                                    if newValue.contains("\n") {
                                        if let idx = addListItems.firstIndex(where: { $0.id == item.id }) {
                                            addListItems[idx].title = newValue.replacingOccurrences(of: "\n", with: "")
                                        }
                                        addNewListItem()
                                    }
                                }

                            Button {
                                removeListItem(id: item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 10)
            }

            // Commit expansion (calendar section)
            if addListCommitExpanded {
                Divider()
                    .padding(.horizontal, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Section", selection: $addListSection) {
                            Text("Focus").tag(Section.focus)
                            Text("Extra").tag(Section.extra)
                        }
                        .pickerStyle(.segmented)

                        UnifiedCalendarPicker(
                            selectedDates: $addListDates,
                            selectedTimeframe: $addListTimeframe
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 350)
            }

            // Bottom row: [Item] ... [Category pill] [Commit pill] [Checkmark]
            HStack(spacing: 8) {
                Button {
                    addNewListItem()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption)
                        Text("Item")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

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
                            .font(.caption)
                        Text(listCategoryPillLabel)
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(addListCategoryId != nil ? Color.blue : Color.black, in: Capsule())
                }

                // Commit toggle pill
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addListCommitExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.caption)
                        Text("Commit")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(!addListDates.isEmpty ? Color.blue : Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                // Submit button (checkmark)
                Button {
                    saveLogList()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundColor(isAddListTitleEmpty ? .secondary : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            isAddListTitleEmpty ? Color(.systemGray4) : Color.blue,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAddListTitleEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 20)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
    }

    // MARK: - Compact Add Project Bar

    private var logAddProjectBar: some View {
        VStack(spacing: 0) {
            // Project title row
            TextField("Create a new project.", text: $addProjectTitle)
                .font(.title3)
                .textFieldStyle(.plain)
                .focused($isAddProjectFieldFocused)
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

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(addProjectDraftTasks) { task in
                            projectTaskDraftRow(task: task)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 400)
            }

            // Commit expansion (calendar section)
            if addProjectCommitExpanded {
                Divider()
                    .padding(.horizontal, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Section", selection: $addProjectSection) {
                            Text("Focus").tag(Section.focus)
                            Text("Extra").tag(Section.extra)
                        }
                        .pickerStyle(.segmented)

                        UnifiedCalendarPicker(
                            selectedDates: $addProjectDates,
                            selectedTimeframe: $addProjectTimeframe
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 350)
            }

            // Bottom row: [Task] ... [Category pill] [Commit pill] [Checkmark]
            HStack(spacing: 8) {
                Button {
                    addNewProjectTask()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption)
                        Text("Task")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

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
                            .font(.caption)
                        Text(projectCategoryPillLabel)
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(addProjectCategoryId != nil ? Color.blue : Color.black, in: Capsule())
                }

                // Commit toggle pill
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addProjectCommitExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.caption)
                        Text("Commit")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(!addProjectDates.isEmpty ? Color.blue : Color.black, in: Capsule())
                }
                .buttonStyle(.plain)

                // Submit button (checkmark)
                Button {
                    saveLogProject()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundColor(isAddProjectTitleEmpty ? .secondary : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            isAddProjectTitleEmpty ? Color(.systemGray4) : Color.blue,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(isAddProjectTitleEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 20)
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
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))

            TextField("Task", text: projectTaskBinding(for: task.id), axis: .vertical)
                .font(.subheadline)
                .textFieldStyle(.plain)
                .focused($focusedProjectTaskId, equals: task.id)
                .lineLimit(1)
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
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }

        // Subtask rows
        ForEach(task.subtasks) { subtask in
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .font(.system(size: 6))
                    .foregroundColor(.secondary.opacity(0.4))

                TextField("Sub-task", text: projectSubtaskBinding(forSubtask: subtask.id, inTask: task.id), axis: .vertical)
                    .font(.caption)
                    .textFieldStyle(.plain)
                    .focused($focusedProjectTaskId, equals: subtask.id)
                    .lineLimit(1)
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
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 24)
        }

        // "+ Sub-task" button
        Button {
            addNewProjectSubtask(toTask: task.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9))
                Text("Sub-task")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.leading, 24)
        .padding(.top, 2)
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

    private func saveLogTask() {
        let title = addTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

        let subtasksToCreate = addTaskSubtasks
            .map { $0.title.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let categoryId = addTaskCategoryId
        let commitEnabled = !addTaskDates.isEmpty
        let timeframe = addTaskTimeframe
        let section = addTaskSection
        let dates = addTaskDates

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Transfer focus to title before removing subtask fields
        isAddTaskFieldFocused = true
        focusedSubtaskId = nil

        // Clear fields for rapid entry (keep category setting)
        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskDates = []
        addTaskCommitExpanded = false

        _Concurrency.Task { @MainActor in
            await taskListVM.createTaskWithCommitments(
                title: title,
                categoryId: categoryId,
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

    private func subtaskBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { addTaskSubtasks.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let idx = addTaskSubtasks.firstIndex(where: { $0.id == id }) {
                    addTaskSubtasks[idx].title = newValue
                }
            }
        )
    }

    private func addNewSubtask() {
        isAddTaskFieldFocused = true
        let newEntry = DraftSubtaskEntry()
        withAnimation(.easeInOut(duration: 0.15)) {
            addTaskSubtasks.append(newEntry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedSubtaskId = newEntry.id
        }
    }

    private func removeSubtask(id: UUID) {
        isAddTaskFieldFocused = true
        withAnimation(.easeInOut(duration: 0.15)) {
            addTaskSubtasks.removeAll { $0.id == id }
        }
    }

    private func dismissAddTask() {
        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskCategoryId = nil
        addTaskCommitExpanded = false
        addTaskDates = []
        taskListVM.showingAddTask = false
        isAddTaskFieldFocused = false
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
        let commitEnabled = !addListDates.isEmpty
        let timeframe = addListTimeframe
        let section = addListSection
        let dates = addListDates

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Transfer focus to title for rapid entry
        isAddListFieldFocused = true
        focusedListItemId = nil

        // Clear fields (keep category)
        addListTitle = ""
        addListItems = []
        addListDates = []
        addListCommitExpanded = false

        _Concurrency.Task { @MainActor in
            await listsVM.createList(title: title, categoryId: categoryId)

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
        isAddListFieldFocused = true
        let newEntry = DraftSubtaskEntry()
        withAnimation(.easeInOut(duration: 0.15)) {
            addListItems.append(newEntry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedListItemId = newEntry.id
        }
    }

    private func removeListItem(id: UUID) {
        isAddListFieldFocused = true
        withAnimation(.easeInOut(duration: 0.15)) {
            addListItems.removeAll { $0.id == id }
        }
    }

    private func dismissAddList() {
        addListTitle = ""
        addListItems = []
        addListCategoryId = nil
        addListCommitExpanded = false
        addListDates = []
        listsVM.showingAddList = false
        isAddListFieldFocused = false
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
        let commitEnabled = !addProjectDates.isEmpty
        let timeframe = addProjectTimeframe
        let section = addProjectSection
        let dates = addProjectDates

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        isAddProjectFieldFocused = true
        focusedProjectTaskId = nil

        // Clear fields (keep category)
        addProjectTitle = ""
        addProjectDraftTasks = []
        addProjectDates = []
        addProjectCommitExpanded = false

        _Concurrency.Task { @MainActor in
            guard let projectId = await projectsVM.saveNewProject(
                title: title,
                categoryId: categoryId,
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
        addProjectDates = []
        projectsVM.showingAddProject = false
        isAddProjectFieldFocused = false
        focusedProjectTaskId = nil
    }

    // MARK: - Shared Dismiss

    private func dismissActiveAddBar() {
        switch selectedTab {
        case 0: dismissAddTask()
        case 1: dismissAddList()
        case 2: dismissAddProject()
        default: break
        }
    }
}

#Preview {
    LogTabView()
}

// MARK: - LogTab onChange Modifiers (split into small groups for type-checker)

private struct LogTabChangeModifier: ViewModifier {
    @Binding var selectedTab: Int
    @ObservedObject var taskListVM: TaskListViewModel
    @ObservedObject var listsVM: ListsViewModel
    @ObservedObject var projectsVM: ProjectsViewModel
    @Binding var showCategoryDropdown: Bool
    var dismissSearch: () -> Void
    var dismissAddTask: () -> Void
    var dismissAddList: () -> Void
    var dismissAddProject: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: selectedTab) { _, _ in
                dismissSearch()
                showCategoryDropdown = false
                taskListVM.exitEditMode()
                projectsVM.exitEditMode()
                listsVM.exitEditMode()
                if taskListVM.showingAddTask { dismissAddTask() }
                if listsVM.showingAddList { dismissAddList() }
                if projectsVM.showingAddProject { dismissAddProject() }
            }
    }
}

private struct LogTaskBarHandlersModifier: ViewModifier {
    let selectedTab: Int
    @ObservedObject var taskListVM: TaskListViewModel
    var isAddTaskFieldFocused: FocusState<Bool>.Binding
    @Binding var addTaskCommitExpanded: Bool
    var focusedSubtaskId: FocusState<UUID?>.Binding

    func body(content: Content) -> some View {
        content
            .onChange(of: taskListVM.showingAddTask) { _, isShowing in
                if isShowing && selectedTab == 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isAddTaskFieldFocused.wrappedValue = true
                    }
                }
            }
            .onChange(of: addTaskCommitExpanded) { _, isExpanded in
                if isExpanded {
                    isAddTaskFieldFocused.wrappedValue = false
                    focusedSubtaskId.wrappedValue = nil
                }
            }
            .onChange(of: isAddTaskFieldFocused.wrappedValue) { _, isFocused in
                if isFocused && addTaskCommitExpanded {
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
    let selectedTab: Int
    @ObservedObject var listsVM: ListsViewModel
    var isAddListFieldFocused: FocusState<Bool>.Binding
    @Binding var addListCommitExpanded: Bool
    var focusedListItemId: FocusState<UUID?>.Binding

    func body(content: Content) -> some View {
        content
            .onChange(of: listsVM.showingAddList) { _, isShowing in
                if isShowing && selectedTab == 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isAddListFieldFocused.wrappedValue = true
                    }
                }
            }
            .onChange(of: addListCommitExpanded) { _, isExpanded in
                if isExpanded {
                    isAddListFieldFocused.wrappedValue = false
                    focusedListItemId.wrappedValue = nil
                }
            }
            .onChange(of: isAddListFieldFocused.wrappedValue) { _, isFocused in
                if isFocused && addListCommitExpanded {
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
    let selectedTab: Int
    @ObservedObject var projectsVM: ProjectsViewModel
    var isAddProjectFieldFocused: FocusState<Bool>.Binding
    @Binding var addProjectCommitExpanded: Bool
    var focusedProjectTaskId: FocusState<UUID?>.Binding
    @Binding var addProjectDraftTasks: [DraftTask]

    func body(content: Content) -> some View {
        content
            .onChange(of: projectsVM.showingAddProject) { _, isShowing in
                if isShowing && selectedTab == 2 {
                    // Seed one empty task so the field is always visible
                    if addProjectDraftTasks.isEmpty {
                        addProjectDraftTasks = [DraftTask()]
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isAddProjectFieldFocused.wrappedValue = true
                    }
                }
            }
            .onChange(of: addProjectCommitExpanded) { _, isExpanded in
                if isExpanded {
                    isAddProjectFieldFocused.wrappedValue = false
                    focusedProjectTaskId.wrappedValue = nil
                }
            }
            .onChange(of: isAddProjectFieldFocused.wrappedValue) { _, isFocused in
                if isFocused && addProjectCommitExpanded {
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
        taskListVM: TaskListViewModel,
        listsVM: ListsViewModel,
        projectsVM: ProjectsViewModel,
        isAddTaskFieldFocused: FocusState<Bool>.Binding,
        addTaskCommitExpanded: Binding<Bool>,
        focusedSubtaskId: FocusState<UUID?>.Binding,
        isAddListFieldFocused: FocusState<Bool>.Binding,
        addListCommitExpanded: Binding<Bool>,
        focusedListItemId: FocusState<UUID?>.Binding,
        isAddProjectFieldFocused: FocusState<Bool>.Binding,
        addProjectCommitExpanded: Binding<Bool>,
        focusedProjectTaskId: FocusState<UUID?>.Binding,
        addProjectDraftTasks: Binding<[DraftTask]>,
        showCategoryDropdown: Binding<Bool>,
        showCreateProjectAlert: Binding<Bool>,
        showCreateListAlert: Binding<Bool>,
        newProjectTitle: Binding<String>,
        newListTitle: Binding<String>,
        dismissSearch: @escaping () -> Void,
        dismissAddTask: @escaping () -> Void,
        dismissAddList: @escaping () -> Void,
        dismissAddProject: @escaping () -> Void
    ) -> some View {
        self
            .modifier(LogTabChangeModifier(
                selectedTab: selectedTab,
                taskListVM: taskListVM,
                listsVM: listsVM,
                projectsVM: projectsVM,
                showCategoryDropdown: showCategoryDropdown,
                dismissSearch: dismissSearch,
                dismissAddTask: dismissAddTask,
                dismissAddList: dismissAddList,
                dismissAddProject: dismissAddProject
            ))
            .modifier(LogTaskBarHandlersModifier(
                selectedTab: selectedTab.wrappedValue,
                taskListVM: taskListVM,
                isAddTaskFieldFocused: isAddTaskFieldFocused,
                addTaskCommitExpanded: addTaskCommitExpanded,
                focusedSubtaskId: focusedSubtaskId
            ))
            .modifier(LogListBarHandlersModifier(
                selectedTab: selectedTab.wrappedValue,
                listsVM: listsVM,
                isAddListFieldFocused: isAddListFieldFocused,
                addListCommitExpanded: addListCommitExpanded,
                focusedListItemId: focusedListItemId
            ))
            .modifier(LogProjectBarHandlersModifier(
                selectedTab: selectedTab.wrappedValue,
                projectsVM: projectsVM,
                isAddProjectFieldFocused: isAddProjectFieldFocused,
                addProjectCommitExpanded: addProjectCommitExpanded,
                focusedProjectTaskId: focusedProjectTaskId,
                addProjectDraftTasks: addProjectDraftTasks
            ))
            .modifier(LogTabAlertsModifier(
                taskListVM: taskListVM,
                showCreateProjectAlert: showCreateProjectAlert,
                showCreateListAlert: showCreateListAlert,
                newProjectTitle: newProjectTitle,
                newListTitle: newListTitle
            ))
    }
}
