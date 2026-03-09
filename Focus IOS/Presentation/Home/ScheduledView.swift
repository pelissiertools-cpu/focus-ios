//
//  ScheduledView.swift
//  Focus IOS
//

import SwiftUI
import Auth

struct ScheduledView: View {
    @StateObject private var taskListVM: TaskListViewModel
    @StateObject private var projectsVM: ProjectsViewModel
    @StateObject private var listsVM: ListsViewModel
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isInlineAddFocused = false
    @State private var isLoading = false
    @State private var viewMode: ScheduleViewMode = .day

    // Schedule entries: item UUID → list of (scheduleId, date, timeframe, sortOrder) tuples
    @State private var itemSchedules: [UUID: [(scheduleId: UUID, date: Date, timeframe: Timeframe, sortOrder: Int)]] = [:]
    @State private var itemTimeframes: [UUID: Set<Timeframe>] = [:]

    // Batch create alerts
    @State private var showCreateProjectAlert = false
    @State private var showCreateListAlert = false
    @State private var newProjectTitle = ""
    @State private var newListTitle = ""

    // Date navigation
    @State private var selectedDate = Date()
    @State private var showCalendarPicker = false

    @State private var selectedScheduleForReschedule: Schedule?

    // Navigation
    @State private var selectedListForNavigation: FocusTask?
    @State private var selectedProjectForNavigation: FocusTask?

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

    // Search
    @State private var isSearchActive = false
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool

    init(authService: AuthService) {
        _taskListVM = StateObject(wrappedValue: TaskListViewModel(authService: authService))
        _projectsVM = StateObject(wrappedValue: ProjectsViewModel(authService: authService))
        _listsVM = StateObject(wrappedValue: ListsViewModel(authService: authService))
    }

    private var isAddTaskTitleEmpty: Bool {
        addTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Computed: All scheduled items (no type separation)

    private var allScheduledTasks: [FocusTask] {
        taskListVM.uncompletedTasks
    }

    private var allScheduledLists: [FocusTask] {
        listsVM.lists
            .filter { !$0.isCompleted && !$0.isCleared }
            .filter { taskListVM.scheduledTaskIds.contains($0.id) }
    }

    private var allScheduledProjects: [FocusTask] {
        projectsVM.projects
            .filter { !$0.isCompleted && !$0.isCleared }
            .filter { taskListVM.scheduledTaskIds.contains($0.id) }
    }

    private var isEmpty: Bool {
        allScheduledTasks.isEmpty && allScheduledLists.isEmpty
        && allScheduledProjects.isEmpty
    }

    private var isSearching: Bool {
        isSearchActive && !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var searchIsEmpty: Bool {
        isSearching && searchSections.allSatisfy { $0.items.isEmpty }
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
        let anchor = calendar.startOfDay(for: selectedDate)
        let realToday = calendar.startOfDay(for: Date())

        let itemsByDate = self.itemsByDate

        var sections: [ScheduledSection] = []
        let dayFormatter = DateFormatter()

        // Helper: label for a day relative to real today
        func dayLabel(for date: Date) -> String {
            if calendar.isDate(date, inSameDayAs: realToday) { return "Today" }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: realToday),
               calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
            dayFormatter.dateFormat = "EEE MMM d"
            return dayFormatter.string(from: date)
        }

        // 1. Today + next 6 days (7 day slots, always visible & droppable)
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: anchor)!
            sections.append(ScheduledSection(
                id: "day-\(offset)-\(day.timeIntervalSince1970)",
                title: dayLabel(for: day),
                isRange: false, isSubDate: false,
                items: itemsByDate[day] ?? [], date: day, alwaysVisible: true
            ))
        }

