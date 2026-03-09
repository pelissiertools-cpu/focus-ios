//
//  TodayView.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct TodayView: View {
    @StateObject private var taskListVM: TaskListViewModel
    @StateObject private var listsVM: ListsViewModel
    @StateObject private var projectsVM: ProjectsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isInlineAddFocused = false
    @State private var showingAddBar = false
    @State private var isLoading = false
    @State private var todaySchedules: [UUID: (scheduleId: UUID, sortOrder: Int)] = [:]
    @State private var scheduleById: [UUID: Schedule] = [:]
    @State private var selectedScheduleForReschedule: Schedule?
    @State private var overdueScheduleDates: [UUID: Date] = [:]
    @State private var focusTaskIds: Set<UUID> = []

    // Navigation
    @State private var selectedListForNavigation: FocusTask?
    @State private var selectedProjectForNavigation: FocusTask?

    private let authService: AuthService
    private let scheduleRepository = ScheduleRepository()

    init(authService: AuthService) {
        self.authService = authService
        _taskListVM = StateObject(wrappedValue: TaskListViewModel(authService: authService))
        _listsVM = StateObject(wrappedValue: ListsViewModel(authService: authService))
        _projectsVM = StateObject(wrappedValue: ProjectsViewModel(authService: authService))
    }

    private var todayScheduledIds: Set<UUID> {
        Set(todaySchedules.keys)
    }

    private var scheduledLists: [FocusTask] {
        listsVM.lists
            .filter { !$0.isCompleted && !$0.isCleared }
            .filter { todayScheduledIds.contains($0.id) }
    }

    private var scheduledProjects: [FocusTask] {
        projectsVM.projects
            .filter { !$0.isCompleted && !$0.isCleared }
            .filter { todayScheduledIds.contains($0.id) }
    }

    private var allTodayEntries: [TodayItemEntry] {
        var entries: [TodayItemEntry] = []

        for task in taskListVM.uncompletedTasks where task.projectId == nil {
            if let schedule = todaySchedules[task.id] {
                entries.append(.task(task, scheduleId: schedule.scheduleId, sortOrder: schedule.sortOrder))
            }
        }

        for list in scheduledLists {
            if let schedule = todaySchedules[list.id] {
                entries.append(.list(list, scheduleId: schedule.scheduleId, sortOrder: schedule.sortOrder))
            }
        }

        for project in scheduledProjects {
            if let schedule = todaySchedules[project.id] {
                entries.append(.project(project, scheduleId: schedule.scheduleId, sortOrder: schedule.sortOrder))
            }
        }

        return TodayItemEntry.sortForDisplay(entries)
    }

    private var focusEntries: [TodayItemEntry] {
        allTodayEntries.filter { focusTaskIds.contains($0.id) }
    }

    private var todoEntries: [TodayItemEntry] {
        allTodayEntries.filter { !focusTaskIds.contains($0.id) }
    }

    private var flattenedTodayItems: [TodayFlatItem] {
        var result: [TodayFlatItem] = []

        // Main Focus section
        result.append(.focusSectionHeader)
        for entry in focusEntries {
            result.append(.item(entry))
            appendExpandedSubtasks(for: entry, into: &result)
        }
        result.append(.focusInlineAdd)
        result.append(.focusDivider)

        // Rest of items
        for entry in todoEntries {
            result.append(.item(entry))
            appendExpandedSubtasks(for: entry, into: &result)
        }

        if todoEntries.isEmpty {
            result.append(.todoDropPlaceholder)
        }

        result.append(.bottomSpacer)
        return result
    }

    private func appendExpandedSubtasks(for entry: TodayItemEntry, into result: inout [TodayFlatItem]) {
        if case .task(let task, _, _) = entry,
           taskListVM.expandedTasks.contains(task.id) {
            let subtasks = taskListVM.getUncompletedSubtasks(for: task.id)
                + taskListVM.getCompletedSubtasks(for: task.id)
            for subtask in subtasks {
                result.append(.subtask(subtask, parentId: task.id))
            }
            result.append(.inlineAddSubtask(parentId: task.id))
        }
    }

    private var isEmpty: Bool {
        allTodayEntries.isEmpty
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: AppStyle.Spacing.compact) {
                    Image(systemName: "sun.max")
                        .font(.helveticaNeue(size: 15, weight: .medium))
                        .foregroundColor(.focusBlue)
                        .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                        .background(Color.todayBadge, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))

                    Text("Today")
                        .pageTitleStyle()
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.horizontal, AppStyle.Spacing.page)
                .padding(.top, AppStyle.Spacing.section)
                .padding(.bottom, AppStyle.Spacing.comfortable)

                if isLoading && isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    itemList
                }
            }

            if !showingAddBar {
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
            }

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

                    AddTodayTaskBar(
                        taskListVM: taskListVM,
                        authService: authService,
                        onSaved: {
                            _Concurrency.Task {
                                await fetchTodayData()
                            }
                        }
                    )
                    .padding(.bottom, AppStyle.Spacing.compact)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(51)
            }
        }
        .sheet(item: $taskListVM.selectedTaskForDetails) { task in
            TaskDetailsDrawer(
                task: task,
                viewModel: taskListVM,
                categories: taskListVM.categories
            )
            .drawerStyle()
        }
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
        .sheet(item: $selectedScheduleForReschedule) { schedule in
            RescheduleSheet(schedule: schedule, focusViewModel: focusViewModel)
                .drawerStyle()
        }
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
        .task {
            // Populate from cache for instant display
            let cache = AppDataCache.shared
            if let cachedDate = cache.todayScheduleDate,
               Calendar.current.isDateInToday(cachedDate) {
                populateScheduleState(
                    focusSchedules: cache.todayFocusSchedules,
                    todoSchedules: cache.todayTodoSchedules,
                    overdueSchedules: cache.overdueSchedules
                )
            }

            // Only show loading if no cached data available
            if isEmpty {
                isLoading = true
            }

            await fetchTodayData()
            isLoading = false
        }
    }

    // MARK: - Data Fetching

    private func populateScheduleState(focusSchedules: [Schedule], todoSchedules: [Schedule], overdueSchedules: [Schedule]) {
        let allSchedules = focusSchedules + todoSchedules
        var schedules: [UUID: (scheduleId: UUID, sortOrder: Int)] = [:]
        var byId: [UUID: Schedule] = [:]
        var focusIds: Set<UUID> = []
        for s in allSchedules {
            schedules[s.taskId] = (scheduleId: s.id, sortOrder: s.sortOrder)
            byId[s.id] = s
        }
        for s in focusSchedules {
            focusIds.insert(s.taskId)
        }

        var overdueDates: [UUID: Date] = [:]
        for (index, s) in overdueSchedules.enumerated() {
            guard schedules[s.taskId] == nil else { continue }
            schedules[s.taskId] = (scheduleId: s.id, sortOrder: -1000 + index)
            byId[s.id] = s
            overdueDates[s.taskId] = s.scheduleDate
        }
        overdueScheduleDates = overdueDates

        todaySchedules = schedules
        scheduleById = byId
        focusTaskIds = focusIds

        taskListVM.scheduledTaskIds = Set(schedules.keys)
        taskListVM.scheduleFilter = .scheduled
    }

    private func fetchTodayData() async {
        do {
            let focusSchedules = try await scheduleRepository.fetchSchedules(
                timeframe: .daily,
                date: Date(),
                section: .focus
            )
            let todoSchedules = try await scheduleRepository.fetchSchedules(
                timeframe: .daily,
                date: Date(),
                section: .todo
            )
            let overdueSchedules = try await scheduleRepository.fetchOverdueSchedules()

            populateScheduleState(
                focusSchedules: focusSchedules,
                todoSchedules: todoSchedules,
                overdueSchedules: overdueSchedules
            )

            // Update cache
            let cache = AppDataCache.shared
            cache.todayFocusSchedules = focusSchedules
            cache.todayTodoSchedules = todoSchedules
            cache.overdueSchedules = overdueSchedules
            cache.todayScheduleDate = Date()
        } catch {
            todaySchedules = [:]
            overdueScheduleDates = [:]
            taskListVM.scheduledTaskIds = []
            taskListVM.scheduleFilter = .scheduled
        }

        await taskListVM.fetchCategories()
        async let t: () = taskListVM.fetchTasks()
        async let l: () = listsVM.fetchLists()
        async let p: () = projectsVM.fetchProjects()
        _ = await (t, l, p)
    }

    // MARK: - Focus Task Creation

    private func createFocusTask(title: String) async {
        guard let userId = authService.currentUser?.id else { return }
        let taskRepo = TaskRepository()
        do {
            let newTask = FocusTask(
                userId: userId,
                title: title,
                type: .task,
                isCompleted: false,
                isInLibrary: true
            )
            let created = try await taskRepo.createTask(newTask)

            let maxSort = focusEntries.map { $0.sortOrder }.max() ?? -1
            let schedule = Schedule(
                userId: userId,
                taskId: created.id,
                timeframe: .daily,
                section: .focus,
                scheduleDate: Date(),
                sortOrder: maxSort + 1
            )
            let createdSchedule = try await scheduleRepository.createSchedule(schedule)

            todaySchedules[created.id] = (scheduleId: createdSchedule.id, sortOrder: createdSchedule.sortOrder)
            scheduleById[createdSchedule.id] = createdSchedule
            focusTaskIds.insert(created.id)
            taskListVM.scheduledTaskIds.insert(created.id)
            await taskListVM.fetchTasks()
        } catch {
            // silently fail
        }
    }

    // MARK: - Item List

    private var itemList: some View {
        List {
            ForEach(flattenedTodayItems) { flatItem in
                switch flatItem {
                case .focusSectionHeader:
                    Text("Main Focus")
                        .font(.inter(.headline, weight: .bold))
                        .foregroundColor(.focusBlue)
                        .padding(.top, AppStyle.Spacing.section)
                        .listRowInsets(AppStyle.Insets.row)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)

                case .item(let entry):
                    todayItemRow(entry)

                case .subtask(let subtask, _):
                    FlatTaskRow(
                        task: subtask,
                        viewModel: taskListVM,
                        isEditMode: false,
                        isSelected: false,
                        onSelectToggle: nil,
                        onToggleCompletion: nil
                    )
                    .padding(.leading, 32)
                    .listRowInsets(AppStyle.Insets.row)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.visible)
                    .moveDisabled(true)

                case .inlineAddSubtask(let parentId):
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
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                case .focusInlineAdd:
                    InlineAddRow(
                        placeholder: "Add to focus",
                        buttonLabel: "Add task",
                        onSubmit: { title in await createFocusTask(title: title) },
                        isAnyAddFieldActive: $isInlineAddFocused,
                        verticalPadding: AppStyle.Spacing.compact,
                        accentColor: .focusBlue
                    )
                    .listRowInsets(AppStyle.Insets.row)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                case .focusDivider:
                    Rectangle()
                        .fill(Color.focusBlue)
                        .frame(height: 1)
                        .listRowInsets(EdgeInsets(top: AppStyle.Spacing.compact, leading: AppStyle.Spacing.page, bottom: AppStyle.Spacing.compact, trailing: AppStyle.Spacing.page))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .moveDisabled(true)

                case .todoDropPlaceholder:
                    Text("Drop items here")
                        .font(.inter(.subheadline))
                        .foregroundColor(.secondary.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppStyle.Spacing.page)
                        .listRowInsets(AppStyle.Insets.row)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                case .bottomSpacer:
                    Color.clear
                        .frame(height: 100)
                        .listRowInsets(AppStyle.Insets.zero)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .moveDisabled(true)
                }
            }
            .onMove { from, to in
                handleMove(from: from, to: to)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .keyboardDismissOverlay(isActive: $isInlineAddFocused)
    }

    // MARK: - Item Row

    @ViewBuilder
    private func todayItemRow(_ entry: TodayItemEntry) -> some View {
        Group {
            switch entry {
            case .task(let task, let scheduleId, _):
                FlatTaskRow(
                    task: task,
                    viewModel: taskListVM,
                    isEditMode: false,
                    isSelected: false,
                    onSelectToggle: nil,
                    onToggleCompletion: { t in
                        taskListVM.requestToggleCompletion(t)
                    },
                    onReschedule: {
                        selectedScheduleForReschedule = scheduleById[scheduleId]
                    },
                    onPushToTomorrow: {
                        if let schedule = scheduleById[scheduleId] {
                            _Concurrency.Task {
                                let _ = await focusViewModel.pushScheduleToNext(schedule)
                                await fetchTodayData()
                            }
                        }
                    },
                    onUnschedule: {
                        if let schedule = scheduleById[scheduleId] {
                            _Concurrency.Task {
                                await focusViewModel.removeSchedule(schedule)
                                await fetchTodayData()
                            }
                        }
                    },
                    overdueDate: overdueScheduleDates[task.id]
                )

            case .project(let project, let scheduleId, _):
                TodayProjectRow(
                    project: project,
                    overdueDate: overdueScheduleDates[project.id],
                    onTap: { selectedProjectForNavigation = project },
                    onEdit: { projectsVM.selectedProjectForDetails = project },
                    onReschedule: { selectedScheduleForReschedule = scheduleById[scheduleId] },
                    onPushToTomorrow: {
                        if let schedule = scheduleById[scheduleId] {
                            _Concurrency.Task {
                                let _ = await focusViewModel.pushScheduleToNext(schedule)
                                await fetchTodayData()
                            }
                        }
                    },
                    onUnschedule: {
                        if let schedule = scheduleById[scheduleId] {
                            _Concurrency.Task {
                                await focusViewModel.removeSchedule(schedule)
                                await fetchTodayData()
                            }
                        }
                    }
                )

            case .list(let list, let scheduleId, _):
                TodayListRow(
                    list: list,
                    overdueDate: overdueScheduleDates[list.id],
                    onTap: { selectedListForNavigation = list },
                    onEdit: { listsVM.selectedListForDetails = list },
                    onReschedule: { selectedScheduleForReschedule = scheduleById[scheduleId] },
                    onPushToTomorrow: {
                        if let schedule = scheduleById[scheduleId] {
                            _Concurrency.Task {
                                let _ = await focusViewModel.pushScheduleToNext(schedule)
                                await fetchTodayData()
                            }
                        }
                    },
                    onUnschedule: {
                        if let schedule = scheduleById[scheduleId] {
                            _Concurrency.Task {
                                await focusViewModel.removeSchedule(schedule)
                                await fetchTodayData()
                            }
                        }
                    }
                )
            }
        }
        .listRowInsets(AppStyle.Insets.row)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Reorder

    private func handleMove(from source: IndexSet, to destination: Int) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            performMove(from: source, to: destination)
        }
    }

    private func performMove(from source: IndexSet, to destination: Int) {
        let flat = flattenedTodayItems
        guard let fromIdx = source.first else { return }

        guard case .item(let movedEntry) = flat[fromIdx] else { return }

        // Find the divider index to determine focus vs todo zones
        let dividerIdx = flat.firstIndex(where: { $0.id == "focus-divider" }) ?? 0

        let itemEntries = flat.enumerated().compactMap { (i, flatItem) -> (flatIdx: Int, entry: TodayItemEntry)? in
            guard case .item(let entry) = flatItem else { return nil }
            return (i, entry)
        }

        guard let itemFrom = itemEntries.firstIndex(where: { $0.entry.id == movedEntry.id }) else { return }

        var itemTo = itemEntries.count
        for (ci, entry) in itemEntries.enumerated() {
            if destination <= entry.flatIdx {
                itemTo = ci
                break
            }
        }
        if itemTo > itemFrom { itemTo = min(itemTo, itemEntries.count) }

        guard itemFrom != itemTo && itemFrom + 1 != itemTo else { return }

        var items = itemEntries.map { $0.entry }
        items.move(fromOffsets: IndexSet(integer: itemFrom), toOffset: itemTo)

        // Determine which items land in focus vs todo based on divider position
        // Focus items: those whose flatIdx is before the divider
        let focusItemCount = itemEntries.filter { $0.flatIdx < dividerIdx }.count
        // After the move, the first focusItemCount items are focus, rest are todo
        // But if destination crosses the divider, the count shifts by 1
        let movedFromFocus = focusTaskIds.contains(movedEntry.id)
        let movedToFocus = destination <= dividerIdx

        // Update focusTaskIds for the moved item
        if movedFromFocus && !movedToFocus {
            focusTaskIds.remove(movedEntry.id)
        } else if !movedFromFocus && movedToFocus {
            focusTaskIds.insert(movedEntry.id)
        }

        // Rebuild sort orders: focus items get their own sequence, todo items get their own
        let newFocusItems = items.filter { focusTaskIds.contains($0.id) }
        let newTodoItems = items.filter { !focusTaskIds.contains($0.id) }

        var updates: [(id: UUID, sortOrder: Int, section: Section)] = []
        for (index, entry) in newFocusItems.enumerated() {
            let newOrder = index + 1
            updates.append((id: entry.scheduleId, sortOrder: newOrder, section: .focus))
            todaySchedules[entry.id] = (scheduleId: entry.scheduleId, sortOrder: newOrder)
        }
        for (index, entry) in newTodoItems.enumerated() {
            let newOrder = index + 1
            updates.append((id: entry.scheduleId, sortOrder: newOrder, section: .todo))
            todaySchedules[entry.id] = (scheduleId: entry.scheduleId, sortOrder: newOrder)
        }

        _Concurrency.Task {
            try? await scheduleRepository.updateScheduleSortOrdersAndSections(updates)
        }
    }
}

