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
    @State private var isLoading = false
    @State private var todaySchedules: [UUID: (scheduleId: UUID, sortOrder: Int)] = [:]

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

    private var flattenedTodayItems: [TodayFlatItem] {
        var result: [TodayFlatItem] = []

        for entry in allTodayEntries {
            result.append(.item(entry))

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

        result.append(.bottomSpacer)
        return result
    }

    private var isEmpty: Bool {
        allTodayEntries.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "sun.max")
                    .font(.inter(size: 22, weight: .regular))
                    .foregroundColor(.primary)

                Text("Today")
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
                    Text("No tasks scheduled")
                        .font(.inter(.headline))
                        .bold()
                    Text("Tasks scheduled for today will appear here")
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
            ScheduleSelectionSheet(task: item, focusViewModel: focusViewModel)
                .drawerStyle()
        }
        .sheet(item: $projectsVM.selectedProjectForDetails) { project in
            ProjectDetailsDrawer(project: project, viewModel: projectsVM)
                .drawerStyle()
        }
        .sheet(item: $projectsVM.selectedTaskForSchedule) { task in
            ScheduleSelectionSheet(task: task, focusViewModel: focusViewModel)
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
                        .contentShape(Circle())
                }
            }
        }
        .task {
            isLoading = true
            await fetchTodayData()
            isLoading = false
        }
    }

    // MARK: - Data Fetching

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

            let allSchedules = focusSchedules + todoSchedules
            var schedules: [UUID: (scheduleId: UUID, sortOrder: Int)] = [:]
            for s in allSchedules {
                schedules[s.taskId] = (scheduleId: s.id, sortOrder: s.sortOrder)
            }
            todaySchedules = schedules

            taskListVM.scheduledTaskIds = Set(schedules.keys)
            taskListVM.scheduleFilter = .scheduled
        } catch {
            todaySchedules = [:]
            taskListVM.scheduledTaskIds = []
            taskListVM.scheduleFilter = .scheduled
        }

        await taskListVM.fetchCategories()
        async let t: () = taskListVM.fetchTasks()
        async let l: () = listsVM.fetchLists()
        async let p: () = projectsVM.fetchProjects()
        _ = await (t, l, p)
    }

    // MARK: - Item List

    private var itemList: some View {
        List {
            ForEach(flattenedTodayItems) { flatItem in
                switch flatItem {
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
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.visible)
                    .moveDisabled(true)

                case .inlineAddSubtask(let parentId):
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
                    .listRowSeparator(.hidden)
                    .moveDisabled(true)

                case .bottomSpacer:
                    Color.clear
                        .frame(height: 100)
                        .listRowInsets(EdgeInsets())
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
            case .task(let task, _, _):
                FlatTaskRow(
                    task: task,
                    viewModel: taskListVM,
                    isEditMode: false,
                    isSelected: false,
                    onSelectToggle: nil,
                    onToggleCompletion: { t in
                        taskListVM.requestToggleCompletion(t)
                    }
                )

            case .project(let project, _, _):
                TodayProjectRow(
                    project: project,
                    onTap: { selectedProjectForNavigation = project },
                    onEdit: { projectsVM.selectedProjectForDetails = project },
                    onSchedule: { projectsVM.selectedTaskForSchedule = project }
                )

            case .list(let list, _, _):
                TodayListRow(
                    list: list,
                    onTap: { selectedListForNavigation = list },
                    onEdit: { listsVM.selectedListForDetails = list },
                    onSchedule: { listsVM.selectedItemForSchedule = list }
                )
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
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

        var updates: [(id: UUID, sortOrder: Int)] = []
        for (index, entry) in items.enumerated() {
            let newOrder = index + 1
            updates.append((id: entry.scheduleId, sortOrder: newOrder))
            todaySchedules[entry.id] = (scheduleId: entry.scheduleId, sortOrder: newOrder)
        }

        _Concurrency.Task {
            try? await scheduleRepository.updateScheduleSortOrders(updates)
        }
    }
}

// MARK: - Today Project Row

private struct TodayProjectRow: View {
    let project: FocusTask
    var onTap: () -> Void
    var onEdit: () -> Void
    var onSchedule: () -> Void

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
        }
    }
}

// MARK: - Today List Row

private struct TodayListRow: View {
    let list: FocusTask
    var onTap: () -> Void
    var onEdit: () -> Void
    var onSchedule: () -> Void

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
        }
    }
}

// MARK: - Today Flat Item

private enum TodayFlatItem: Identifiable {
    case item(TodayItemEntry)
    case subtask(FocusTask, parentId: UUID)
    case inlineAddSubtask(parentId: UUID)
    case bottomSpacer

    var id: String {
        switch self {
        case .item(let e): return "item-\(e.id.uuidString)"
        case .subtask(let t, _): return "subtask-\(t.id.uuidString)"
        case .inlineAddSubtask(let pid): return "add-subtask-\(pid.uuidString)"
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
                return $0.createdDate < $1.createdDate
            }
        } else {
            return items.sorted { $0.sortOrder < $1.sortOrder }
        }
    }
}
