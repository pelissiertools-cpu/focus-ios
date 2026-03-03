//
//  UnassignedView.swift
//  Focus IOS
//

import SwiftUI
import Auth

private enum AddBarTitleFocus: Hashable {
    case task, list, project
}

struct UnassignedView: View {
    @StateObject private var taskListVM = TaskListViewModel(authService: AuthService())
    @StateObject private var listsVM = ListsViewModel(authService: AuthService())
    @StateObject private var projectsVM = ProjectsViewModel(authService: AuthService())
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isInlineAddFocused = false
    @State private var isLoading = false

    // Batch create alerts
    @State private var showCreateProjectAlert = false
    @State private var showCreateListAlert = false
    @State private var newProjectTitle = ""
    @State private var newListTitle = ""

    // Unified add bar state
    @State private var showingAddBar = false
    @State private var addBarMode: TaskType = .task

    // Add task bar state
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

    // Add list bar state
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

    // Add project bar state
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

    // Unified title focus
    @FocusState private var addBarTitleFocus: AddBarTitleFocus?

    private var isAddTaskTitleEmpty: Bool {
        addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isAddListTitleEmpty: Bool {
        addListTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isAddProjectTitleEmpty: Bool {
        addProjectTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Tasks not in a project
    private var standaloneUncompletedTasks: [FocusTask] {
        taskListVM.uncompletedTasks.filter { $0.projectId == nil }
    }

    private var isEmpty: Bool {
        standaloneUncompletedTasks.isEmpty
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "tray")
                        .font(.inter(size: 22, weight: .regular))
                        .foregroundColor(.primary)

                    Text("Unassign")
                        .font(.inter(size: 28, weight: .regular))
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                if isLoading && isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isEmpty {
                    VStack(spacing: 4) {
                        Text("No unassigned items")
                            .font(.inter(.headline))
                            .bold()
                        Text("Tasks without a schedule will appear here")
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
            } else if !showingAddBar {
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

                    addBarModeSelector

                    activeAddBar
                        .padding(.bottom, 8)
                        .contentShape(Rectangle())
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
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
        .onChange(of: addBarMode) { _, newMode in
            switch newMode {
            case .task: addBarTitleFocus = .task
            case .list: addBarTitleFocus = .list
            case .project: addBarTitleFocus = .project
            }
        }
        // Task sheets
        .sheet(item: $taskListVM.selectedTaskForDetails) { task in
            TaskDetailsDrawer(task: task, viewModel: taskListVM, categories: taskListVM.categories)
                .drawerStyle()
        }
        .sheet(item: $taskListVM.selectedTaskForSchedule) { task in
            CommitmentSelectionSheet(task: task, focusViewModel: focusViewModel)
                .drawerStyle()
        }
        // Batch delete confirmation
        .alert("Delete \(taskListVM.selectedCount) task\(taskListVM.selectedCount == 1 ? "" : "s")?", isPresented: $taskListVM.showBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task { await taskListVM.batchDeleteTasks() }
            }
        } message: {
            Text("This will permanently delete the selected tasks and their commitments.")
        }
        // Batch move category sheet
        .sheet(isPresented: $taskListVM.showBatchMovePicker) {
            BatchMoveCategorySheet(
                viewModel: taskListVM,
                onMoveToProject: { projectId in
                    await taskListVM.batchMoveToProject(projectId)
                }
            )
            .drawerStyle()
        }
        // Batch commit sheet
        .sheet(isPresented: $taskListVM.showBatchCommitSheet) {
            BatchCommitSheet(viewModel: taskListVM)
                .drawerStyle()
        }
        // Create project alert
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
        // Create list alert
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
            taskListVM.commitmentFilter = .uncommitted

            isLoading = true
            async let t: () = fetchTasks()
            async let p: () = fetchProjects()
            _ = await (t, p)
            isLoading = false
        }
    }

    private func fetchTasks() async {
        await taskListVM.fetchTasks()
        await taskListVM.fetchCategories()
        await taskListVM.fetchCommittedTaskIds()
    }

    private func fetchProjects() async {
        await projectsVM.fetchProjects()
    }

    // MARK: - Item List

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

    private var itemList: some View {
        List {
            // Tasks (excluding project-contained)
            ForEach(standaloneTaskDisplayItems) { item in
                switch item {
                case .priorityHeader:
                    EmptyView()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                case .task(let task):
                    FlatTaskRow(
                        task: task,
                        viewModel: taskListVM,
                        isEditMode: taskListVM.isEditMode,
                        isSelected: taskListVM.selectedTaskIds.contains(task.id),
                        onSelectToggle: { taskListVM.toggleTaskSelection(task.id) }
                    )
                    .padding(.leading, task.parentTaskId != nil ? 32 : 0)
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                    .listRowBackground(Color.clear)
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] - 12 }
                    .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] + 12 }

                case .addSubtaskRow(let parentId):
                    InlineAddRow(
                        placeholder: "Subtask title",
                        buttonLabel: "Add subtask",
                        onSubmit: { title in await taskListVM.createSubtask(title: title, parentId: parentId) },
                        isAnyAddFieldActive: $isInlineAddFocused,
                        verticalPadding: 12
                    )
                    .padding(.leading, 32)
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                    .listRowBackground(Color.clear)

                case .addTaskRow:
                    EmptyView()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
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
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissOverlay(isActive: $isInlineAddFocused)
        .refreshable {
            await withCheckedContinuation { continuation in
                _Concurrency.Task { @MainActor in
                    await fetchTasks()
                    continuation.resume()
                }
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

    @ViewBuilder
    private var activeAddBar: some View {
        switch addBarMode {
        case .task: addTaskBar
        case .list: addListBar
        case .project: addProjectBar
        }
    }

    // MARK: - Add Task Bar

    private var categoryPillLabel: String {
        if let categoryId = addTaskCategoryId,
           let category = taskListVM.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private var addTaskBar: some View {
        VStack(spacing: 0) {
            TextField("Create a new task", text: $addTaskTitle)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .task)
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

            if addTaskCommitExpanded {
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

                    let hasDateChanges = addTaskDates != addTaskDatesSnapshot
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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

            if !addTaskCommitExpanded {
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

            if addTaskOptionsExpanded && !addTaskCommitExpanded {
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

        addBarTitleFocus = .task
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
        // Clear task state
        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskCategoryId = nil
        addTaskPriority = .low
        addTaskOptionsExpanded = false
        addTaskCommitExpanded = false
        addTaskDates = []
        hasGeneratedBreakdown = false
        focusedSubtaskId = nil

        // Clear list state
        addListTitle = ""
        addListItems = []
        addListCategoryId = nil
        addListCommitExpanded = false
        addListOptionsExpanded = false
        addListPriority = .low
        addListDates = []
        focusedListItemId = nil

        // Clear project state
        addProjectTitle = ""
        addProjectDraftTasks = []
        addProjectCategoryId = nil
        addProjectCommitExpanded = false
        addProjectOptionsExpanded = false
        addProjectPriority = .low
        addProjectDates = []
        focusedProjectTaskId = nil

        addBarTitleFocus = nil
        showingAddBar = false
    }

    // MARK: - Add List Bar

    private var listCategoryPillLabel: String {
        if let categoryId = addListCategoryId,
           let category = listsVM.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private var addListBar: some View {
        VStack(spacing: 0) {
            TextField("Create a new list", text: $addListTitle)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .list)
                .submitLabel(.return)
                .onSubmit { saveList() }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

            DraftSubtaskListEditor(
                subtasks: $addListItems,
                focusedSubtaskId: $focusedListItemId,
                onAddNew: { addNewListItem() },
                placeholder: "Item"
            )

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
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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

            if addListOptionsExpanded && !addListCommitExpanded {
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

    // MARK: - Add List Helpers

    private func saveList() {
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

        addBarTitleFocus = .list
        focusedListItemId = nil

        addListTitle = ""
        addListItems = []
        addListDates = []
        addListCommitExpanded = false
        addListOptionsExpanded = false
        addListPriority = .low

        _Concurrency.Task { @MainActor in
            await listsVM.createList(title: title, categoryId: categoryId, priority: priority)

            if let createdList = listsVM.lists.first {
                for itemTitle in itemTitles {
                    await listsVM.createItem(title: itemTitle, listId: createdList.id)
                }
                if !itemTitles.isEmpty {
                    listsVM.expandedLists.insert(createdList.id)
                }

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

            // Navigate back to Home after list creation
            showingAddBar = false
            dismiss()
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

    // MARK: - Add Project Bar

    private var projectCategoryPillLabel: String {
        if let categoryId = addProjectCategoryId,
           let category = projectsVM.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private var addProjectBar: some View {
        VStack(spacing: 0) {
            TextField("Create a new project", text: $addProjectTitle)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($addBarTitleFocus, equals: .project)
                .submitLabel(.return)
                .onSubmit { saveProject() }
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 10)

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
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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

            if addProjectOptionsExpanded && !addProjectCommitExpanded {
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

    // MARK: - Add Project Helpers

    private func saveProject() {
        let title = addProjectTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }

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

            // Navigate back to Home after project creation
            showingAddBar = false
            dismiss()
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
}
