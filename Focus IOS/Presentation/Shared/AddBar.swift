//
//  AddBar.swift
//  Focus IOS
//

import SwiftUI
import Auth

// MARK: - Configuration

struct AddBarConfig {
    let availableModes: [TaskType]
    let showSchedule: Bool
    let showAIBreakdown: Bool
    let initialCategoryId: UUID?
    let initialDates: Set<Date>
    let initialTimeframe: Timeframe

    init(
        availableModes: [TaskType],
        showSchedule: Bool,
        showAIBreakdown: Bool,
        initialCategoryId: UUID? = nil,
        initialDates: Set<Date> = [],
        initialTimeframe: Timeframe = .daily
    ) {
        self.availableModes = availableModes
        self.showSchedule = showSchedule
        self.showAIBreakdown = showAIBreakdown
        self.initialCategoryId = initialCategoryId
        self.initialDates = initialDates
        self.initialTimeframe = initialTimeframe
    }

    static func categoryDetail(categoryId: UUID) -> AddBarConfig {
        AddBarConfig(availableModes: [.task, .list, .project], showSchedule: true, showAIBreakdown: true, initialCategoryId: categoryId)
    }

    static var today: AddBarConfig {
        let todayDate = Calendar.current.startOfDay(for: Date())
        return AddBarConfig(availableModes: [.task], showSchedule: true, showAIBreakdown: true, initialDates: [todayDate], initialTimeframe: .daily)
    }

    static var quickLists: AddBarConfig {
        AddBarConfig(availableModes: [.list], showSchedule: true, showAIBreakdown: false)
    }

    static var projectsList: AddBarConfig {
        AddBarConfig(availableModes: [.project], showSchedule: true, showAIBreakdown: false)
    }

    static func upcoming(initialDates: Set<Date> = [], initialTimeframe: Timeframe = .daily) -> AddBarConfig {
        AddBarConfig(availableModes: [.task], showSchedule: true, showAIBreakdown: true, initialDates: initialDates, initialTimeframe: initialTimeframe)
    }

    static var home: AddBarConfig {
        AddBarConfig(availableModes: [.task, .list, .project], showSchedule: true, showAIBreakdown: true)
    }

    static var backlog: AddBarConfig {
        AddBarConfig(availableModes: [.task], showSchedule: true, showAIBreakdown: true)
    }
}

// MARK: - Result Types

struct AddBarScheduleInfo {
    let dates: Set<Date>
    let timeframe: Timeframe
    let section: Section
    let notificationEnabled: Bool
    let notificationTime: Date
}

struct AddBarTaskResult {
    let title: String
    let subtaskTitles: [String]
    let categoryId: UUID?
    let priority: Priority
    let schedule: AddBarScheduleInfo?
}

struct AddBarListResult {
    let title: String
    let itemTitles: [String]
    let categoryId: UUID?
    let priority: Priority
    let schedule: AddBarScheduleInfo?
}

struct AddBarProjectResult {
    let title: String
    let draftTasks: [DraftTask]
    let categoryId: UUID?
    let priority: Priority
    let schedule: AddBarScheduleInfo?
}

enum AddBarResult {
    case task(AddBarTaskResult)
    case list(AddBarListResult)
    case project(AddBarProjectResult)
}

extension AddBarScheduleInfo {
    /// Persists notification to DB and schedules local notification for the given task.
    func scheduleNotificationIfNeeded(taskId: UUID, taskTitle: String) {
        guard notificationEnabled, let firstDate = dates.sorted().first else { return }
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: firstDate)
        let timeComps = cal.dateComponents([.hour, .minute], from: notificationTime)
        comps.hour = timeComps.hour
        comps.minute = timeComps.minute
        guard let notifDate = cal.date(from: comps) else { return }

        _Concurrency.Task {
            try? await TaskRepository().updateTaskNotification(
                id: taskId,
                enabled: true,
                date: notifDate
            )
        }
        NotificationService.shared.scheduleNotification(taskId: taskId, title: taskTitle, date: notifDate)
    }
}

// MARK: - AddBar View

struct AddBar: View {
    let config: AddBarConfig
    let categories: [Category]
    @Binding var activeMode: TaskType
    let onSave: (AddBarResult) -> Void
    let onDismiss: () -> Void

