//
//  ScheduledView.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct ScheduledView: View {
    @StateObject private var taskListVM = TaskListViewModel(authService: AuthService())
    @StateObject private var projectsVM = ProjectsViewModel(authService: AuthService())
    @StateObject private var listsVM = ListsViewModel(authService: AuthService())
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isInlineAddFocused = false
    @State private var isLoading = false
    @State private var viewMode: ScheduleViewMode = .day

    // Pending completions (committed to DB on disappear)
    @State private var pendingCompletions: Set<UUID> = []
    @State private var isCompletedSectionCollapsed = false

    // Commitment date entries: item UUID → set of committed dates
    @State private var itemDateEntries: [UUID: Set<Date>] = [:]

    // Batch create alerts
    @State private var showCreateProjectAlert = false
    @State private var showCreateListAlert = false
    @State private var newProjectTitle = ""
    @State private var newListTitle = ""

    // Date navigation
    @State private var selectedDate = Date()
    @State private var showCalendarPicker = false

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

    private var isAddTaskTitleEmpty: Bool {
        addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Computed: All committed items (no type separation)

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

    // MARK: - Computed: Completed items

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
        allCommittedTasks.isEmpty && allCommittedLists.isEmpty
        && allCommittedProjects.isEmpty && completedItems.isEmpty
    }

    // MARK: - Date Navigation Text

    private var scheduleCalendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal
    }

    private var scheduleDateText: String? {
        switch viewMode {
        case .day:
            let day = scheduleCalendar.component(.day, from: selectedDate)
            let suffix: String
            switch day {
            case 1, 21, 31: suffix = "st"
            case 2, 22: suffix = "nd"
            case 3, 23: suffix = "rd"
            default: suffix = "th"
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"
            let month = formatter.string(from: selectedDate)
            formatter.dateFormat = "yyyy"
            let year = formatter.string(from: selectedDate)
            return "\(month) \(day)\(suffix), \(year)"
        case .week:
            guard let weekStart = scheduleCalendar.date(from: scheduleCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)),
                  let weekEnd = scheduleCalendar.date(byAdding: .day, value: 6, to: weekStart) else { return nil }
            let startFmt = DateFormatter()
            startFmt.dateFormat = "MMM d"
            let endFmt = DateFormatter()
            endFmt.dateFormat = "MMM d, yyyy"
            return "\(startFmt.string(from: weekStart)) - \(endFmt.string(from: weekEnd))"
        case .month:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"
            return formatter.string(from: selectedDate)
        case .year:
            return String(scheduleCalendar.component(.year, from: selectedDate))
        }
    }

    // MARK: - Date Sections

    private var dateSections: [ScheduledSection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }

        let itemsByDate = self.itemsByDate

        var sections: [ScheduledSection] = []
        let dayFormatter = DateFormatter()

        // 1. Today (always shown)
        sections.append(ScheduledSection(
            id: "today", title: "Today", isRange: false, isSubDate: false,
            items: itemsByDate[today] ?? [], date: today, alwaysVisible: true
        ))

        // 2. Tomorrow (always shown)
        sections.append(ScheduledSection(
            id: "tomorrow", title: "Tomorrow", isRange: false, isSubDate: false,
            items: itemsByDate[tomorrow] ?? [], date: tomorrow, alwaysVisible: true
        ))

        // 3. Rest of current week (day after tomorrow through end of week, always shown)
        let endOfWeekOffset = 7 - calendar.component(.weekday, from: today) // days until Saturday
        if let endOfWeek = calendar.date(byAdding: .day, value: max(endOfWeekOffset, 2), to: today) {
            var day = calendar.date(byAdding: .day, value: 2, to: today)!
            while day <= endOfWeek {
                dayFormatter.dateFormat = "EEE"
                let dayName = dayFormatter.string(from: day)
                dayFormatter.dateFormat = "MMM d"
                let dateStr = dayFormatter.string(from: day)
                sections.append(ScheduledSection(
                    id: "week-\(day.timeIntervalSince1970)",
                    title: "\(dayName) \(dateStr)",
                    isRange: false, isSubDate: false,
                    items: itemsByDate[day] ?? [], date: day, alwaysVisible: true
                ))
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }

            // 4. "Rest of [Month]" — dates after this week but still in current month
            let dayAfterWeek = calendar.date(byAdding: .day, value: 1, to: endOfWeek)!
            var startOfNextMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfNextMonth)!

            let restOfMonthDates = itemsByDate.keys
                .filter { $0 >= dayAfterWeek && $0 < startOfNextMonth }
                .sorted()

            if !restOfMonthDates.isEmpty {
                dayFormatter.dateFormat = "MMMM"
                let monthName = dayFormatter.string(from: today)
                sections.append(ScheduledSection(
                    id: "rest-of-\(monthName)", title: "Rest of \(monthName)",
                    isRange: true, isSubDate: false,
                    items: [], date: nil, alwaysVisible: false
                ))
                for date in restOfMonthDates {
                    dayFormatter.dateFormat = "EEE"
                    let dn = dayFormatter.string(from: date)
                    dayFormatter.dateFormat = "MMM d"
                    let ds = dayFormatter.string(from: date)
                    sections.append(ScheduledSection(
                        id: "sub-\(date.timeIntervalSince1970)",
                        title: "\(dn) \(ds)",
                        isRange: false, isSubDate: true,
                        items: itemsByDate[date] ?? [], date: date, alwaysVisible: false
                    ))
                }
            }

            // 5. Future months
            let futureDates = itemsByDate.keys
                .filter { $0 >= startOfNextMonth }
                .sorted()

            let groupedByMonth = Dictionary(grouping: futureDates) { date -> String in
                dayFormatter.dateFormat = "yyyy-MM"
                return dayFormatter.string(from: date)
            }

            for monthKey in groupedByMonth.keys.sorted() {
                let datesInMonth = groupedByMonth[monthKey]!.sorted()
                dayFormatter.dateFormat = "MMMM"
                let monthTitle = dayFormatter.string(from: datesInMonth.first!)

                sections.append(ScheduledSection(
                    id: "month-\(monthKey)", title: monthTitle,
                    isRange: true, isSubDate: false,
                    items: [], date: nil, alwaysVisible: false
                ))
                for date in datesInMonth {
                    dayFormatter.dateFormat = "EEE"
                    let dn = dayFormatter.string(from: date)
                    dayFormatter.dateFormat = "MMM d"
                    let ds = dayFormatter.string(from: date)
                    sections.append(ScheduledSection(
                        id: "sub-\(date.timeIntervalSince1970)",
                        title: "\(dn) \(ds)",
                        isRange: false, isSubDate: true,
                        items: itemsByDate[date] ?? [], date: date, alwaysVisible: false
                    ))
                }
            }
        }

        return sections
    }

    // MARK: - Items By Date (shared helper)

    private var itemsByDate: [Date: [ScheduledItemEntry]] {
        var result: [Date: [ScheduledItemEntry]] = [:]
        for task in allCommittedTasks {
            if let dates = itemDateEntries[task.id] {
                for date in dates { result[date, default: []].append(.task(task)) }
            }
        }
        for list in allCommittedLists {
            if let dates = itemDateEntries[list.id] {
                for date in dates { result[date, default: []].append(.list(list)) }
            }
        }
        for project in allCommittedProjects {
            if let dates = itemDateEntries[project.id] {
                for date in dates { result[date, default: []].append(.project(project)) }
            }
        }
        // Sort each date's items: tasks first, projects second, lists third
        for key in result.keys {
            result[key]?.sort { $0.typeSortOrder < $1.typeSortOrder }
        }
        return result
    }

    // MARK: - Week Sections

    private var weekSections: [ScheduledSection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let byDate = itemsByDate

        // Find start of current week (Sunday or Monday depending on locale)
        let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let nextWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeekStart)!
        let weekAfterNext = calendar.date(byAdding: .weekOfYear, value: 2, to: thisWeekStart)!

        var sections: [ScheduledSection] = []
        let formatter = DateFormatter()

        // Collect items for a date range, sorted by type (tasks → projects → lists)
        func items(from start: Date, to end: Date) -> [ScheduledItemEntry] {
            byDate.filter { $0.key >= start && $0.key < end }
                .sorted { $0.key < $1.key }
                .flatMap { $0.value }
                .sorted { $0.typeSortOrder < $1.typeSortOrder }
        }

        // 1. This Week
        sections.append(ScheduledSection(
            id: "this-week", title: "This Week",
            isRange: false, isSubDate: false,
            items: items(from: thisWeekStart, to: nextWeekStart),
            date: today, alwaysVisible: true
        ))

        // 2. Next Week
        sections.append(ScheduledSection(
            id: "next-week", title: "Next Week",
            isRange: false, isSubDate: false,
            items: items(from: nextWeekStart, to: weekAfterNext),
            date: nextWeekStart, alwaysVisible: true
        ))

        // 3. Future weeks
        let futureDates = byDate.keys.filter { $0 >= weekAfterNext }.sorted()
        let groupedByWeek = Dictionary(grouping: futureDates) { date -> Date in
            calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        }

        for weekStart in groupedByWeek.keys.sorted() {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
            let weekNum = calendar.component(.weekOfYear, from: weekStart)

            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: weekStart)
            let endStr = formatter.string(from: weekEnd)

            let weekItems = groupedByWeek[weekStart]!
                .sorted()
                .flatMap { byDate[$0] ?? [] }
                .sorted { $0.typeSortOrder < $1.typeSortOrder }

            sections.append(ScheduledSection(
                id: "week-\(weekStart.timeIntervalSince1970)",
                title: "Week \(weekNum): \(startStr) – \(endStr)",
                isRange: false, isSubDate: false,
                items: weekItems, date: weekStart, alwaysVisible: false
            ))
        }

        return sections
    }

    // MARK: - Month Sections

    private var monthSections: [ScheduledSection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let byDate = itemsByDate

        let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
        let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: thisMonthStart)!
        let monthAfterNext = calendar.date(byAdding: .month, value: 2, to: thisMonthStart)!

        var sections: [ScheduledSection] = []
        let formatter = DateFormatter()

        func items(from start: Date, to end: Date) -> [ScheduledItemEntry] {
            byDate.filter { $0.key >= start && $0.key < end }
                .sorted { $0.key < $1.key }
                .flatMap { $0.value }
                .sorted { $0.typeSortOrder < $1.typeSortOrder }
        }

        // 1. This Month
        sections.append(ScheduledSection(
            id: "this-month", title: "This Month",
            isRange: false, isSubDate: false,
            items: items(from: thisMonthStart, to: nextMonthStart),
            date: today, alwaysVisible: true
        ))

        // 2. Next Month
        formatter.dateFormat = "MMMM"
        let nextMonthName = formatter.string(from: nextMonthStart)
        sections.append(ScheduledSection(
            id: "next-month", title: "Next Month – \(nextMonthName)",
            isRange: false, isSubDate: false,
            items: items(from: nextMonthStart, to: monthAfterNext),
            date: nextMonthStart, alwaysVisible: true
        ))

        // 3. Future months
        let futureDates = byDate.keys.filter { $0 >= monthAfterNext }.sorted()
        let groupedByMonth = Dictionary(grouping: futureDates) { date -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        }

        for monthStart in groupedByMonth.keys.sorted() {
            let year = calendar.component(.year, from: monthStart)
            let currentYear = calendar.component(.year, from: today)

            formatter.dateFormat = year == currentYear ? "MMMM" : "MMMM yyyy"
            let title = formatter.string(from: monthStart)

            let monthItems = groupedByMonth[monthStart]!
                .sorted()
                .flatMap { byDate[$0] ?? [] }
                .sorted { $0.typeSortOrder < $1.typeSortOrder }

            sections.append(ScheduledSection(
                id: "month-\(monthStart.timeIntervalSince1970)",
                title: title,
                isRange: false, isSubDate: false,
                items: monthItems, date: monthStart, alwaysVisible: false
            ))
        }

        return sections
    }

    // MARK: - Year Sections

    private var yearSections: [ScheduledSection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let byDate = itemsByDate

        let currentYear = calendar.component(.year, from: today)
        var sections: [ScheduledSection] = []

        let groupedByYear = Dictionary(grouping: byDate.keys) { date -> Int in
            calendar.component(.year, from: date)
        }

        // Current year (always visible)
        let currentYearItems = (groupedByYear[currentYear] ?? [])
            .sorted()
            .flatMap { byDate[$0] ?? [] }
            .sorted { $0.typeSortOrder < $1.typeSortOrder }

        sections.append(ScheduledSection(
            id: "year-\(currentYear)", title: "This Year",
            isRange: false, isSubDate: false,
            items: currentYearItems, date: today, alwaysVisible: true
        ))

        // Future years
        for year in groupedByYear.keys.sorted() where year > currentYear {
            let yearItems = groupedByYear[year]!
                .sorted()
                .flatMap { byDate[$0] ?? [] }
                .sorted { $0.typeSortOrder < $1.typeSortOrder }

            sections.append(ScheduledSection(
                id: "year-\(year)", title: "\(year)",
                isRange: false, isSubDate: false,
                items: yearItems, date: nil, alwaysVisible: false
            ))
        }

        return sections
    }

    // MARK: - Active Sections (switches on viewMode)

    private var activeSections: [ScheduledSection] {
        switch viewMode {
        case .day: return dateSections
        case .week: return weekSections
        case .month: return monthSections
        case .year: return yearSections
        }
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
        .sheet(isPresented: $taskListVM.showBatchMovePicker) {
            BatchMoveCategorySheet(
                viewModel: taskListVM,
                onMoveToProject: { projectId in
                    await taskListVM.batchMoveToProject(projectId)
                    await refreshAllData()
                }
            )
            .drawerStyle()
        }
        .sheet(isPresented: $taskListVM.showBatchCommitSheet) {
            BatchCommitSheet(
                viewModel: taskListVM,
                onBatchSchedule: { tasks, timeframe, section, dates in
                    guard !dates.isEmpty else { return }
                    let repo = CommitmentRepository()
                    for task in tasks {
                        for date in dates {
                            let c = Commitment(
                                userId: task.userId, taskId: task.id,
                                timeframe: timeframe, section: section,
                                commitmentDate: Calendar.current.startOfDay(for: date),
                                sortOrder: 0
                            )
                            _Concurrency.Task { _ = try? await repo.createCommitment(c) }
                        }
                    }
                    _Concurrency.Task { @MainActor in await refreshAllData() }
                }
            )
            .drawerStyle()
        }
        // Alerts
        .alert("Delete \(taskListVM.selectedCount) item\(taskListVM.selectedCount == 1 ? "" : "s")?",
               isPresented: $taskListVM.showBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await taskListVM.batchDeleteTasks()
                    await refreshAllData()
                }
            }
        } message: {
            Text("This will permanently delete the selected items and their commitments.")
        }
        .alert("Create Project", isPresented: $showCreateProjectAlert) {
            TextField("Project title", text: $newProjectTitle)
            Button("Cancel", role: .cancel) { newProjectTitle = "" }
            Button("Create") {
                let title = newProjectTitle
                newProjectTitle = ""
                _Concurrency.Task { @MainActor in
                    await taskListVM.createProjectFromSelected(title: title)
                    await refreshAllData()
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
                    await refreshAllData()
                }
            }
        } message: {
            Text("Enter a name for the new list")
        }
        // Project sheets
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
            ToolbarItem(placement: .navigationBarLeading) { leadingToolbarContent }
            ToolbarItem(placement: .navigationBarTrailing) { trailingToolbarContent }
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
                Text("Scheduled")
                    .font(.inter(size: 28, weight: .regular))
                    .foregroundColor(.appRed)
                Spacer()
                if let dateText = scheduleDateText {
                    Button {
                        showCalendarPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(dateText)
                                .font(.montserratHeader(.subheadline, weight: .medium))
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.right")
                                .font(.inter(size: 8, weight: .semiBold))
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                ForEach(ScheduleViewMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewMode = mode
                        }
                    } label: {
                        Text(mode.label)
                            .font(.inter(size: 13, weight: .medium))
                            .foregroundColor(viewMode == mode ? .white : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(viewMode == mode ? Color.appRed : Color.secondary.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .sheet(isPresented: $showCalendarPicker) {
            SingleSelectCalendarPicker(
                selectedDate: $selectedDate,
                timeframe: viewMode.timeframe
            )
            .drawerStyle()
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 4) {
            Text("No scheduled items")
                .font(.inter(.headline))
                .bold()
            Text("Scheduled tasks, lists, and projects will appear here")
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
        if taskListVM.isEditMode {
            EditModeActionBar(
                viewModel: taskListVM,
                showCreateProjectAlert: $showCreateProjectAlert,
                showCreateListAlert: $showCreateListAlert
            )
            .transition(.scale.combined(with: .opacity))
        } else if !showingAddBar {
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
            ForEach(activeSections) { section in
                if section.alwaysVisible || !section.items.isEmpty || section.isRange {
                    dateSectionHeader(for: section)

                    ForEach(section.items) { entry in
                        scheduledItemRow(entry)
                    }

                    // Per-day add button (dashed circle) — only in day mode
                    if viewMode == .day, let date = section.date, !section.isRange {
                        addButtonForDay(date: date)
                    }
                }
            }

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

    // MARK: - Date Section Headers

    @ViewBuilder
    private func dateSectionHeader(for section: ScheduledSection) -> some View {
        if section.isRange {
            // Major range header: "Rest of March", "April"
            VStack(spacing: 0) {
                HStack {
                    Text(section.title)
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
            .padding(.top, 16)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if section.isSubDate {
            // Sub-date header within a range: "Sun Mar 29"
            HStack {
                Text(section.title)
                    .font(.inter(.subheadline, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.top, 10)
            .padding(.bottom, 2)
            .listRowInsets(EdgeInsets(top: 0, leading: 28, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            // Day header: "Today", "Tomorrow", "Thu Mar 5"
            VStack(spacing: 0) {
                HStack {
                    Text(section.title)
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
            .padding(.top, section.id == "today" ? 0 : 8)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Unified Item Row

    @ViewBuilder
    private func scheduledItemRow(_ entry: ScheduledItemEntry) -> some View {
        switch entry {
        case .task(let task):
            FlatTaskRow(
                task: task,
                viewModel: taskListVM,
                isEditMode: taskListVM.isEditMode,
                isSelected: taskListVM.selectedTaskIds.contains(task.id),
                onSelectToggle: { taskListVM.toggleTaskSelection(task.id) },
                onToggleCompletion: { t in pendingCompletions.insert(t.id) }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

        case .project(let project):
            ScheduledProjectRow(
                project: project,
                isEditMode: taskListVM.isEditMode,
                isSelected: taskListVM.selectedTaskIds.contains(project.id),
                onSelectToggle: { taskListVM.toggleTaskSelection(project.id) },
                onTap: { selectedProjectForNavigation = project },
                onToggleCompletion: { pendingCompletions.insert(project.id) },
                onEdit: { projectsVM.selectedProjectForDetails = project },
                onSchedule: { projectsVM.selectedTaskForSchedule = project },
                onDelete: {
                    await projectsVM.deleteProject(project)
                    await refreshAllData()
                }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

        case .list(let list):
            ScheduledListRow(
                list: list,
                isEditMode: taskListVM.isEditMode,
                isSelected: taskListVM.selectedTaskIds.contains(list.id),
                onSelectToggle: { taskListVM.toggleTaskSelection(list.id) },
                onTap: { selectedListForNavigation = list },
                onToggleCompletion: { pendingCompletions.insert(list.id) },
                onEdit: { listsVM.selectedListForDetails = list },
                onSchedule: { listsVM.selectedItemForSchedule = list },
                onDelete: {
                    await listsVM.deleteList(list)
                    await refreshAllData()
                }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - Per-Day Add Button

    private func addButtonForDay(date: Date) -> some View {
        Button {
            addTaskDates = [date]
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
            var datesByTask: [UUID: Set<Date>] = [:]
            for s in summaries {
                let date = calendar.startOfDay(for: s.commitmentDate)
                datesByTask[s.taskId, default: []].insert(date)
            }
            itemDateEntries = datesByTask
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
        addTaskDates = []
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

private extension ScheduledView {
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

// MARK: - Toolbar Content

private extension ScheduledView {
    @ViewBuilder
    var leadingToolbarContent: some View {
        if taskListVM.isEditMode {
            Button { taskListVM.exitEditMode() } label: {
                Text("Done")
                    .font(.inter(.body, weight: .medium))
                    .foregroundColor(.appRed)
            }
        } else {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(.primary)
            }
        }
    }

    @ViewBuilder
    var trailingToolbarContent: some View {
        if taskListVM.isEditMode {
            Button {
                if taskListVM.allUncompletedSelected { taskListVM.deselectAll() }
                else { taskListVM.selectAllUncompleted() }
            } label: {
                Text(taskListVM.allUncompletedSelected ? "Deselect All" : "Select All")
                    .font(.inter(.body, weight: .medium))
                    .foregroundColor(.appRed)
            }
        } else {
            trailingMenu
        }
    }

    var trailingMenu: some View {
        Menu {
            Button { taskListVM.enterEditMode() } label: {
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

// MARK: - Data Models

private enum ScheduledItemEntry: Identifiable {
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

    /// Sort order: tasks first, projects second, lists third
    var typeSortOrder: Int {
        switch self {
        case .task: return 0
        case .project: return 1
        case .list: return 2
        }
    }
}

private struct ScheduledSection: Identifiable {
    let id: String
    let title: String
    let isRange: Bool
    let isSubDate: Bool
    let items: [ScheduledItemEntry]
    let date: Date?
    let alwaysVisible: Bool
}

private enum ScheduleViewMode: String, CaseIterable {
    case day, week, month, year

    var label: String {
        rawValue.capitalized
    }

    var timeframe: Timeframe {
        switch self {
        case .day: return .daily
        case .week: return .weekly
        case .month: return .monthly
        case .year: return .yearly
        }
    }
}

// MARK: - Scheduled Project Row

private struct ScheduledProjectRow: View {
    let project: FocusTask
    var isEditMode: Bool
    var isSelected: Bool
    var onSelectToggle: () -> Void
    var onTap: () -> Void
    var onToggleCompletion: () -> Void
    var onEdit: () -> Void
    var onSchedule: () -> Void
    var onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(isSelected ? .appRed : .secondary)
            }
            ProjectIconShape()
                .frame(width: 24, height: 24)
                .foregroundColor(.secondary)
            Text(project.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            if !isEditMode {
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
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if isEditMode { onSelectToggle() } else { onTap() } }
        .contextMenu {
            if !isEditMode {
                ContextMenuItems.editButton { onEdit() }
                ContextMenuItems.scheduleButton { onSchedule() }
                Divider()
                ContextMenuItems.deleteButton { showDeleteConfirmation = true }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isEditMode {
                Button(role: .destructive) { showDeleteConfirmation = true } label: {
                    Label("Delete", systemImage: "trash")
                }
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

// MARK: - Scheduled List Row

private struct ScheduledListRow: View {
    let list: FocusTask
    var isEditMode: Bool
    var isSelected: Bool
    var onSelectToggle: () -> Void
    var onTap: () -> Void
    var onToggleCompletion: () -> Void
    var onEdit: () -> Void
    var onSchedule: () -> Void
    var onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(isSelected ? .appRed : .secondary)
            }
            Image(systemName: "list.bullet")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 24)
            Text(list.title)
                .font(.inter(.body))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            if !isEditMode {
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
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if isEditMode { onSelectToggle() } else { onTap() } }
        .contextMenu {
            if !isEditMode {
                ContextMenuItems.editButton { onEdit() }
                ContextMenuItems.scheduleButton { onSchedule() }
                Divider()
                ContextMenuItems.deleteButton { showDeleteConfirmation = true }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isEditMode {
                Button(role: .destructive) { showDeleteConfirmation = true } label: {
                    Label("Delete", systemImage: "trash")
                }
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
