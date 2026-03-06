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
    @State private var todayCommittedIds: Set<UUID> = []

    // Navigation
    @State private var selectedListForNavigation: FocusTask?
    @State private var selectedProjectForNavigation: FocusTask?

    private let authService: AuthService
    private let commitmentRepository = CommitmentRepository()

    init(authService: AuthService) {
        self.authService = authService
        _taskListVM = StateObject(wrappedValue: TaskListViewModel(authService: authService))
        _listsVM = StateObject(wrappedValue: ListsViewModel(authService: authService))
        _projectsVM = StateObject(wrappedValue: ProjectsViewModel(authService: authService))
    }

    private var displayItems: [FlatDisplayItem] {
        taskListVM.flattenedDisplayItems.filter { item in
            switch item {
            case .task(let task): return task.projectId == nil
            case .addSubtaskRow(let parentId):
                let projectTaskIds = Set(taskListVM.uncompletedTasks.filter { $0.projectId != nil }.map { $0.id })
                return !projectTaskIds.contains(parentId)
            default: return true
            }
        }
    }

    private var committedLists: [FocusTask] {
        listsVM.lists
            .filter { !$0.isCompleted && !$0.isCleared }
            .filter { todayCommittedIds.contains($0.id) }
    }

    private var committedProjects: [FocusTask] {
        projectsVM.projects
            .filter { !$0.isCompleted && !$0.isCleared }
            .filter { todayCommittedIds.contains($0.id) }
    }

    private var isEmpty: Bool {
        taskListVM.uncompletedTasks.filter { $0.projectId == nil }.isEmpty
            && committedLists.isEmpty
            && committedProjects.isEmpty
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
                    Text("Tasks committed to today will appear here")
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
            CommitmentSelectionSheet(task: item, focusViewModel: focusViewModel)
                .drawerStyle()
        }
        .sheet(item: $projectsVM.selectedProjectForDetails) { project in
            ProjectDetailsDrawer(project: project, viewModel: projectsVM)
                .drawerStyle()
        }
        .sheet(item: $projectsVM.selectedTaskForSchedule) { task in
            CommitmentSelectionSheet(task: task, focusViewModel: focusViewModel)
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
            // Fetch daily commitments for today (both focus and todo sections)
            let focusCommitments = try await commitmentRepository.fetchCommitments(
                timeframe: .daily,
                date: Date(),
                section: .focus
            )
            let todoCommitments = try await commitmentRepository.fetchCommitments(
                timeframe: .daily,
                date: Date(),
                section: .todo
            )

            let allCommitments = focusCommitments + todoCommitments
            todayCommittedIds = Set(allCommitments.map { $0.taskId })

            // Set only today's task IDs as the committed filter
            taskListVM.committedTaskIds = todayCommittedIds
            taskListVM.commitmentFilter = .committed
        } catch {
            todayCommittedIds = []
            taskListVM.committedTaskIds = []
            taskListVM.commitmentFilter = .committed
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
            // Tasks with expandable subtasks
            ForEach(displayItems) { item in
                switch item {
                case .priorityHeader(let priority):
                    PrioritySectionHeader(
                        priority: priority,
                        count: taskListVM.uncompletedTasks.filter { $0.priority == priority && $0.projectId == nil }.count,
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
                        isEditMode: false,
                        isSelected: false,
                        onSelectToggle: nil,
                        onToggleCompletion: { t in
                            _Concurrency.Task { await taskListVM.toggleCompletion(t) }
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

            // Lists committed to today
            ForEach(committedLists) { list in
                TodayListRow(
                    list: list,
                    onTap: { selectedListForNavigation = list },
                    onEdit: { listsVM.selectedListForDetails = list },
                    onSchedule: { listsVM.selectedItemForSchedule = list }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Projects committed to today
            ForEach(committedProjects) { project in
                TodayProjectRow(
                    project: project,
                    onTap: { selectedProjectForNavigation = project },
                    onEdit: { projectsVM.selectedProjectForDetails = project },
                    onSchedule: { projectsVM.selectedTaskForSchedule = project }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