        // 2. "Rest of [Month]" — dates after the 7-day window but still in anchor's month
        let day7 = calendar.date(byAdding: .day, value: 7, to: anchor)!
        var startOfNextMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor))!
        startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfNextMonth)!

        let restOfMonthDates = itemsByDate.keys
            .filter { $0 >= day7 && $0 < startOfNextMonth }
            .sorted()

        if !restOfMonthDates.isEmpty {
            dayFormatter.dateFormat = "MMMM"
            let monthName = dayFormatter.string(from: anchor)
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

        // 3. Future months (relative to anchor's month)
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

        return sections
    }

    // MARK: - Items By Date (shared helper)

    private var itemsByDate: [Date: [ScheduledItemEntry]] {
        let allowed = viewMode.allowedTimeframes
        let nativeTimeframe = viewMode.timeframe
        let showNative = viewMode != .day
        var result: [Date: [ScheduledItemEntry]] = [:]

        func addEntries(for item: FocusTask, as type: (FocusTask, Bool, UUID, Int) -> ScheduledItemEntry) {
            guard let itemEntries = itemSchedules[item.id] else { return }
            for entry in itemEntries where allowed.contains(entry.timeframe) {
                let isNative = showNative && entry.timeframe == nativeTimeframe
                result[entry.date, default: []].append(type(item, isNative, entry.scheduleId, entry.sortOrder))
            }
        }

        for task in allScheduledTasks { addEntries(for: task) { .task($0, isNative: $1, scheduleId: $2, sortOrder: $3) } }
        for list in allScheduledLists { addEntries(for: list) { .list($0, isNative: $1, scheduleId: $2, sortOrder: $3) } }
        for project in allScheduledProjects { addEntries(for: project) { .project($0, isNative: $1, scheduleId: $2, sortOrder: $3) } }

        // Deduplicate per date (same item, multiple timeframes) — prefer native
        for key in result.keys {
            var best: [UUID: ScheduledItemEntry] = [:]
            for entry in result[key]! {
                if let existing = best[entry.id] {
                    if entry.isNative && !existing.isNative { best[entry.id] = entry }
                } else {
                    best[entry.id] = entry
                }
            }
            result[key] = ScheduledItemEntry.sortForDisplay(Array(best.values))
        }
        return result
    }

    // MARK: - Week Sections

    private var weekSections: [ScheduledSection] {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: selectedDate)
        let byDate = itemsByDate

        // Find start of selected week
        let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: anchor))!
        let nextWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: thisWeekStart)!
        let weekAfterNext = calendar.date(byAdding: .weekOfYear, value: 2, to: thisWeekStart)!

        var sections: [ScheduledSection] = []
        let formatter = DateFormatter()

        func items(from start: Date, to end: Date) -> [ScheduledItemEntry] {
            let flat = byDate.filter { $0.key >= start && $0.key < end }
                .sorted { $0.key < $1.key }
                .flatMap { $0.value }
            var best: [UUID: ScheduledItemEntry] = [:]
            for entry in flat {
                if let existing = best[entry.id] {
                    if entry.isNative && !existing.isNative { best[entry.id] = entry }
                } else {
                    best[entry.id] = entry
                }
            }
            return ScheduledItemEntry.sortForDisplay(Array(best.values))
        }

        // Helper: title for a week start date
        let realToday = calendar.startOfDay(for: Date())
        let realWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: realToday))!
        let realNextWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: realWeekStart)!

        func weekTitle(for start: Date) -> String {
            if calendar.isDate(start, inSameDayAs: realWeekStart) { return "This Week" }
            if calendar.isDate(start, inSameDayAs: realNextWeekStart) { return "Next Week" }
            let weekNum = calendar.component(.weekOfYear, from: start)
            let end = calendar.date(byAdding: .day, value: 6, to: start)!
            formatter.dateFormat = "MMM d"
            return "Week \(weekNum): \(formatter.string(from: start)) – \(formatter.string(from: end))"
        }

        // 1. Selected week
        sections.append(ScheduledSection(
            id: "this-week", title: weekTitle(for: thisWeekStart),
            isRange: false, isSubDate: false,
            items: items(from: thisWeekStart, to: nextWeekStart),
            date: anchor, alwaysVisible: true
        ))

        // 2. Following week (relative to selected)
        sections.append(ScheduledSection(
            id: "next-week", title: weekTitle(for: nextWeekStart),
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
            let weekItems = items(from: weekStart, to: calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart)!)

            sections.append(ScheduledSection(
                id: "week-\(weekStart.timeIntervalSince1970)",
                title: weekTitle(for: weekStart),
                isRange: false, isSubDate: false,
                items: weekItems, date: weekStart, alwaysVisible: false
            ))
        }

        return sections
    }

    // MARK: - Month Sections

    private var monthSections: [ScheduledSection] {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: selectedDate)
        let byDate = itemsByDate

        let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor))!
        let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: thisMonthStart)!
        let monthAfterNext = calendar.date(byAdding: .month, value: 2, to: thisMonthStart)!

        var sections: [ScheduledSection] = []
        let formatter = DateFormatter()

        func items(from start: Date, to end: Date) -> [ScheduledItemEntry] {
            let flat = byDate.filter { $0.key >= start && $0.key < end }
                .sorted { $0.key < $1.key }
                .flatMap { $0.value }
            var best: [UUID: ScheduledItemEntry] = [:]
            for entry in flat {
                if let existing = best[entry.id] {
                    if entry.isNative && !existing.isNative { best[entry.id] = entry }
                } else {
                    best[entry.id] = entry
                }
            }
            return ScheduledItemEntry.sortForDisplay(Array(best.values))
        }

        // 1. Selected month
        let realToday = calendar.startOfDay(for: Date())
        let realMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: realToday))!
        formatter.dateFormat = "MMMM"
        let thisMonthTitle = calendar.isDate(thisMonthStart, inSameDayAs: realMonthStart)
            ? "This Month"
            : formatter.string(from: thisMonthStart)

        sections.append(ScheduledSection(
            id: "this-month", title: thisMonthTitle,
            isRange: false, isSubDate: false,
            items: items(from: thisMonthStart, to: nextMonthStart),
            date: anchor, alwaysVisible: true
        ))

        // 2. Next month (relative to selected)
        let realNextMonthStart = calendar.date(byAdding: .month, value: 1, to: realMonthStart)!
        let nextMonthName = formatter.string(from: nextMonthStart)
        let nextMonthTitle = calendar.isDate(nextMonthStart, inSameDayAs: realNextMonthStart)
            ? "Next Month – \(nextMonthName)"
            : nextMonthName

        sections.append(ScheduledSection(
            id: "next-month", title: nextMonthTitle,
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
            let currentYear = calendar.component(.year, from: anchor)

            formatter.dateFormat = year == currentYear ? "MMMM" : "MMMM yyyy"
            let title = formatter.string(from: monthStart)

            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            let monthItems = items(from: monthStart, to: nextMonth)

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
        let anchor = calendar.startOfDay(for: selectedDate)
        let byDate = itemsByDate

        let selectedYear = calendar.component(.year, from: anchor)
        let realYear = calendar.component(.year, from: Date())
        var sections: [ScheduledSection] = []

        let groupedByYear = Dictionary(grouping: byDate.keys) { date -> Int in
            calendar.component(.year, from: date)
        }

        func deduped(_ dates: [Date]) -> [ScheduledItemEntry] {
            let flat = dates.sorted().flatMap { byDate[$0] ?? [] }
            var best: [UUID: ScheduledItemEntry] = [:]
            for entry in flat {
                if let existing = best[entry.id] {
                    if entry.isNative && !existing.isNative { best[entry.id] = entry }
                } else {
                    best[entry.id] = entry
                }
            }
            return ScheduledItemEntry.sortForDisplay(Array(best.values))
        }

        // Selected year (always visible)
        let yearTitle = selectedYear == realYear ? "This Year" : "\(selectedYear)"

        sections.append(ScheduledSection(
            id: "year-\(selectedYear)", title: yearTitle,
            isRange: false, isSubDate: false,
            items: deduped(groupedByYear[selectedYear] ?? []), date: anchor, alwaysVisible: true
        ))

        // Future years (relative to selected)
        for year in groupedByYear.keys.sorted() where year > selectedYear {
            sections.append(ScheduledSection(
                id: "year-\(year)", title: "\(year)",
                isRange: false, isSubDate: false,
                items: deduped(groupedByYear[year]!), date: nil, alwaysVisible: false
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

    // MARK: - Flattened Items (for cross-section drag)

    private var flattenedItems: [ScheduledFlatItem] {
        let sections = isSearching ? searchSections : activeSections
        var result: [ScheduledFlatItem] = []

        for section in sections {
            guard section.alwaysVisible || !section.items.isEmpty || section.isRange else { continue }

            if section.items.isEmpty, section.alwaysVisible, section.date != nil {
                // Empty day section: compact drop zone row replaces both header and add button
                result.append(.dropZone(section))
            } else {
                result.append(.sectionHeader(section))

                for entry in section.items {
                    result.append(.item(entry))

                    // Expanded subtasks
                    if case .task(let task, _, _, _) = entry,
                       taskListVM.expandedTasks.contains(task.id) {
                        let subtasks = taskListVM.getUncompletedSubtasks(for: task.id)
                            + taskListVM.getCompletedSubtasks(for: task.id)
                        for subtask in subtasks {
                            result.append(.subtask(subtask, parentId: task.id))
                        }
                        result.append(.inlineAddSubtask(parentId: task.id))
                    }
                }

                if !isSearching, let date = section.date, !section.isRange {
                    result.append(.addButton(date))
                }
            }
        }

        result.append(.bottomSpacer)
        return result
    }

    // MARK: - Search Sections (grouped by timeframe)

    private var searchSections: [ScheduledSection] {
        let query = searchText.lowercased()
        let matchingTasks = allScheduledTasks.filter { $0.title.lowercased().contains(query) }
        let matchingProjects = allScheduledProjects.filter { $0.title.lowercased().contains(query) }
        let matchingLists = allScheduledLists.filter { $0.title.lowercased().contains(query) }

        let timeframes: [(Timeframe, String)] = [
            (.daily, "Day"), (.weekly, "Week"), (.monthly, "Month"), (.yearly, "Year")
        ]

        return timeframes.map { tf, title in
            var items: [ScheduledItemEntry] = []
            for task in matchingTasks where itemTimeframes[task.id]?.contains(tf) == true {
                items.append(.task(task, isNative: false, scheduleId: UUID(), sortOrder: 0))
            }
            for project in matchingProjects where itemTimeframes[project.id]?.contains(tf) == true {
                items.append(.project(project, isNative: false, scheduleId: UUID(), sortOrder: 0))
            }
            for list in matchingLists where itemTimeframes[list.id]?.contains(tf) == true {
                items.append(.list(list, isNative: false, scheduleId: UUID(), sortOrder: 0))
            }
            return ScheduledSection(
                id: "search-\(tf.rawValue)", title: title,
                isRange: false, isSubDate: false,
                items: items, date: nil, alwaysVisible: true
            )
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            mainContent
            overlayContent
        }
        .onChange(of: showingAddBar) { _, isShowing in
            if isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    addBarTitleFocused = true
                }
            }
        }
        .onChange(of: searchFieldFocused) { _, focused in
            if !focused && searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSearchActive = false
                }
            }
        }
        .task {
            taskListVM.scheduleFilter = .scheduled
            // Only show loading if no cached data
            if isEmpty {
                isLoading = true
            }
            await loadAllData()
            isLoading = false
        }
        // Sheets
        .sheet(item: $taskListVM.selectedTaskForDetails) { task in
            TaskDetailsDrawer(task: task, viewModel: taskListVM, categories: taskListVM.categories)
                .drawerStyle()
        }
        .sheet(item: $taskListVM.selectedTaskForSchedule) { task in
            ScheduleSelectionSheet(
                task: task,
                focusViewModel: focusViewModel
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
        .sheet(isPresented: $taskListVM.showBatchScheduleSheet) {
            BatchScheduleSheet(
                viewModel: taskListVM,
                onBatchSchedule: { tasks, timeframe, section, dates in
                    guard !dates.isEmpty else { return }
                    let repo = ScheduleRepository()
                    for task in tasks {
                        for date in dates {
                            let c = Schedule(
                                userId: task.userId, taskId: task.id,
                                timeframe: timeframe, section: section,
                                scheduleDate: Calendar.current.startOfDay(for: date),
                                sortOrder: 0
                            )
                            _Concurrency.Task { _ = try? await repo.createSchedule(c) }
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
            Text("This will permanently delete the selected items and their schedules.")
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
            } else if searchIsEmpty {
                VStack(spacing: AppStyle.Spacing.tiny) {
                    Text("No results")
                        .font(AppStyle.Typography.emptyTitle)
                    Text("No items match \"\(searchText)\"")
                        .font(AppStyle.Typography.emptySubtitle)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, AppStyle.Spacing.page)
            } else {
                itemList
            }
        }
    }

    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: AppStyle.Spacing.medium) {
            HStack(alignment: .center, spacing: AppStyle.Spacing.compact) {
                Image(systemName: "calendar")
                    .font(.helveticaNeue(size: 15, weight: .medium))
                    .foregroundColor(.appRed)
                    .frame(width: AppStyle.Layout.iconBadge, height: AppStyle.Layout.iconBadge)
                    .background(Color.scheduledBadge, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.iconBadge))

                Text("Scheduled")
                    .pageTitleStyle()
                    .foregroundColor(.primary)
                Spacer()
                if let dateText = scheduleDateText {
                    Button {
                        showCalendarPicker = true
                    } label: {
                        HStack(spacing: AppStyle.Spacing.tiny) {
                            Text(dateText)
                                .font(.inter(.subheadline, weight: .medium))
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(AppStyle.Typography.chevron)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: AppStyle.Spacing.small) {
                ForEach(ScheduleViewMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewMode = mode
                        }
                    } label: {
                        Text(mode.label)
                            .font(.helveticaNeue(size: 13, weight: .medium))
                            .tracking(-0.135)
                            .foregroundColor(viewMode == mode ? .white : .appText)
                            .padding(.horizontal, AppStyle.Spacing.content)
                            .padding(.vertical, AppStyle.Spacing.small)
                            .background(
                                viewMode == mode ? Color.appRed : Color.categoryBackground,
                                in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card)
                                    .stroke(viewMode == mode ? Color.clear : Color.cardBorder, lineWidth: AppStyle.Border.thin)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSearchActive.toggle()
                        if !isSearchActive {
                            searchText = ""
                            searchFieldFocused = false
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                searchFieldFocused = true
                            }
                        }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(.primary)
                        .frame(width: AppStyle.Layout.compactButton, height: AppStyle.Layout.compactButton)
                        .background(Color.pillBackground, in: Circle())
                }
                .accessibilityLabel("Search")
            }

            if isSearchActive {
                HStack(spacing: AppStyle.Spacing.compact) {
                    Image(systemName: "magnifyingglass")
                        .font(.inter(.subheadline))
                        .foregroundColor(.secondary)

                    TextField("Search scheduled items...", text: $searchText)
                        .font(.inter(.body))
                        .textFieldStyle(.plain)
                        .focused($searchFieldFocused)
                        .submitLabel(.search)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.inter(.subheadline))
                                .foregroundColor(.secondary)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, AppStyle.Spacing.comfortable)
                .padding(.vertical, AppStyle.Spacing.compact)
                .background(Color.pillBackground, in: Capsule())
                .transition(.opacity)
            }
        }
        .padding(.horizontal, AppStyle.Spacing.page)
        .padding(.top, AppStyle.Spacing.section)
        .padding(.bottom, AppStyle.Spacing.tiny)
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
        VStack(spacing: AppStyle.Spacing.tiny) {
            Text("No scheduled items")
                .font(AppStyle.Typography.emptyTitle)
            Text("Scheduled tasks, lists, and projects will appear here")
                .font(AppStyle.Typography.emptySubtitle)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, AppStyle.Spacing.page)
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
        .transition(.opacity)
    }

    @ViewBuilder
    private var addBarOverlay: some View {
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
                        dismissAddBar()
                    }
                }
            addTaskBar
                .padding(.bottom, AppStyle.Spacing.compact)
                .contentShape(Rectangle())
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(100)
    }

    // MARK: - Item List

    private var itemList: some View {
        List {
            ForEach(flattenedItems) { flatItem in
                switch flatItem {
                case .sectionHeader(let section):
                    dateSectionHeader(for: section)
                        .moveDisabled(true)

                case .item(let entry):
                    scheduledItemRow(entry)

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

                case .addButton(let date):
                    addButtonForDay(date: date)
                        .moveDisabled(true)

                case .dropZone(let section):
                    HStack(spacing: 0) {
                        Text(section.title)
                            .font(.inter(size: 16, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.5))
                        Spacer()
                        Text("Drop here")
                            .font(.inter(.caption, weight: .light))
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let date = section.date {
                            addTaskDates = [date]
                            addTaskTimeframe = viewMode.timeframe
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showingAddBar = true
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: AppStyle.Spacing.expanded, bottom: 0, trailing: AppStyle.Spacing.page))
                    .listRowSeparator(.visible, edges: .bottom)
                    .listRowBackground(Color.clear)
                    // No .moveDisabled — acts as a valid drop target for empty sections

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
                handleFlatMove(from: from, to: to)
            }

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
                        .font(AppStyle.Typography.sectionHeader)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.vertical, AppStyle.Spacing.small)
                .padding(.horizontal, AppStyle.Spacing.tiny)

                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
            }
            .padding(.top, AppStyle.Spacing.section)
            .listRowInsets(AppStyle.Insets.row)
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
            .padding(.top, AppStyle.Spacing.medium)
            .padding(.bottom, AppStyle.Spacing.micro)
            .listRowInsets(EdgeInsets(top: 0, leading: 28, bottom: 0, trailing: AppStyle.Spacing.page))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            // Day header: "Today", "Tomorrow", "Thu Mar 5"
            VStack(spacing: 0) {
                HStack {
                    Text(section.title)
                        .font(AppStyle.Typography.sectionHeader)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.vertical, AppStyle.Spacing.small)
                .padding(.horizontal, AppStyle.Spacing.tiny)

                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
            }
            .opacity(section.items.isEmpty && section.alwaysVisible ? 0.35 : 1.0)
            .padding(.top, section.id.hasPrefix("day-0-") ? 0 : AppStyle.Spacing.compact)
            .listRowInsets(AppStyle.Insets.row)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Unified Item Row

    @ViewBuilder
    private func scheduledItemRow(_ entry: ScheduledItemEntry) -> some View {
        HStack(spacing: 0) {
            if entry.isNative {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.appRed)
                    .frame(width: 3)
                    .padding(.vertical, AppStyle.Spacing.small)
                    .padding(.trailing, AppStyle.Spacing.compact)
            }

            Group {
                switch entry {
                case .task(let task, _, let scheduleId, _):
                    FlatTaskRow(
                        task: task,
                        viewModel: taskListVM,
                        isEditMode: taskListVM.isEditMode,
                        isSelected: taskListVM.selectedTaskIds.contains(task.id),
                        onSelectToggle: { taskListVM.toggleTaskSelection(task.id) },
                        onToggleCompletion: { t in taskListVM.requestToggleCompletion(t) },
                        onReschedule: {
                            fetchAndReschedule(taskId: task.id, scheduleId: scheduleId)
                        },
                        onPushToTomorrow: {
                            pushItemToTomorrow(taskId: task.id, scheduleId: scheduleId)
                        },
                        onUnschedule: {
                            unscheduleItem(scheduleId: scheduleId)
                        }
                    )

                case .project(let project, _, let scheduleId, _):
                    ScheduledProjectRow(
                        project: project,
                        isPending: taskListVM.isPendingCompletion(project.id),
                        isEditMode: taskListVM.isEditMode,
                        isSelected: taskListVM.selectedTaskIds.contains(project.id),
                        onSelectToggle: { taskListVM.toggleTaskSelection(project.id) },
                        onTap: { selectedProjectForNavigation = project },
                        onToggleCompletion: {
                            taskListVM.requestExternalCompletion(id: project.id) {
                                try? await TaskRepository().completeTask(id: project.id)
                                await projectsVM.fetchProjects()
                            }
                        },
                        onEdit: { projectsVM.selectedProjectForDetails = project },
                        onReschedule: { fetchAndReschedule(taskId: project.id, scheduleId: scheduleId) },
                        onPushToTomorrow: {
                            pushItemToTomorrow(taskId: project.id, scheduleId: scheduleId)
                        },
                        onUnschedule: { unscheduleItem(scheduleId: scheduleId) },
                        onDelete: {
                            await projectsVM.deleteProject(project)
                            await refreshAllData()
                        }
                    )

                case .list(let list, _, let scheduleId, _):
                    ScheduledListRow(
                        list: list,
                        isPending: taskListVM.isPendingCompletion(list.id),
                        isEditMode: taskListVM.isEditMode,
                        isSelected: taskListVM.selectedTaskIds.contains(list.id),
                        onSelectToggle: { taskListVM.toggleTaskSelection(list.id) },
                        onTap: { selectedListForNavigation = list },
                        onToggleCompletion: {
                            taskListVM.requestExternalCompletion(id: list.id) {
                                try? await TaskRepository().completeTask(id: list.id)
                                await listsVM.fetchLists()
                            }
                        },
                        onEdit: { listsVM.selectedListForDetails = list },
                        onReschedule: { fetchAndReschedule(taskId: list.id, scheduleId: scheduleId) },
                        onPushToTomorrow: {
                            pushItemToTomorrow(taskId: list.id, scheduleId: scheduleId)
                        },
                        onUnschedule: { unscheduleItem(scheduleId: scheduleId) },
                        onDelete: {
                            await listsVM.deleteList(list)
                            await refreshAllData()
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: entry.isNative ? AppStyle.Spacing.comfortable : AppStyle.Spacing.page, bottom: 0, trailing: AppStyle.Spacing.page))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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
                .foregroundColor(.secondary.opacity(0.5))
        }
        .accessibilityLabel("Add task")
        .buttonStyle(.plain)
        .padding(.vertical, AppStyle.Spacing.tiny)
        .listRowInsets(AppStyle.Insets.row)
        .listRowSeparator(.visible)
        .listRowBackground(Color.clear)
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        async let c: () = taskListVM.fetchScheduledTaskIds()
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
            let repo = ScheduleRepository()
            let summaries = try await repo.fetchScheduleSummaries()
            let calendar = Calendar.current
            var schedulesByTask: [UUID: [(scheduleId: UUID, date: Date, timeframe: Timeframe, sortOrder: Int)]] = [:]
            var timeframesByTask: [UUID: Set<Timeframe>] = [:]
            for s in summaries {
                let date = calendar.startOfDay(for: s.scheduleDate)
                schedulesByTask[s.taskId, default: []].append((scheduleId: s.id, date: date, timeframe: s.timeframe, sortOrder: s.sortOrder))
                timeframesByTask[s.taskId, default: []].insert(s.timeframe)
            }
            itemSchedules = schedulesByTask
            itemTimeframes = timeframesByTask
        } catch { }
    }

    private func refreshAllData() async {
        await loadAllData()
    }

    private func pushItemToTomorrow(taskId: UUID, scheduleId: UUID) {
        _Concurrency.Task {
            let schedules = try? await ScheduleRepository().fetchSchedules(forTask: taskId)
            if let schedule = schedules?.first(where: { $0.id == scheduleId }) {
                let _ = await focusViewModel.pushScheduleToNext(schedule)
                await refreshAllData()
            }
        }
    }

    private func fetchAndReschedule(taskId: UUID, scheduleId: UUID) {
        _Concurrency.Task {
            let schedules = try? await ScheduleRepository().fetchSchedules(forTask: taskId)
            if let schedule = schedules?.first(where: { $0.id == scheduleId }) {
                selectedScheduleForReschedule = schedule
            }
        }
    }

    private func unscheduleItem(scheduleId: UUID) {
        _Concurrency.Task {
            try? await ScheduleRepository().deleteSchedule(id: scheduleId)
            await refreshAllData()
            await focusViewModel.fetchSchedules()
        }
    }

    // MARK: - Reorder

    private func handleFlatMove(from source: IndexSet, to destination: Int) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            performFlatMove(from: source, to: destination)
        }
    }

    private func performFlatMove(from source: IndexSet, to destination: Int) {
        let flat = flattenedItems
        guard let fromIdx = source.first else { return }

        // Only .item entries can be moved
        guard case .item(let movedEntry) = flat[fromIdx] else { return }

        // Find source section by scanning backward for nearest section boundary
        var sourceSection: ScheduledSection?
        for i in stride(from: fromIdx, through: 0, by: -1) {
            if let section = flat[i].boundarySection {
                sourceSection = section
                break
            }
        }

        // Find destination section by scanning backward from destination
        var destSection: ScheduledSection?
        let destLookup = max(0, min(destination - 1, flat.count - 1))
        for i in stride(from: destLookup, through: 0, by: -1) {
            if let section = flat[i].boundarySection {
                destSection = section
                break
            }
        }

        // Fix for upward moves into empty sections: drop zones replace sectionHeaders,
        // so destination points AT the drop zone but destination-1 misses it.
        if destination < fromIdx, destination < flat.count,
           case .dropZone(let s) = flat[destination] {
            destSection = s
        }

        guard let sourceSection, let destSection else { return }

        if sourceSection.id == destSection.id {
            // Same section — reorder within
            handleWithinSectionMove(movedEntry: movedEntry, section: sourceSection, flat: flat, fromIdx: fromIdx, destination: destination)
        } else {
            // Cross-section — change scheduled date
            handleCrossSectionMove(movedEntry: movedEntry, sourceSection: sourceSection, destSection: destSection, flat: flat, destination: destination)
        }
    }

    private func handleWithinSectionMove(movedEntry: ScheduledItemEntry, section: ScheduledSection, flat: [ScheduledFlatItem], fromIdx: Int, destination: Int) {
        // Collect all .item entries in this section with their flat indices
        let sectionItems = flat.enumerated().compactMap { (i, flatItem) -> (flatIdx: Int, entry: ScheduledItemEntry)? in
            guard case .item(let entry) = flatItem else { return nil }
            // Check if this item belongs to this section by scanning backward
            for j in stride(from: i, through: 0, by: -1) {
                if let s = flat[j].boundarySection {
                    return s.id == section.id ? (i, entry) : nil
                }
            }
            return nil
        }

        guard let itemFrom = sectionItems.firstIndex(where: { $0.entry.id == movedEntry.id }) else { return }

        var itemTo = sectionItems.count
        for (ci, entry) in sectionItems.enumerated() {
            if destination <= entry.flatIdx {
                itemTo = ci
                break
            }
        }
        if itemTo > itemFrom { itemTo = min(itemTo, sectionItems.count) }

        guard itemFrom != itemTo && itemFrom + 1 != itemTo else { return }

        var items = sectionItems.map { $0.entry }
        items.move(fromOffsets: IndexSet(integer: itemFrom), toOffset: itemTo)

        // Assign sequential sort orders (1-based)
        var updates: [(id: UUID, sortOrder: Int)] = []
        for (index, entry) in items.enumerated() {
            let newOrder = index + 1
            updates.append((id: entry.scheduleId, sortOrder: newOrder))
            updateLocalSortOrder(taskId: entry.id, scheduleId: entry.scheduleId, sortOrder: newOrder)
        }

        _Concurrency.Task {
            let repo = ScheduleRepository()
            try? await repo.updateScheduleSortOrders(updates)
        }
    }

    private func handleCrossSectionMove(movedEntry: ScheduledItemEntry, sourceSection: ScheduledSection, destSection: ScheduledSection, flat: [ScheduledFlatItem], destination: Int) {
        guard let targetDate = destSection.date else { return }

        let calendar = Calendar.current
        let newDate = calendar.startOfDay(for: targetDate)

        // Collect destination section items to determine insert position
        let destItems = flat.enumerated().compactMap { (i, flatItem) -> (flatIdx: Int, entry: ScheduledItemEntry)? in
            guard case .item(let entry) = flatItem else { return nil }
            for j in stride(from: i, through: 0, by: -1) {
                if case .sectionHeader(let s) = flat[j] {
                    return s.id == destSection.id ? (i, entry) : nil
                }
            }
            return nil
        }

        var insertAt = destItems.count
        for (ci, entry) in destItems.enumerated() {
            if destination <= entry.flatIdx {
                insertAt = ci
                break
            }
        }

        // Update local state: change the schedule's date
        if var entries = itemSchedules[movedEntry.id] {
            if let idx = entries.firstIndex(where: { $0.scheduleId == movedEntry.scheduleId }) {
                entries[idx].date = newDate
                entries[idx].sortOrder = insertAt + 1
                itemSchedules[movedEntry.id] = entries
            }
        }

        // Re-number sort orders for all items now in the destination section
        // (rebuild from updated itemSchedules)
        let updatedFlat = flattenedItems
        let newDestItems = updatedFlat.enumerated().compactMap { (i, flatItem) -> ScheduledItemEntry? in
            guard case .item(let entry) = flatItem else { return nil }
            for j in stride(from: i, through: 0, by: -1) {
                if let s = updatedFlat[j].boundarySection {
                    return s.id == destSection.id ? entry : nil
                }
            }
            return nil
        }

        var sortUpdates: [(id: UUID, sortOrder: Int)] = []
        for (index, entry) in newDestItems.enumerated() {
            let newOrder = index + 1
            updateLocalSortOrder(taskId: entry.id, scheduleId: entry.scheduleId, sortOrder: newOrder)
            sortUpdates.append((id: entry.scheduleId, sortOrder: newOrder))
        }

        // Also re-number source section
        let sourceItems = updatedFlat.enumerated().compactMap { (i, flatItem) -> ScheduledItemEntry? in
            guard case .item(let entry) = flatItem else { return nil }
            for j in stride(from: i, through: 0, by: -1) {
                if let s = updatedFlat[j].boundarySection {
                    return s.id == sourceSection.id ? entry : nil
                }
            }
            return nil
        }

        for (index, entry) in sourceItems.enumerated() {
            let newOrder = index + 1
            updateLocalSortOrder(taskId: entry.id, scheduleId: entry.scheduleId, sortOrder: newOrder)
            sortUpdates.append((id: entry.scheduleId, sortOrder: newOrder))
        }

        // Persist: date change + sort orders
        let movedScheduleId = movedEntry.scheduleId
        _Concurrency.Task {
            let repo = ScheduleRepository()
            try? await repo.updateScheduleDateAndSortOrder(id: movedScheduleId, date: newDate, sortOrder: insertAt + 1)
            try? await repo.updateScheduleSortOrders(sortUpdates)
        }
    }

    private func updateLocalSortOrder(taskId: UUID, scheduleId: UUID, sortOrder: Int) {
        if var entries = itemSchedules[taskId] {
            if let idx = entries.firstIndex(where: { $0.scheduleId == scheduleId }) {
                entries[idx].sortOrder = sortOrder
                itemSchedules[taskId] = entries
            }
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
                title: title, categoryId: categoryId, priority: priority,
                subtaskTitles: subtasksToCreate, scheduleAfterCreate: scheduleEnabled,
                selectedTimeframe: timeframe, selectedSection: section,
                selectedDates: dates, hasScheduledTime: false, scheduledTime: nil
            )
            if scheduleEnabled && !dates.isEmpty {
                await focusViewModel.fetchSchedules()
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
        addTaskScheduleExpanded = false
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
            if addTaskScheduleExpanded {
                addBarScheduleSection
            }
            if !addTaskScheduleExpanded {
                addBarButtonRow
            }
            if addTaskOptionsExpanded && !addTaskScheduleExpanded {
                addBarOptionsRow
            }
            Spacer().frame(height: AppStyle.Spacing.page)
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
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.top, AppStyle.Spacing.page)
            .padding(.bottom, AppStyle.Spacing.medium)
    }

    var addBarScheduleSection: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, AppStyle.Spacing.content)

            VStack(alignment: .leading, spacing: AppStyle.Spacing.comfortable) {
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
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.top, AppStyle.Spacing.small)
            .padding(.bottom, AppStyle.Spacing.content)

            addBarScheduleButtons
        }
    }

    var addBarScheduleButtons: some View {
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
                    .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                    .background(Color(.systemGray4), in: Circle())
            }
            .accessibilityLabel("Clear schedule")
            .buttonStyle(.plain)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    addTaskScheduleExpanded = false
                }
            } label: {
                let hasDateChanges = addTaskDates != addTaskDatesSnapshot
                Image(systemName: "checkmark")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(hasDateChanges ? .white : .secondary)
                    .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                    .background(hasDateChanges ? Color.appRed : Color(.systemGray4), in: Circle())
            }
            .accessibilityLabel("Confirm schedule")
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppStyle.Spacing.content)
        .padding(.bottom, AppStyle.Spacing.tiny)
    }

    var addBarButtonRow: some View {
        HStack(spacing: AppStyle.Spacing.compact) {
            Button { addNewSubtask() } label: {
                HStack(spacing: AppStyle.Spacing.tiny) {
                    Image(systemName: "plus").font(.inter(.caption))
                    Text("Sub-task").font(.inter(.caption))
                }
                .foregroundColor(.white)
                .padding(.horizontal, AppStyle.Spacing.medium)
                .padding(.vertical, AppStyle.Spacing.compact)
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
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(Color.white, in: Capsule())
            }
            .accessibilityLabel("More options")
            .buttonStyle(.plain)

            Spacer()

            Button { generateBreakdown() } label: {
                HStack(spacing: AppStyle.Spacing.small) {
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
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.vertical, AppStyle.Spacing.compact)
                .background(!isAddTaskTitleEmpty ? Color.pillBackground : Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isAddTaskTitleEmpty || isGeneratingBreakdown)

            Button { saveTask() } label: {
                Image(systemName: "checkmark")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(isAddTaskTitleEmpty ? .secondary : .white)
                    .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                    .background(isAddTaskTitleEmpty ? Color(.systemGray4) : Color.focusBlue, in: Circle())
            }
            .accessibilityLabel("Save task")
            .buttonStyle(.plain)
            .disabled(isAddTaskTitleEmpty)
        }
        .padding(.horizontal, AppStyle.Spacing.content)
        .padding(.bottom, AppStyle.Spacing.tiny)
    }

    var addBarOptionsRow: some View {
        HStack(spacing: AppStyle.Spacing.compact) {
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
                HStack(spacing: AppStyle.Spacing.tiny) {
                    Image(systemName: "folder").font(.inter(.caption))
                    Text(LocalizedStringKey(categoryPillLabel)).font(.inter(.caption))
                }
                .foregroundColor(.black)
                .padding(.horizontal, AppStyle.Spacing.medium)
                .padding(.vertical, AppStyle.Spacing.compact)
                .background(Color.white, in: Capsule())
            }

            Button {
                if !addTaskScheduleExpanded { addTaskDatesSnapshot = addTaskDates }
                withAnimation(.easeInOut(duration: 0.2)) { addTaskScheduleExpanded.toggle() }
            } label: {
                HStack(spacing: AppStyle.Spacing.tiny) {
                    Image(systemName: "arrow.right.circle").font(.inter(.caption))
                    Text("Schedule").font(.inter(.caption))
                }
                .foregroundColor(!addTaskDates.isEmpty ? .white : .black)
                .padding(.horizontal, AppStyle.Spacing.medium)
                .padding(.vertical, AppStyle.Spacing.compact)
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
                HStack(spacing: AppStyle.Spacing.tiny) {
                    Circle().fill(addTaskPriority.dotColor).frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)
                    Text(addTaskPriority.displayName).font(.inter(.caption))
                }
                .foregroundColor(.black)
                .padding(.horizontal, AppStyle.Spacing.medium)
                .padding(.vertical, AppStyle.Spacing.compact)
                .background(Color.white, in: Capsule())
            }

            Spacer()
        }
        .padding(.horizontal, AppStyle.Spacing.content)
        .padding(.top, AppStyle.Spacing.small)
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
                    .frame(width: AppStyle.Layout.touchTarget, height: AppStyle.Layout.touchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
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
                .frame(width: AppStyle.Layout.compactButton, height: AppStyle.Layout.compactButton)
                .background(Color.pillBackground, in: Circle())
        }
        .accessibilityLabel("More options")
    }
}