    // MARK: - Shared State

    @State private var title = ""
    @State private var categoryId: UUID?
    @State private var priority: Priority = .low
    @State private var optionsExpanded = false
    @State private var scheduleExpanded = false
    @State private var scheduleDates: Set<Date> = []
    @State private var scheduleDatesSnapshot: Set<Date> = []
    @State private var timeframe: Timeframe = .daily
    @State private var section: Section = .todo
    @State private var notificationEnabled = false
    @State private var notificationExpanded = false
    @State private var notificationTime: Date = {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 9
        comps.minute = 0
        return cal.date(from: comps) ?? Date()
    }()

    // Task mode
    @State private var subtasks: [DraftSubtaskEntry] = []
    @State private var isGeneratingBreakdown = false
    @State private var hasGeneratedBreakdown = false

    // List mode
    @State private var listItems: [DraftSubtaskEntry] = []

    // Project mode
    @State private var draftTasks: [DraftTask] = []

    @FocusState private var titleFocused: Bool
    @FocusState private var focusedSubItemId: UUID?

    private var isTitleEmpty: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var categoryPillLabel: String {
        if let categoryId,
           let category = categories.first(where: { $0.id == categoryId }) {
            return category.name
        }
        return "Category"
    }

    private var titlePlaceholder: String {
        switch activeMode {
        case .task, .goal: return "Create a new task"
        case .list: return "Create a new list"
        case .project: return "Create a new project"
        }
    }

    private var addButtonLabel: String {
        switch activeMode {
        case .task, .goal: return "Sub-task"
        case .list: return "Item"
        case .project: return "Task"
        }
    }

    private var hasSubItems: Bool {
        switch activeMode {
        case .task, .goal: return !subtasks.isEmpty
        case .list: return !listItems.isEmpty
        case .project: return !draftTasks.isEmpty
        }
    }

    private var subItemCount: Int {
        switch activeMode {
        case .task, .goal: return subtasks.count
        case .list: return listItems.count
        case .project: return draftTasks.count
        }
    }

    private var subItemSummaryLabel: String {
        switch activeMode {
        case .task, .goal: return subItemCount == 1 ? "subtask" : "subtasks"
        case .list: return subItemCount == 1 ? "item" : "items"
        case .project: return subItemCount == 1 ? "task" : "tasks"
        }
    }