// MARK: - Today Project Row

private struct TodayProjectRow: View {
    let project: FocusTask
    var overdueDate: Date? = nil
    var onTap: () -> Void
    var onEdit: () -> Void
    var onReschedule: () -> Void
    var onPushToTomorrow: () -> Void
    var onUnschedule: () -> Void

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            Image(systemName: "folder")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: AppStyle.Layout.pillButton)
            VStack(alignment: .leading, spacing: AppStyle.Spacing.tiny) {
                Text(project.title)
                    .font(.inter(.body))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let overdueDate {
                    Text(OverdueDateFormatter.format(overdueDate))
                        .font(.inter(.caption))
                        .foregroundColor(.red)
                }
            }
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
            ContextMenuItems.rescheduleButton { onReschedule() }
            ContextMenuItems.pushToTomorrowButton { onPushToTomorrow() }
            ContextMenuItems.unscheduleButton { onUnschedule() }
        }
    }
}

// MARK: - Today List Row

private struct TodayListRow: View {
    let list: FocusTask
    var overdueDate: Date? = nil
    var onTap: () -> Void
    var onEdit: () -> Void
    var onReschedule: () -> Void
    var onPushToTomorrow: () -> Void
    var onUnschedule: () -> Void

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            Image(systemName: "list.bullet")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: AppStyle.Layout.pillButton)
            VStack(alignment: .leading, spacing: AppStyle.Spacing.tiny) {
                Text(list.title)
                    .font(.inter(.body))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let overdueDate {
                    Text(OverdueDateFormatter.format(overdueDate))
                        .font(.inter(.caption))
                        .foregroundColor(.red)
                }
            }
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
            ContextMenuItems.rescheduleButton { onReschedule() }
            ContextMenuItems.pushToTomorrowButton { onPushToTomorrow() }
            ContextMenuItems.unscheduleButton { onUnschedule() }
        }
    }
}