// MARK: - Data Models

private enum ScheduledItemEntry: Identifiable {
    case task(FocusTask, isNative: Bool, scheduleId: UUID, sortOrder: Int)
    case project(FocusTask, isNative: Bool, scheduleId: UUID, sortOrder: Int)
    case list(FocusTask, isNative: Bool, scheduleId: UUID, sortOrder: Int)

    var id: UUID {
        switch self {
        case .task(let t, _, _, _): return t.id
        case .project(let p, _, _, _): return p.id
        case .list(let l, _, _, _): return l.id
        }
    }

    var isNative: Bool {
        switch self {
        case .task(_, let n, _, _), .project(_, let n, _, _), .list(_, let n, _, _): return n
        }
    }

    var scheduleId: UUID {
        switch self {
        case .task(_, _, let sid, _), .project(_, _, let sid, _), .list(_, _, let sid, _): return sid
        }
    }

    var sortOrder: Int {
        switch self {
        case .task(_, _, _, let so), .project(_, _, _, let so), .list(_, _, _, let so): return so
        }
    }

    var createdDate: Date {
        switch self {
        case .task(let t, _, _, _): return t.createdDate
        case .project(let p, _, _, _): return p.createdDate
        case .list(let l, _, _, _): return l.createdDate
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

    /// Stable sort: by type, then native-first, then by creation date (oldest first), then UUID tiebreaker
    static func stableSort(_ a: ScheduledItemEntry, _ b: ScheduledItemEntry) -> Bool {
        if a.typeSortOrder != b.typeSortOrder { return a.typeSortOrder < b.typeSortOrder }
        if a.isNative != b.isNative { return a.isNative && !b.isNative }
        if a.createdDate != b.createdDate { return a.createdDate < b.createdDate }
        return a.id.uuidString < b.id.uuidString
    }

    /// Sort for display: use sort order if any item has been manually reordered, otherwise type-based
    static func sortForDisplay(_ items: [ScheduledItemEntry]) -> [ScheduledItemEntry] {
        let allZero = items.allSatisfy { $0.sortOrder == 0 }
        if allZero {
            return items.sorted(by: stableSort)
        } else {
            return items.sorted { a, b in
                if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
                return stableSort(a, b)
            }
        }
    }
}

private struct ScheduledSection: Identifiable {
    let id: String
    let title: String
    let isRange: Bool
    let isSubDate: Bool
    var items: [ScheduledItemEntry]
    let date: Date?
    let alwaysVisible: Bool
}

private enum ScheduledFlatItem: Identifiable {
    case sectionHeader(ScheduledSection)
    case item(ScheduledItemEntry)
    case subtask(FocusTask, parentId: UUID)
    case inlineAddSubtask(parentId: UUID)
    case addButton(Date)
    case dropZone(ScheduledSection)
    case bottomSpacer

    var id: String {
        switch self {
        case .sectionHeader(let s): return "header-\(s.id)"
        case .item(let e): return "item-\(e.id.uuidString)"
        case .subtask(let t, _): return "subtask-\(t.id.uuidString)"
        case .inlineAddSubtask(let pid): return "add-subtask-\(pid.uuidString)"
        case .addButton(let d): return "add-\(Int(d.timeIntervalSince1970))"
        case .dropZone(let s): return "dropzone-\(s.id)"
        case .bottomSpacer: return "bottom-spacer"
        }
    }

    /// Returns the section if this is a section boundary (header or drop zone)
    var boundarySection: ScheduledSection? {
        switch self {
        case .sectionHeader(let s), .dropZone(let s): return s
        default: return nil
        }
    }
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

    /// Timeframes that should be visible at this view level
    var allowedTimeframes: Set<Timeframe> {
        switch self {
        case .day: return [.daily]
        case .week: return [.daily, .weekly]
        case .month: return [.daily, .weekly, .monthly]
        case .year: return [.daily, .weekly, .monthly, .yearly]
        }
    }
}

// MARK: - Scheduled Project Row

private struct ScheduledProjectRow: View {
    let project: FocusTask
    var isPending: Bool = false
    var isEditMode: Bool
    var isSelected: Bool
    var onSelectToggle: () -> Void
    var onTap: () -> Void
    var onToggleCompletion: () -> Void
    var onEdit: () -> Void
    var onReschedule: () -> Void
    var onPushToTomorrow: () -> Void
    var onUnschedule: () -> Void
    var onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(isSelected ? .appRed : .secondary)
                    .accessibilityLabel(isSelected ? "Selected" : "Select")
            }
            Image(systemName: "folder")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: AppStyle.Layout.pillButton)
            Text(project.title)
                .font(.inter(.body))
                .strikethrough(isPending)
                .foregroundColor(isPending ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            if !isEditMode {
                Button {
                    UIImpactFeedbackGenerator(style: isPending ? .light : .medium).impactOccurred()
                    onToggleCompletion()
                } label: {
                    Image(systemName: isPending ? "checkmark.circle.fill" : "circle")
                        .font(.inter(.title3))
                        .foregroundColor(isPending ? Color.focusBlue.opacity(0.6) : .gray)
                        .symbolEffect(.pulse, isActive: isPending)
                }
                .accessibilityLabel(isPending ? "Completed" : "Mark complete")
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, AppStyle.Spacing.compact)
        .contentShape(Rectangle())
        .onTapGesture { if isEditMode { onSelectToggle() } else { onTap() } }
        .contextMenu {
            if !isEditMode {
                ContextMenuItems.editButton { onEdit() }
                ContextMenuItems.rescheduleButton { onReschedule() }
                ContextMenuItems.pushToTomorrowButton { onPushToTomorrow() }
                ContextMenuItems.unscheduleButton { onUnschedule() }
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
    var isPending: Bool = false
    var isEditMode: Bool
    var isSelected: Bool
    var onSelectToggle: () -> Void
    var onTap: () -> Void
    var onToggleCompletion: () -> Void
    var onEdit: () -> Void
    var onReschedule: () -> Void
    var onPushToTomorrow: () -> Void
    var onUnschedule: () -> Void
    var onDelete: () async -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.inter(.title3))
                    .foregroundColor(isSelected ? .appRed : .secondary)
                    .accessibilityLabel(isSelected ? "Selected" : "Select")
            }
            Image(systemName: "list.bullet")
                .font(.inter(.body, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: AppStyle.Layout.pillButton)
            Text(list.title)
                .font(.inter(.body))
                .strikethrough(isPending)
                .foregroundColor(isPending ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            if !isEditMode {
                Button {
                    UIImpactFeedbackGenerator(style: isPending ? .light : .medium).impactOccurred()
                    onToggleCompletion()
                } label: {
                    Image(systemName: isPending ? "checkmark.circle.fill" : "circle")
                        .font(.inter(.title3))
                        .foregroundColor(isPending ? Color.focusBlue.opacity(0.6) : .gray)
                        .symbolEffect(.pulse, isActive: isPending)
                }
                .accessibilityLabel(isPending ? "Completed" : "Mark complete")
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, AppStyle.Spacing.compact)
        .contentShape(Rectangle())
        .onTapGesture { if isEditMode { onSelectToggle() } else { onTap() } }
        .contextMenu {
            if !isEditMode {
                ContextMenuItems.editButton { onEdit() }
                ContextMenuItems.rescheduleButton { onReschedule() }
                ContextMenuItems.pushToTomorrowButton { onPushToTomorrow() }
                ContextMenuItems.unscheduleButton { onUnschedule() }
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
