//
//  BraindumpView.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct PendingScheduleInfo {
    let taskId: UUID
    let userId: UUID
    var timeframe: Timeframe
    var section: Section
    var dates: Set<Date>
}

struct BraindumpView: View {
    @StateObject private var taskListVM: TaskListViewModel
    @StateObject private var projectsVM: ProjectsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isInlineAddFocused = false
    @State private var isLoading = false

    // Pending schedule state
    @State private var pendingSchedules: [UUID: PendingScheduleInfo] = [:]
    @State private var pendingCompletions: Set<UUID> = []
    @State private var dismissedPendingBanner = false

    // Batch create alerts
    @State private var showCreateProjectAlert = false
    @State private var showCreateListAlert = false
    @State private var newProjectTitle = ""
    @State private var newListTitle = ""

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

    init(authService: AuthService) {
        _taskListVM = StateObject(wrappedValue: TaskListViewModel(authService: authService))
        _projectsVM = StateObject(wrappedValue: ProjectsViewModel(authService: authService))
    }

    private var isAddTaskTitleEmpty: Bool {
        addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Tasks not in a project (excluding pending scheduled/completed)
    private var standaloneUncompletedTasks: [FocusTask] {
        taskListVM.uncompletedTasks.filter {
            $0.projectId == nil && $0.categoryId == nil
            && !pendingSchedules.keys.contains($0.id) && !pendingCompletions.contains($0.id)
        }
    }

    /// Tasks that have been scheduled or completed but not yet scheduled
    private var pendingTasks: [FocusTask] {
        taskListVM.uncompletedTasks.filter {
            $0.projectId == nil && $0.categoryId == nil
            && (pendingSchedules.keys.contains($0.id) || pendingCompletions.contains($0.id))
        }
    }

    private var isEmpty: Bool {
        standaloneUncompletedTasks.isEmpty && pendingTasks.isEmpty
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.inter(size: 22, weight: .regular))
                        .foregroundColor(.primary)

                    Text("Braindump")
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
                        Text("No braindump items")
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

                    addTaskBar
                        .padding(.bottom, 8)
                        .contentShape(Rectangle())
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .onDisappear {
            savePendingSchedules()
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
            TaskDetailsDrawer(
                task: task,
                viewModel: taskListVM,
                categories: taskListVM.categories,
                pendingSchedule: pendingSchedules[task.id],
                onSchedule: { timeframe, section, dates in
                    guard !dates.isEmpty else { return }
                    pendingSchedules[task.id] = PendingScheduleInfo(
                        taskId: task.id, userId: task.userId,
                        timeframe: timeframe, section: section, dates: dates
                    )
                    dismissedPendingBanner = false
                },
                onClearSchedule: {
                    pendingSchedules.removeValue(forKey: task.id)
                }
            )
            .drawerStyle()
        }
        .sheet(item: $taskListVM.selectedTaskForSchedule) { task in
            ScheduleSelectionSheet(
                task: task,
                focusViewModel: focusViewModel,
                onSchedule: { timeframe, section, dates in
                    guard !dates.isEmpty else { return }
                    pendingSchedules[task.id] = PendingScheduleInfo(
                        taskId: task.id, userId: task.userId,
                        timeframe: timeframe, section: section, dates: dates
                    )
                    dismissedPendingBanner = false
                },
                pendingSchedule: pendingSchedules[task.id],
                onClearSchedule: {
                    pendingSchedules.removeValue(forKey: task.id)
                },
                onSomeday: {
                    _Concurrency.Task { await taskListVM.moveTaskToSomeday(task) }
                },
                isSomedayTask: task.categoryId == taskListVM.somedayCategory?.id
            )
            .drawerStyle()
        }
        // Batch delete confirmation
        .alert("Delete \(taskListVM.selectedCount) task\(taskListVM.selectedCount == 1 ? "" : "s")?", isPresented: $taskListVM.showBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task { await taskListVM.batchDeleteTasks() }
            }
        } message: {
            Text("This will permanently delete the selected tasks and their schedules.")
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
        // Batch schedule sheet
        .sheet(isPresented: $taskListVM.showBatchScheduleSheet) {
            BatchScheduleSheet(
                viewModel: taskListVM,
                onBatchSchedule: { tasks, timeframe, section, dates in
                    guard !dates.isEmpty else { return }
                    for task in tasks {
                        pendingSchedules[task.id] = PendingScheduleInfo(
                            taskId: task.id, userId: task.userId,
                            timeframe: timeframe, section: section, dates: dates
                        )
                    }
                    dismissedPendingBanner = false
                }
            )
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
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
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
                        // Sort By submenu
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
        .onChange(of: taskListVM.tasks) { _, _ in
            // Clean up pending entries for tasks that were deleted
            let currentIds = Set(taskListVM.uncompletedTasks.map { $0.id })
            for taskId in pendingSchedules.keys {
                if !currentIds.contains(taskId) {
                    pendingSchedules.removeValue(forKey: taskId)
                }
            }
            for taskId in pendingCompletions {
                if !currentIds.contains(taskId) {
                    pendingCompletions.remove(taskId)
                }
            }
        }
        .task {
            taskListVM.scheduleFilter = .unscheduled

            isLoading = true
            async let t: () = fetchTasks()
            async let p: () = fetchProjects()
            _ = await (t, p)
            isLoading = false
        }
    }

    private func fetchTasks() async {
        // Fetch scheduled IDs first so the unscheduled filter works
        // immediately when tasks arrive — prevents flash of scheduled items.
        async let c: () = taskListVM.fetchScheduledTaskIds()
        async let cats: () = taskListVM.fetchCategories()
        _ = await (c, cats)
        await taskListVM.fetchTasks()
    }

    private func fetchProjects() async {
        await projectsVM.fetchProjects()
    }

    private func handleBraindumpMove(from source: IndexSet, to destination: Int) {
        let braindumpItems = standaloneTaskDisplayItems
        let fullItems = taskListVM.flattenedDisplayItems

        guard let fromIdx = source.first else { return }
        let movedItem = braindumpItems[fromIdx]

        // Map source index to full list
        guard let fullFromIdx = fullItems.firstIndex(where: { $0.id == movedItem.id }) else { return }

        // Map destination index to full list
        let fullDestIdx: Int
        if destination < braindumpItems.count {
            let destItem = braindumpItems[destination]
            guard let idx = fullItems.firstIndex(where: { $0.id == destItem.id }) else { return }
            fullDestIdx = idx
        } else if let lastItem = braindumpItems.last,
                  let lastFullIdx = fullItems.firstIndex(where: { $0.id == lastItem.id }) {
            fullDestIdx = lastFullIdx + 1
        } else {
            return
        }

        taskListVM.handleFlatMove(from: IndexSet(integer: fullFromIdx), to: fullDestIdx)
    }

    private func savePendingSchedules() {
        let schedulesToSave = pendingSchedules
        let completionsToSave = pendingCompletions
        guard !schedulesToSave.isEmpty || !completionsToSave.isEmpty else { return }

        _Concurrency.Task { @MainActor in
            // Save pending schedules
            if !schedulesToSave.isEmpty {
                let scheduleRepository = ScheduleRepository()
                for (_, schedule) in schedulesToSave {
                    for date in schedule.dates {
                        let schedule = Schedule(
                            userId: schedule.userId,
                            taskId: schedule.taskId,
                            timeframe: schedule.timeframe,
                            section: schedule.section,
                            scheduleDate: Calendar.current.startOfDay(for: date),
                            sortOrder: 0
                        )
                        _ = try? await scheduleRepository.createSchedule(schedule)
                    }
                }
            }

            // Save pending completions
            if !completionsToSave.isEmpty {
                for taskId in completionsToSave {
                    if let task = taskListVM.uncompletedTasks.first(where: { $0.id == taskId }) {
                        await taskListVM.toggleCompletion(task)
                    }
                }
            }

            await taskListVM.fetchScheduledTaskIds()
            // Clear pending after scheduled IDs are refreshed so tasks
            // go straight from pending section to hidden — no flash.
            pendingSchedules.removeAll()
            pendingCompletions.removeAll()
            await focusViewModel.fetchSchedules()
        }
    }

    // MARK: - Item List

    /// Flattened task display items excluding project-contained, categorized, and pending tasks
    private var standaloneTaskDisplayItems: [FlatDisplayItem] {
        let excludedTaskIds = Set(taskListVM.uncompletedTasks.filter { $0.projectId != nil || $0.categoryId != nil }.map { $0.id })
        let pendingTaskIds = Set(pendingSchedules.keys).union(pendingCompletions)
        return taskListVM.flattenedDisplayItems.filter { item in
            switch item {
            case .task(let task): return task.projectId == nil && task.categoryId == nil && !pendingTaskIds.contains(task.id)
            case .addSubtaskRow(let parentId): return !excludedTaskIds.contains(parentId) && !pendingTaskIds.contains(parentId)
            default: return true
            }
        }
    }

    private var itemList: some View {
        List {
            // Tasks (excluding project-contained)
            ForEach(standaloneTaskDisplayItems) { item in
                switch item {
                case .priorityHeader(let priority):
                    PrioritySectionHeader(
                        priority: priority,
                        count: standaloneUncompletedTasks.filter { $0.priority == priority }.count,
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
                    .moveDisabled(true)

                case .task(let task):
                    FlatTaskRow(
                        task: task,
                        viewModel: taskListVM,
                        isEditMode: taskListVM.isEditMode,
                        isSelected: taskListVM.selectedTaskIds.contains(task.id),
                        onSelectToggle: { taskListVM.toggleTaskSelection(task.id) },
                        onToggleCompletion: { t in
                            pendingCompletions.insert(t.id)
                            dismissedPendingBanner = false
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
                    .moveDisabled(true)

                case .addTaskRow:
                    EmptyView()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .moveDisabled(true)
                }
            }
            .onMove(perform: handleBraindumpMove)

            // Pending scheduled section
            if !pendingTasks.isEmpty {
                if !dismissedPendingBanner {
                    HStack {
                        Text("\(pendingTasks.count) to-do\(pendingTasks.count == 1 ? "" : "s") moved out of the Inbox")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button {
                            savePendingSchedules()
                        } label: {
                            Text("OK")
                                .font(.inter(.subheadline, weight: .semiBold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.pillBackground, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                ForEach(pendingTasks) { task in
                    FlatTaskRow(
                        task: task,
                        viewModel: taskListVM,
                        isEditMode: false,
                        isSelected: false,
                        onSelectToggle: nil,
                        onToggleCompletion: { t in
                            if pendingCompletions.contains(t.id) {
                                // Uncomplete: remove from pending, task goes back to main list
                                pendingCompletions.remove(t.id)
                            } else {
                                // Complete: add to pending completions
                                pendingCompletions.insert(t.id)
                            }
                        },
                        appearCompleted: pendingCompletions.contains(task.id) ? true : nil
                    )
                    .opacity(0.5)
                    .padding(.leading, task.parentTaskId != nil ? 32 : 0)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(task.parentTaskId != nil ? .visible : .hidden)
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
        addTaskScheduleExpanded = false
        addTaskDates = []
        hasGeneratedBreakdown = false
        focusedSubtaskId = nil
        addBarTitleFocused = false
        showingAddBar = false
    }

}