// MARK: - Today Flat Item

private enum TodayFlatItem: Identifiable {
    case item(TodayItemEntry)
    case subtask(FocusTask, parentId: UUID)
    case inlineAddSubtask(parentId: UUID)
    case focusSectionHeader
    case focusInlineAdd
    case focusDivider
    case todoDropPlaceholder
    case bottomSpacer

    var id: String {
        switch self {
        case .item(let e): return "item-\(e.id.uuidString)"
        case .subtask(let t, _): return "subtask-\(t.id.uuidString)"
        case .inlineAddSubtask(let pid): return "add-subtask-\(pid.uuidString)"
        case .focusSectionHeader: return "focus-section-header"
        case .focusInlineAdd: return "focus-inline-add"
        case .focusDivider: return "focus-divider"
        case .todoDropPlaceholder: return "todo-drop-placeholder"
        case .bottomSpacer: return "bottom-spacer"
        }
    }
}

// MARK: - Today Item Entry

private enum TodayItemEntry: Identifiable {
    case task(FocusTask, scheduleId: UUID, sortOrder: Int)
    case project(FocusTask, scheduleId: UUID, sortOrder: Int)
    case list(FocusTask, scheduleId: UUID, sortOrder: Int)

    var id: UUID {
        switch self {
        case .task(let t, _, _): return t.id
        case .project(let p, _, _): return p.id
        case .list(let l, _, _): return l.id
        }
    }