    private var scheduleDateLabel: String {
        guard let date = scheduleDates.sorted().first else {
            return String(localized: "Date")
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return String(localized: "Today")
        } else if calendar.isDateInTomorrow(date) {
            return String(localized: "Tom")
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
                ? "MMM d"
                : "MMM d, yyyy"
            return formatter.string(from: date)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Mode selector (above the card)
            if config.availableModes.count > 1 {
                modeSelector
                    .padding(.vertical, AppStyle.Spacing.comfortable)
            }

            // Glass card
            VStack(spacing: 0) {
                // Title
                TextField(titlePlaceholder, text: $title)
                    .font(.inter(.title3))
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .submitLabel(.return)
                    .onSubmit { save() }
                    .padding(.horizontal, AppStyle.Spacing.content)
                    .padding(.top, AppStyle.Spacing.page)
                    .padding(.bottom, AppStyle.Spacing.page)

                // Content area - collapses when schedule picker is open
                if scheduleExpanded && hasSubItems {
                    collapsedItemsSummary
                } else {
                    contentArea
                }

                // Schedule expansion
                if config.showSchedule && scheduleExpanded {
                    scheduleSection
                }

                // Button row
                if !scheduleExpanded {
                    buttonRow
                }

                // Options row
                if optionsExpanded && !scheduleExpanded {
                    optionsRow
                }

                Spacer().frame(height: AppStyle.Spacing.medium)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            .padding(.horizontal)
        }
        .contentShape(Rectangle())
        .onAppear {
            if let initialCategoryId = config.initialCategoryId {
                categoryId = initialCategoryId
            }
            if !config.initialDates.isEmpty {
                scheduleDates = config.initialDates
                timeframe = config.initialTimeframe
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                titleFocused = true
            }
        }
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        HStack(spacing: AppStyle.Spacing.comfortable) {
            ForEach(config.availableModes, id: \.self) { mode in
                modeCircle(mode: mode)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private func modeCircle(mode: TaskType) -> some View {
        let isActive = activeMode == mode
        return Button {
            withAnimation(AppStyle.Anim.buttonTap) {
                activeMode = mode
            }
        } label: {
            Group {
                switch mode {
                case .project:
                    Image("ProjectIcon")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                case .task, .goal:
                    Image(systemName: "checkmark.circle")
                case .list:
                    Image(systemName: "checklist")
                }
            }
            .font(.inter(.body, weight: .medium))
            .foregroundColor(isActive ? .white : .primary)
            .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
            .glassEffect(
                isActive
                    ? .regular.tint(.black).interactive()
                    : .regular.interactive(),
                in: .rect(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch activeMode {
        case .task, .goal:
            DraftSubtaskListEditor(
                subtasks: $subtasks,
                focusedSubtaskId: $focusedSubItemId,
                onAddNew: { addNewSubItem() }
            )
        case .list:
            DraftSubtaskListEditor(
                subtasks: $listItems,
                focusedSubtaskId: $focusedSubItemId,
                onAddNew: { addNewSubItem() },
                placeholder: "Item"
            )
        case .project:
            projectDraftTasksArea
        }
    }

    // MARK: - Collapsed Items Summary

    private var collapsedItemsSummary: some View {
        HStack(spacing: AppStyle.Spacing.tiny) {
            Image(systemName: "chevron.right")
                .font(.inter(.caption2))
                .foregroundColor(.secondary)
            Text("\(subItemCount) \(subItemSummaryLabel)")
                .font(.inter(.subheadline))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, AppStyle.Spacing.content)
        .padding(.bottom, AppStyle.Spacing.small)
    }

    // MARK: - Project Draft Tasks

    @ViewBuilder
    private var projectDraftTasksArea: some View {
        if !draftTasks.isEmpty {
            Divider()
                .padding(.horizontal, AppStyle.Spacing.content)

            VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
                ForEach(draftTasks) { task in
                    projectTaskDraftRow(task: task)
                }
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.top, AppStyle.Spacing.compact)
            .padding(.bottom, AppStyle.Spacing.small)
        }
    }

    @ViewBuilder
    private func projectTaskDraftRow(task: DraftTask) -> some View {
        HStack(spacing: AppStyle.Spacing.compact) {
            Image(systemName: "circle")
                .font(.inter(.caption2))
                .foregroundColor(.secondary.opacity(0.5))

            TextField("Task", text: projectTaskBinding(for: task.id), axis: .vertical)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($focusedSubItemId, equals: task.id)
                .lineLimit(1...3)
                .onChange(of: projectTaskBinding(for: task.id).wrappedValue) { _, newValue in
                    if newValue.contains("\n") {
                        if let idx = draftTasks.firstIndex(where: { $0.id == task.id }) {
                            draftTasks[idx].title = newValue.replacingOccurrences(of: "\n", with: "")
                        }
                        addNewProjectSubtask(toTask: task.id)
                    }
                }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    draftTasks.removeAll { $0.id == task.id }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Remove task")
            .buttonStyle(.plain)
        }

        // Subtask rows
        ForEach(task.subtasks) { subtask in
            HStack(spacing: AppStyle.Spacing.compact) {
                Image(systemName: "circle")
                    .font(.inter(.caption2))
                    .foregroundColor(.secondary.opacity(0.5))

                TextField("Sub-task", text: projectSubtaskBinding(forSubtask: subtask.id, inTask: task.id), axis: .vertical)
                    .font(.inter(.body))
                    .textFieldStyle(.plain)
                    .focused($focusedSubItemId, equals: subtask.id)
                    .lineLimit(1...3)
                    .onChange(of: projectSubtaskBinding(forSubtask: subtask.id, inTask: task.id).wrappedValue) { _, newValue in
                        if newValue.contains("\n") {
                            if let tIdx = draftTasks.firstIndex(where: { $0.id == task.id }),
                               let sIdx = draftTasks[tIdx].subtasks.firstIndex(where: { $0.id == subtask.id }) {
                                draftTasks[tIdx].subtasks[sIdx].title = newValue.replacingOccurrences(of: "\n", with: "")
                            }
                            addNewProjectSubtask(toTask: task.id)
                        }
                    }

                Button {
                    guard let tIdx = draftTasks.firstIndex(where: { $0.id == task.id }) else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        draftTasks[tIdx].subtasks.removeAll { $0.id == subtask.id }
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.inter(.caption))
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Remove subtask")
                .buttonStyle(.plain)
            }
            .padding(.leading, 28)
            .padding(.trailing, AppStyle.Spacing.compact)
            .padding(.vertical, AppStyle.Spacing.small)
        }
        .padding(.top, AppStyle.Spacing.comfortable)

        // "+ Sub-task" button
        Button {
            addNewProjectSubtask(toTask: task.id)
        } label: {
            HStack(spacing: AppStyle.Spacing.tiny) {
                Image(systemName: "plus")
                    .font(.inter(.subheadline))
                Text("Sub-task")
                    .font(.inter(.subheadline))
            }
            .foregroundColor(.secondary)
            .padding(.vertical, AppStyle.Spacing.tiny)
        }
        .buttonStyle(.plain)
        .padding(.leading, 28)
        .padding(.top, AppStyle.Spacing.compact)
        .padding(.bottom, AppStyle.Spacing.small)
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, AppStyle.Spacing.content)

            if notificationExpanded {
                // Collapsed date summary row
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        notificationExpanded = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                            .font(.inter(.subheadline))
                            .foregroundColor(.secondary)
                            .frame(width: 24)

                        Text("Date")
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.primary)

                        Text(scheduleDateLabel)
                            .font(.inter(.body, weight: .medium))
                            .foregroundColor(.focusBlue)

                        Image(systemName: "chevron.down")
                            .font(.inter(.caption2))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(0))

                        Spacer()
                    }
                    .padding(.horizontal, AppStyle.Spacing.content)
                    .padding(.vertical, AppStyle.Spacing.comfortable)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: AppStyle.Spacing.comfortable) {
                    UnifiedCalendarPicker(
                        selectedDates: $scheduleDates,
                        selectedTimeframe: $timeframe
                    )
                }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.small)
                .padding(.bottom, AppStyle.Spacing.content)
            }

            NotificationToggleRow(
                isEnabled: $notificationEnabled,
                selectedTime: $notificationTime,
                isExpanded: $notificationExpanded
            )

            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scheduleDates.removeAll()
                        scheduleExpanded = false
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

                let hasDateChanges = scheduleDates != scheduleDatesSnapshot
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scheduleExpanded = false
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.inter(.body, weight: .semiBold))
                        .foregroundColor(hasDateChanges ? .white : .secondary)
                        .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                        .background(
                            hasDateChanges ? Color.focusBlue : Color(.systemGray4),
                            in: Circle()
                        )
                }
                .accessibilityLabel("Confirm schedule")
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.bottom, AppStyle.Spacing.tiny)
        }
    }

    // MARK: - Button Row

    private var buttonRow: some View {
        HStack(spacing: AppStyle.Spacing.compact) {
            // Add sub-item button
            Button {
                addNewSubItem()
            } label: {
                HStack(spacing: AppStyle.Spacing.tiny) {
                    Image(systemName: "plus")
                        .font(.inter(size: 14, weight: .semiBold))
                    Text(addButtonLabel)
                        .font(.inter(size: 14, weight: .semiBold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, AppStyle.Spacing.comfortable)
                .padding(.vertical, AppStyle.Spacing.medium)
                .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)

            // Schedule button
            if config.showSchedule {
                Button {
                    scheduleDatesSnapshot = scheduleDates
                    if !scheduleExpanded {
                        // Dismiss keyboard first, then expand schedule in one smooth step
                        titleFocused = false
                        focusedSubItemId = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scheduleExpanded = true
                            }
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scheduleExpanded = false
                        }
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        Image(systemName: "calendar")
                            .font(.inter(size: 14, weight: .semiBold))
                        Text(scheduleDateLabel)
                            .font(.inter(size: 14, weight: .semiBold))
                    }
                    .foregroundColor(!scheduleDates.isEmpty ? .focusBlue : .black)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.medium)
                    .background(!scheduleDates.isEmpty ? Color.todayBadge : Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            // Priority menu
            Menu {
                ForEach(Priority.allCases, id: \.self) { p in
                    Button {
                        priority = p
                    } label: {
                        if priority == p {
                            Label(p.displayName, systemImage: "checkmark")
                        } else {
                            Text(p.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: AppStyle.Spacing.tiny) {
                    Circle()
                        .fill(priority.dotColor)
                        .frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)
                    Text(priority.displayName)
                        .font(.inter(size: 14, weight: .semiBold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, AppStyle.Spacing.comfortable)
                .padding(.vertical, AppStyle.Spacing.medium)
                .background(Color.white, in: Capsule())
            }

            // More options
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    optionsExpanded.toggle()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.inter(size: 14, weight: .semiBold))
                    .foregroundColor(.black)
                    .frame(minHeight: UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
                    .padding(.horizontal, AppStyle.Spacing.medium)
                    .padding(.vertical, AppStyle.Spacing.medium)
                    .background(Color.white, in: Capsule())
            }
            .accessibilityLabel("More options")
            .buttonStyle(.plain)

            Spacer()

            // Save button
            Button {
                save()
            } label: {
                Image(systemName: "checkmark")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(isTitleEmpty ? .secondary : .white)
                    .frame(width: AppStyle.Layout.iconButton, height: AppStyle.Layout.iconButton)
                    .background(
                        isTitleEmpty ? Color(.systemGray4) : Color.focusBlue,
                        in: Circle()
                    )
            }
            .accessibilityLabel("Save")
            .buttonStyle(.plain)
            .disabled(isTitleEmpty)
        }
        .padding(.horizontal, AppStyle.Spacing.content)
        .padding(.bottom, AppStyle.Spacing.tiny)
    }

    // MARK: - Options Row

    private var optionsRow: some View {
        HStack(spacing: AppStyle.Spacing.compact) {
            // Category menu
            Menu {
                Button {
                    categoryId = nil
                } label: {
                    if categoryId == nil {
                        Label("None", systemImage: "checkmark")
                    } else {
                        Text("None")
                    }
                }
                ForEach(categories) { category in
                    Button {
                        categoryId = category.id
                    } label: {
                        if self.categoryId == category.id {
                            Label(category.name, systemImage: "checkmark")
                        } else {
                            Text(category.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: AppStyle.Spacing.tiny) {
                    Image(systemName: "folder")
                        .font(.inter(size: 14, weight: .semiBold))
                    Text(LocalizedStringKey(categoryPillLabel))
                        .font(.inter(size: 14, weight: .semiBold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, AppStyle.Spacing.comfortable)
                .padding(.vertical, AppStyle.Spacing.medium)
                .background(Color.white, in: Capsule())
            }

            // AI Breakdown (task mode only)
            if config.showAIBreakdown && (activeMode == .task || activeMode == .goal) {
                Button {
                    generateBreakdown()
                } label: {
                    HStack(spacing: AppStyle.Spacing.tiny) {
                        if isGeneratingBreakdown {
                            ProgressView()
                                .tint(.primary)
                        } else {
                            Image(systemName: hasGeneratedBreakdown ? "arrow.clockwise" : "sparkles")
                                .font(.inter(size: 14, weight: .semiBold))
                                .foregroundColor(!isTitleEmpty ? .blue : .primary)
                        }
                        Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Breakdown"))
                            .font(.inter(size: 14, weight: .semiBold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, AppStyle.Spacing.comfortable)
                    .padding(.vertical, AppStyle.Spacing.medium)
                    .background(
                        !isTitleEmpty ? Color.pillBackground : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(isTitleEmpty || isGeneratingBreakdown)
            }

            Spacer()
        }
        .padding(.horizontal, AppStyle.Spacing.content)
        .padding(.top, AppStyle.Spacing.small)
    }

    // MARK: - Save

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let catId = categoryId
        let pri = priority
        let scheduleInfo: AddBarScheduleInfo? = scheduleDates.isEmpty ? nil : AddBarScheduleInfo(
            dates: scheduleDates,
            timeframe: timeframe,
            section: section,
            notificationEnabled: notificationEnabled,
            notificationTime: notificationTime
        )

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let result: AddBarResult
        switch activeMode {
        case .task, .goal:
            let subtaskTitles = subtasks
                .map { $0.title.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            result = .task(AddBarTaskResult(
                title: trimmedTitle,
                subtaskTitles: subtaskTitles,
                categoryId: catId,
                priority: pri,
                schedule: scheduleInfo
            ))
        case .list:
            let itemTitles = listItems
                .map { $0.title.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            result = .list(AddBarListResult(
                title: trimmedTitle,
                itemTitles: itemTitles,
                categoryId: catId,
                priority: pri,
                schedule: scheduleInfo
            ))
        case .project:
            let tasks = draftTasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            result = .project(AddBarProjectResult(
                title: trimmedTitle,
                draftTasks: tasks,
                categoryId: catId,
                priority: pri,
                schedule: scheduleInfo
            ))
        }

        // Reset state
        titleFocused = true
        focusedSubItemId = nil
        title = ""
        subtasks = []
        listItems = []
        draftTasks = []
        scheduleDates = config.initialDates
        timeframe = config.initialTimeframe
        scheduleExpanded = false
        optionsExpanded = false
        notificationEnabled = false
        notificationExpanded = false
        priority = .low
        hasGeneratedBreakdown = false

        onSave(result)
    }

    // MARK: - Sub-Item Helpers

    private func addNewSubItem() {
        switch activeMode {
        case .task, .goal:
            let entry = DraftSubtaskEntry()
            withAnimation(.easeInOut(duration: 0.15)) {
                subtasks.append(entry)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedSubItemId = entry.id
            }
        case .list:
            let entry = DraftSubtaskEntry()
            withAnimation(.easeInOut(duration: 0.15)) {
                listItems.append(entry)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedSubItemId = entry.id
            }
        case .project:
            let newTask = DraftTask()
            withAnimation(.easeInOut(duration: 0.15)) {
                draftTasks.append(newTask)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedSubItemId = newTask.id
            }
        }
    }

    private func addNewProjectSubtask(toTask taskId: UUID) {
        guard let tIdx = draftTasks.firstIndex(where: { $0.id == taskId }) else { return }
        let newSubtask = DraftSubtask(title: "")
        withAnimation(.easeInOut(duration: 0.15)) {
            draftTasks[tIdx].subtasks.append(newSubtask)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedSubItemId = newSubtask.id
        }
    }

    // MARK: - Project Bindings

    private func projectTaskBinding(for taskId: UUID) -> Binding<String> {
        Binding(
            get: { draftTasks.first(where: { $0.id == taskId })?.title ?? "" },
            set: { newValue in
                if let idx = draftTasks.firstIndex(where: { $0.id == taskId }) {
                    draftTasks[idx].title = newValue
                }
            }
        )
    }

    private func projectSubtaskBinding(forSubtask subtaskId: UUID, inTask taskId: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let tIdx = draftTasks.firstIndex(where: { $0.id == taskId }),
                      let s = draftTasks[tIdx].subtasks.first(where: { $0.id == subtaskId })
                else { return "" }
                return s.title
            },
            set: { newValue in
                if let tIdx = draftTasks.firstIndex(where: { $0.id == taskId }),
                   let sIdx = draftTasks[tIdx].subtasks.firstIndex(where: { $0.id == subtaskId }) {
                    draftTasks[tIdx].subtasks[sIdx].title = newValue
                }
            }
        )
    }

    // MARK: - AI Breakdown

    private func generateBreakdown() {
        let taskTitle = title.trimmingCharacters(in: .whitespaces)
        guard !taskTitle.isEmpty else { return }
        isGeneratingBreakdown = true
        _Concurrency.Task { @MainActor in
            do {
                let aiService = AIService()
                let suggestions = try await aiService.generateSubtasks(title: taskTitle, description: nil)
                withAnimation(.easeInOut(duration: 0.2)) {
                    subtasks.append(contentsOf: suggestions.map { DraftSubtaskEntry(title: $0) })
                }
                hasGeneratedBreakdown = true
            } catch { }
            isGeneratingBreakdown = false
        }
    }
}
