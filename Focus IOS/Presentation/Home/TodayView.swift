//
//  TodayView.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct TodayView: View {
    @StateObject private var taskListVM = TaskListViewModel(authService: AuthService())
    @StateObject private var projectsVM = ProjectsViewModel(authService: AuthService())
    @StateObject private var listsVM = ListsViewModel(authService: AuthService())
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false

    // Pending completions (committed to DB on disappear)
    @State private var pendingCompletions: Set<UUID> = []
    @State private var isCompletedSectionCollapsed = false

    // Commitment entries: item UUID → list of (date, timeframe) pairs
    @State private var itemCommitments: [UUID: [(date: Date, timeframe: Timeframe)]] = [:]

    // Navigation
    @State private var selectedListForNavigation: FocusTask?
    @State private var selectedProjectForNavigation: FocusTask?

    // Add task bar state
    @State private var showingAddBar = false
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
    @FocusState private var addBarTitleFocused: Bool
    @State private var isInlineAddFocused = false

    private var isAddTaskTitleEmpty: Bool {
        addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Computed: All committed items

    private var allCommittedTasks: [FocusTask] {
        taskListVM.uncompletedTasks.filter { !pendingCompletions.contains($0.id) }
    }

    private var allCommittedLists: [FocusTask] {
        listsVM.lists
            .filter { !$0.isCompleted && !$0.isCleared }
            .filter { taskListVM.committedTaskIds.contains($0.id) }
            .filter { !pendingCompletions.contains($0.id) }
    }

    private var allCommittedProjects: [FocusTask] {
        projectsVM.projects
            .filter { !$0.isCompleted && !$0.isCleared }
            .filter { taskListVM.committedTaskIds.contains($0.id) }
            .filter { !pendingCompletions.contains($0.id) }
    }

    // MARK: - Completed items

    private var completedItems: [FocusTask] {
        var items: [FocusTask] = []
        for taskId in pendingCompletions {
            if let task = taskListVM.uncompletedTasks.first(where: { $0.id == taskId }) {
                items.append(task)
                continue
            }
            if let list = listsVM.lists.first(where: { $0.id == taskId }) {
                items.append(list)
                continue
            }
            if let project = projectsVM.projects.first(where: { $0.id == taskId }) {
                items.append(project)
                continue
            }
        }
        return items
    }

    private var isEmpty: Bool {
        todayItems.isEmpty && completedItems.isEmpty
    }

    // MARK: - Today's items

    private var todayItems: [TodayItemEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var entries: [TodayItemEntry] = []

        func addEntries(for item: FocusTask, as type: (FocusTask) -> TodayItemEntry) {
            guard let commits = itemCommitments[item.id] else { return }
            let hasToday = commits.contains { calendar.isDate($0.date, inSameDayAs: today) }
            if hasToday {
                entries.append(type(item))
            }
        }

        for task in allCommittedTasks { addEntries(for: task) { .task($0) } }
        for list in allCommittedLists { addEntries(for: list) { .list($0) } }
        for project in allCommittedProjects { addEntries(for: project) { .project($0) } }

        // Deduplicate by ID
        var seen: Set<UUID> = []
        entries = entries.filter { seen.insert($0.id).inserted }

        // Sort: tasks first, projects second, lists third, then by creation date
        return entries.sorted(by: TodayItemEntry.stableSort)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            mainContent
            overlayContent
        }
        .onDisappear { commitPendingCompletions() }
        .onChange(of: showingAddBar) { _, isShowing in
            if isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    addBarTitleFocused = true
                }
            }
        }
        .onChange(of: taskListVM.tasks) { _, _ in
            cleanupPendingCompletions()
        }
        .task {
            taskListVM.commitmentFilter = .committed
            isLoading = true
            await loadAllData()
            isLoading = false
        }
        // Sheets
        .sheet(item: $taskListVM.selectedTaskForDetails) { task in
            TaskDetailsDrawer(task: task, viewModel: taskListVM, categories: taskListVM.categories)
                .drawerStyle()
        }
        .sheet(item: $taskListVM.selectedTaskForSchedule) { task in
            CommitmentSelectionSheet(task: task, focusViewModel: focusViewModel)
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
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(.primary)
                }
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            headerView
            if isLoading && isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isEmpty {
                emptyStateView
            } else {
                itemList
            }
        }
    }

    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Today")
                    .font(.inter(size: 28, weight: .regular))
                    .foregroundColor(.appRed)
                Spacer()
                Text(todayDateText)
                    .font(.montserratHeader(.subheadline, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var todayDateText: String {
        let date = Date()
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let suffix: String
        switch day {
        case 1, 21, 31: suffix = "st"
        case 2, 22: suffix = "nd"
        case 3, 23: suffix = "rd"
        default: suffix = "th"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: date)
        formatter.dateFormat = "yyyy"
        let year = formatter.string(from: date)
        return "\(month) \(day)\(suffix), \(year)"
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 4) {
            Text("Nothing scheduled for today")
                .font(.inter(.headline))
                .bold()
            Text("Tasks, lists, and projects scheduled for today will appear here")
                .font(.inter(.subheadline))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - Overlay Content

    @ViewBuilder
    private var overlayContent: some View {
        if !showingAddBar {
            fabButton
        }

        if showingAddBar {
            addBarOverlay
        }
    }

    @ViewBuilder
    private var fabButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    // Pre-fill today's date for new tasks
                    addTaskDates = [Calendar.current.startOfDay(for: Date())]
                    addTaskTimeframe = .daily
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

    @ViewBuilder
    private var addBarOverlay: some View {
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

    // MARK: - Item List

    private var itemList: some View {
        List {
            // Today section header
            todaySectionHeader

            ForEach(todayItems) { entry in
                todayItemRow(entry)
            }

            // Add button for today
            addButtonForToday

            // Completed section
            completedSection

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
                    await loadAllData()
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Section Header

    private var todaySectionHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Todo's")
                    .font(.inter(size: 22, weight: .semiBold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Item Row

    @ViewBuilder
    private func todayItemRow(_ entry: TodayItemEntry) -> some View {
        Group {
            switch entry {
            case .task(let task):
                FlatTaskRow(
                    task: task,
                    viewModel: taskListVM,
                    isEditMode: false,
                    isSelected: false,
                    onSelectToggle: nil,
                    onToggleCompletion: { t in pendingCompletions.insert(t.id) }
                )

            case .project(let project):
                TodayProjectRow(
                    project: project,
                    onTap: { selectedProjectForNavigation = project },
                    onToggleCompletion: { pendingCompletions.insert(project.id) },
                    onEdit: { projectsVM.selectedProjectForDetails = project },
                    onSchedule: { projectsVM.selectedTaskForSchedule = project },
                    onDelete: {
                        await projectsVM.deleteProject(project)
                        await refreshAllData()
                    }
                )

            case .list(let list):
                TodayListRow(
                    list: list,
                    onTap: { selectedListForNavigation = list },
                    onToggleCompletion: { pendingCompletions.insert(list.id) },
                    onEdit: { listsVM.selectedListForDetails = list },
                    onSchedule: { listsVM.selectedItemForSchedule = list },
                    onDelete: {
                        await listsVM.deleteList(list)
                        await refreshAllData()
                    }
                )
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Add Button

    private var addButtonForToday: some View {
        Button {
            addTaskDates = [Calendar.current.startOfDay(for: Date())]
            addTaskTimeframe = .daily
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showingAddBar = true
            }
        } label: {
            Image(systemName: "circle.dashed")
                .font(.inter(.title3))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Completed Section

    @ViewBuilder
    private var completedSection: some View {
        if !completedItems.isEmpty {
            completedSectionHeader

            if !isCompletedSectionCollapsed {
                ForEach(completedItems) { item in
                    FlatTaskRow(
                        task: item,
                        viewModel: taskListVM,
                        isEditMode: false,
                        isSelected: false,
                        onSelectToggle: nil,
                        onToggleCompletion: { t in pendingCompletions.remove(t.id) },
                        appearCompleted: true
                    )
                    .opacity(0.5)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    private var completedSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCompletedSectionCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.inter(.subheadline))
                    .foregroundColor(.completedPurple)
                Text("Completed")
                    .font(.inter(.headline, weight: .bold))
                    .foregroundColor(.secondary)
                Text("\(completedItems.count)")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.inter(size: 10, weight: .semiBold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isCompletedSectionCollapsed ? 0 : 90))
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

    // MARK: - Data Loading

    private func loadAllData() async {
        async let c: () = taskListVM.fetchCommittedTaskIds()
        async let cats: () = taskListVM.fetchCategories()
        _ = await (c, cats)

        async let t: () = taskListVM.fetchTasks()
        async let p: () = projectsVM.fetchProjects()
        async let l: () = listsVM.fetchLists()
        async let s: () = fetchScheduledDates()
        _ = await (t, p, l, s)
    }

    private func fetchScheduledDates() async {
        do {
            let repo = CommitmentRepository()
            let summaries = try await repo.fetchCommitmentSummaries()
            let calendar = Calendar.current
            var commitsByTask: [UUID: [(date: Date, timeframe: Timeframe)]] = [:]
            for s in summaries {
                let date = calendar.startOfDay(for: s.commitmentDate)
                commitsByTask[s.taskId, default: []].append((date: date, timeframe: s.timeframe))
            }
            itemCommitments = commitsByTask
        } catch { }
    }

    private func refreshAllData() async {
        await loadAllData()
    }

    private func cleanupPendingCompletions() {
        let allKnownIds = Set(taskListVM.uncompletedTasks.map { $0.id })
            .union(Set(listsVM.lists.map { $0.id }))
            .union(Set(projectsVM.projectTasksMap.values.flatMap { $0 }.map { $0.id }))
        for taskId in pendingCompletions {
            if !allKnownIds.contains(taskId) {
                pendingCompletions.remove(taskId)
            }
        }
    }

    private func commitPendingCompletions() {
        let completionsToCommit = pendingCompletions
        guard !completionsToCommit.isEmpty else { return }

        _Concurrency.Task { @MainActor in
            let repository = TaskRepository()
            for taskId in completionsToCommit {
                if let task = taskListVM.uncompletedTasks.first(where: { $0.id == taskId }) {
                    await taskListVM.toggleCompletion(task)
                    continue
                }
                if listsVM.lists.contains(where: { $0.id == taskId }) {
                    try? await repository.completeTask(id: taskId)
                    continue
                }
                if projectsVM.projects.contains(where: { $0.id == taskId }) {
                    try? await repository.completeTask(id: taskId)
                    continue
                }
            }
            pendingCompletions.removeAll()
            await focusViewModel.fetchCommitments()
        }
    }

    // MARK: - Add Task Helpers

    private var categoryPillLabel: String {
        if let categoryId = addTaskCategoryId,
           let category = taskListVM.categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

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
        addBarTitleFocused = true
        focusedSubtaskId = nil
        addTaskTitle = ""
        addTaskSubtasks = []
        addTaskDates = [Calendar.current.startOfDay(for: Date())]
        addTaskOptionsExpanded = false
        addTaskCommitExpanded = false
        addTaskPriority = .low
        hasGeneratedBreakdown = false

        _Concurrency.Task { @MainActor in
            await taskListVM.createTaskWithCommitments(
                title: title, categoryId: categoryId, priority: priority,
                subtaskTitles: subtasksToCreate, commitAfterCreate: commitEnabled,
                selectedTimeframe: timeframe, selectedSection: section,
                selectedDates: dates, hasScheduledTime: false, scheduledTime: nil
            )
            if commitEnabled && !dates.isEmpty {
                await focusViewModel.fetchCommitments()
                await refreshAllData()
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
        addTaskCommitExpanded = false
        addTaskDates = []
        hasGeneratedBreakdown = false
        focusedSubtaskId = nil
        addBarTitleFocused = false
        showingAddBar = false
    }
}

// MARK: - Add Task Bar

private extension TodayView {
    var addTaskBar: some View {
        VStack(spacing: 0) {
            addBarTitleField
            DraftSubtaskListEditor(
                subtasks: $addTaskSubtasks,
                focusedSubtaskId: $focusedSubtaskId,
                onAddNew: { addNewSubtask() }
            )
            if addTaskCommitExpanded {
                addBarCommitSection
            }
            if !addTaskCommitExpanded {
                addBarButtonRow
            }
            if addTaskOptionsExpanded && !addTaskCommitExpanded {
                addBarOptionsRow
            }
            Spacer().frame(height: 20)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .padding(.horizontal)
    }

    var addBarTitleField: some View {
        TextField("Create a new task", text: $addTaskTitle)
            .font(.inter(.title3))
            .textFieldStyle(.plain)
            .focused($addBarTitleFocused)
            .submitLabel(.return)
            .onSubmit { saveTask() }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 10)
    }

    var addBarCommitSection: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 14)

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

            addBarCommitButtons
        }
    }

    var addBarCommitButtons: some View {
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

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    addTaskCommitExpanded = false
                }
            } label: {
                let hasDateChanges = addTaskDates != addTaskDatesSnapshot
                Image(systemName: "checkmark")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(hasDateChanges ? .white : .secondary)
                    .frame(width: 36, height: 36)
                    .background(hasDateChanges ? Color.appRed : Color(.systemGray4), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    var addBarButtonRow: some View {
        HStack(spacing: 8) {
            Button { addNewSubtask() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.inter(.caption))
                    Text("Sub-task").font(.inter(.caption))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { addTaskOptionsExpanded.toggle() }
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

            Button { generateBreakdown() } label: {
                HStack(spacing: 6) {
                    if isGeneratingBreakdown {
                        ProgressView().tint(.primary)
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
                .background(!isAddTaskTitleEmpty ? Color.pillBackground : Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isAddTaskTitleEmpty || isGeneratingBreakdown)

            Button { saveTask() } label: {
                Image(systemName: "checkmark")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(isAddTaskTitleEmpty ? .secondary : .white)
                    .frame(width: 36, height: 36)
                    .background(isAddTaskTitleEmpty ? Color(.systemGray4) : Color.completedPurple, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isAddTaskTitleEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    var addBarOptionsRow: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    addTaskCategoryId = nil
                } label: {
                    if addTaskCategoryId == nil { Label("None", systemImage: "checkmark") } else { Text("None") }
                }
                ForEach(taskListVM.categories) { category in
                    Button {
                        addTaskCategoryId = category.id
                    } label: {
                        if addTaskCategoryId == category.id { Label(category.name, systemImage: "checkmark") } else { Text(category.name) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder").font(.inter(.caption))
                    Text(LocalizedStringKey(categoryPillLabel)).font(.inter(.caption))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white, in: Capsule())
            }

            Button {
                if !addTaskCommitExpanded { addTaskDatesSnapshot = addTaskDates }
                withAnimation(.easeInOut(duration: 0.2)) { addTaskCommitExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle").font(.inter(.caption))
                    Text("Schedule").font(.inter(.caption))
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
                        if addTaskPriority == priority { Label(priority.displayName, systemImage: "checkmark") } else { Text(priority.displayName) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle().fill(addTaskPriority.dotColor).frame(width: 8, height: 8)
                    Text(addTaskPriority.displayName).font(.inter(.caption))
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
}

// MARK: - Data Models

private enum TodayItemEntry: Identifiable {
    case task(FocusTask)
    case project(FocusTask)
    case list(FocusTask)

    var id: UUID {
        switch self {
        case .task(let t): return t.id
        case .project(let p): return p.id
        case .list(let l): return l.id
        }
    }

    var createdDate: Date {
        switch self {
        case .task(let t): return t.createdDate
        case .project(let p): return p.createdDate
        case .list(let l): return l.createdDate
        }
    }

    var typeSortOrder: Int {
        switch self {
        case .task: return 0
        case .project: return 1
        case .list: return 2
        }
    }

    static func stableSort(_ a: TodayItemEntry, _ b: TodayItemEntry) -> Bool {
        if a.typeSortOrder != b.typeSortOrder { return a.typeSortOrder < b.typeSortOrder }
        return a.createdDate < b.createdDate
    }
}

// MARK: - Today Project Row

private struct TodayProjectRow: View {
    let project: FocusTask
    var onTap: () -> Void
    var onToggleCompletion: () -> Void
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
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onToggleCompletion()
            } label: {
                Image(systemName: "circle")
                    .font(.inter(.title3))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
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

// MARK: - Today List Row

private struct TodayListRow: View {
    let list: FocusTask
    var onTap: () -> Void
    var onToggleCompletion: () -> Void
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
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onToggleCompletion()
            } label: {
                Image(systemName: "circle")
                    .font(.inter(.title3))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
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