    var scheduleId: UUID {
        switch self {
        case .task(_, let sid, _), .project(_, let sid, _), .list(_, let sid, _): return sid
        }
    }

    var sortOrder: Int {
        switch self {
        case .task(_, _, let so), .project(_, _, let so), .list(_, _, let so): return so
        }
    }

    var createdDate: Date {
        switch self {
        case .task(let t, _, _): return t.createdDate
        case .project(let p, _, _): return p.createdDate
        case .list(let l, _, _): return l.createdDate
        }
    }

    private var typeSortOrder: Int {
        switch self {
        case .task: return 0
        case .project: return 1
        case .list: return 2
        }
    }

    static func sortForDisplay(_ items: [TodayItemEntry]) -> [TodayItemEntry] {
        let allZero = items.allSatisfy { $0.sortOrder == 0 }
        if allZero {
            return items.sorted {
                if $0.typeSortOrder != $1.typeSortOrder { return $0.typeSortOrder < $1.typeSortOrder }
                if $0.createdDate != $1.createdDate { return $0.createdDate < $1.createdDate }
                return $0.id.uuidString < $1.id.uuidString
            }
        } else {
            return items.sorted { a, b in
                if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
                if a.typeSortOrder != b.typeSortOrder { return a.typeSortOrder < b.typeSortOrder }
                if a.createdDate != b.createdDate { return a.createdDate < b.createdDate }
                return a.id.uuidString < b.id.uuidString
            }
        }
    }
}

// MARK: - Overdue Date Formatter

enum OverdueDateFormatter {
    static func format(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let scheduleDay = calendar.startOfDay(for: date)

        if calendar.isDate(scheduleDay, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
    }
}
