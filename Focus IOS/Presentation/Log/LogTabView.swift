//
//  LogTabView.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

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

    // View models — owned here, passed to child views
    @StateObject private var taskListVM = TaskListViewModel(authService: AuthService())
    @StateObject private var projectsVM = ProjectsViewModel(authService: AuthService())
    @StateObject private var listsVM = ListsViewModel(authService: AuthService())

    // Focus view model for refreshing commitments after commit creation
    @EnvironmentObject var focusViewModel: FocusTabViewModel

    // Pre-computed title emptiness check
    private var isAddTaskTitleEmpty: Bool {
        addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
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

                // Add-task scrim + bar (Tasks tab only)
                if taskListVM.showingAddTask && selectedTab == 0 {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                dismissAddTask()
                            }
                        }
                        .allowsHitTesting(true)
                        .zIndex(50)

                    VStack {
                        Spacer()
                        logAddTaskBar
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
                }
            }
            .onChange(of: selectedTab) { _, _ in
                dismissSearch()
                showCategoryDropdown = false
                // Exit edit mode on all VMs
                taskListVM.exitEditMode()
                projectsVM.exitEditMode()
                listsVM.exitEditMode()
                // Dismiss add task bar if open
                if taskListVM.showingAddTask {
                    dismissAddTask()
                }
            }
            .onChange(of: taskListVM.showingAddTask) { _, isShowing in
                if isShowing && selectedTab == 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isAddTaskFieldFocused = true
                    }
                }
            }
            .onChange(of: addTaskCommitExpanded) { _, isExpanded in
                if isExpanded {
                    // Calendar showing — dismiss keyboard
                    isAddTaskFieldFocused = false
                    focusedSubtaskId = nil
                }
            }
            .onChange(of: isAddTaskFieldFocused) { _, isFocused in
                if isFocused && addTaskCommitExpanded {
                    // Title tapped — collapse calendar, keep dates
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addTaskCommitExpanded = false
                    }
                }
            }
            .onChange(of: focusedSubtaskId) { _, subtaskId in
                if subtaskId != nil && addTaskCommitExpanded {
                    // Subtask tapped — collapse calendar, keep dates
                    withAnimation(.easeInOut(duration: 0.2)) {
                        addTaskCommitExpanded = false
                    }
                }
            }
            // Batch create project alert (Tasks tab)
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
            // Batch create list alert (Tasks tab)
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
        } else {
            fabButton { projectsVM.showingAddItem = true }
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var listTabBottomArea: some View {
        if listsVM.isEditMode {
            EditModeActionBar(viewModel: listsVM)
                .transition(.scale.combined(with: .opacity))
        } else {
            fabButton { listsVM.showingAddItem = true }
                .transition(.scale.combined(with: .opacity))
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
                        .glassEffect(.regular.tint(.blue).interactive(), in: .circle)
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
            TextField("Add new task.", text: $addTaskTitle)
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
}

#Preview {
    LogTabView()
}
