//
//  TaskDetailsDrawer.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-05.
//

import SwiftUI

struct TaskDetailsDrawer<VM: TaskEditingViewModel>: View {
    let task: FocusTask
    let schedule: Schedule?
    let categories: [Category]
    @ObservedObject var viewModel: VM

    // Pending schedule interception (used by InboxView)
    var pendingSchedule: PendingScheduleInfo? = nil
    var onScheduleCallback: ((Timeframe, Section, Set<Date>) -> Void)? = nil
    var onClearSchedule: (() -> Void)? = nil

    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @EnvironmentObject var languageManager: LanguageManager
    @State private var taskTitle: String
    @State private var scheduleExpanded = false
    @State private var scheduleTimeframe: Timeframe = .daily
    @State private var scheduleSection: Section = .focus
    @State private var scheduleDates: Set<Date> = []
    @State private var originalScheduleDates: Set<Date> = []
    @State private var originalSchedules: [Schedule] = []
    @State private var hasExistingSchedules = false
    @State private var showingRescheduleSheet = false
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var newSubtaskTitle: String = ""
    @State private var showNewSubtaskField = false
    @State private var selectedCategoryId: UUID?
    @State private var selectedPriority: Priority
    @State private var noteText: String
    @State private var showingDeleteConfirmation = false
    @State private var isGeneratingBreakdown = false
    @State private var hasGeneratedBreakdown = false
    @State private var draftSuggestions: [DraftSubtaskEntry] = []
    @State private var pendingDeletions: Set<UUID> = []
    // Notification
    @State private var notificationEnabled: Bool = false
    @State private var notificationTime: Date = {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }()
    @FocusState private var isTitleFocused: Bool
    @FocusState private var focusedSubtaskId: UUID?
    @FocusState private var isNewSubtaskFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isSubtask: Bool {
        task.parentTaskId != nil
    }

    private var parentTask: FocusTask? {
        guard let parentId = task.parentTaskId else { return nil }
        return viewModel.findTask(byId: parentId)
    }

    private var subtasks: [FocusTask] {
        viewModel.getSubtasks(for: task.id)
            .filter { !pendingDeletions.contains($0.id) }
    }

    init(task: FocusTask, viewModel: VM, schedule: Schedule? = nil, categories: [Category] = [],
         pendingSchedule: PendingScheduleInfo? = nil,
         onSchedule: ((Timeframe, Section, Set<Date>) -> Void)? = nil,
         onClearSchedule: (() -> Void)? = nil) {
        self.task = task
        self.viewModel = viewModel
        self.schedule = schedule
        self.categories = categories
        self.pendingSchedule = pendingSchedule
        self.onScheduleCallback = onSchedule
        self.onClearSchedule = onClearSchedule
        _taskTitle = State(initialValue: task.title)
        _noteText = State(initialValue: task.description ?? "")
        _selectedCategoryId = State(initialValue: task.categoryId)
        _selectedPriority = State(initialValue: task.priority)
        _notificationEnabled = State(initialValue: task.notificationEnabled)
        if let notifDate = task.notificationDate {
            _notificationTime = State(initialValue: notifDate)
        }
    }

    private var schedulePillIsActive: Bool {
        !scheduleDates.isEmpty || hasExistingSchedules || pendingSchedule != nil
    }

    private var scheduleDateLabel: String {
        guard let date = scheduleDates.sorted().first else {
            return String(localized: "Date")
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return String(localized: "Today")
        } else if calendar.isDateInTomorrow(date) {
            return String(localized: "Tomorrow")
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
                ? "MMM d"
                : "MMM d, yyyy"
            return formatter.string(from: date)
        }
    }

    private var hasScheduleChanges: Bool {
        let currentDates = Set(scheduleDates.map { Calendar.current.startOfDay(for: $0) })
        return originalScheduleDates != currentDates
    }

    private var hasNoteChanges: Bool {
        noteText != (task.description ?? "")
    }

    private var hasNotificationChanges: Bool {
        notificationEnabled != task.notificationEnabled ||
        (notificationEnabled && !Calendar.current.isDate(notificationTime, equalTo: task.notificationDate ?? Date.distantPast, toGranularity: .minute))
    }

    private var hasChanges: Bool {
        taskTitle != task.title || selectedCategoryId != task.categoryId || selectedPriority != task.priority || !pendingDeletions.isEmpty || !newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty || !draftSuggestions.isEmpty || hasScheduleChanges || hasNoteChanges || hasNotificationChanges
    }

    var body: some View {
        DrawerContainer(
            title: isSubtask ? "Subtask Details" : "Task Details",
            leadingButton: .close { dismiss() },
            trailingButton: .check(action: {
                saveTitle()
                saveNote()
                saveCategory()
                savePriority()
                addSubtask()
                saveDraftSuggestions()
                savePendingDeletions()
                saveScheduleChanges()
                saveNotification()
                dismiss()
            }, highlighted: hasChanges)
        ) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: AppStyle.Spacing.comfortable) {
                        // ─── TITLE ───
                        titleCard

                        // ─── SUBTASKS ───
                        if !isSubtask {
                            subtasksCard
                        }

                        // ─── PILL ACTIONS ───
                        actionPillsRow

                        // ─── INLINE COMMIT ───
                        if scheduleExpanded {
                            inlineScheduleCard
                                .id("scheduleCard")
                        }

                        // ─── CONTEXTUAL ACTIONS ───
                        if contextualActionsVisible {
                            contextualActionsCard
                        }

                        // ─── NOTE ───
                        noteCard
                    }
                    .padding(.bottom, AppStyle.Spacing.page)
                }
                .onChange(of: scheduleExpanded) { _, expanded in
                    if expanded {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo("scheduleCard", anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: notificationEnabled) { _, enabled in
                    if enabled {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo("notificationTimePicker", anchor: .center)
                            }
                        }
                    }
                }
            }
            .background(.clear)
            .onChange(of: isTitleFocused) { _, isFocused in
                if isFocused && scheduleExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scheduleExpanded = false
                    }
                }
            }
            .onChange(of: isNewSubtaskFocused) { _, isFocused in
                if isFocused && scheduleExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scheduleExpanded = false
                    }
                }
            }
            .onChange(of: focusedSubtaskId) { _, subtaskId in
                if subtaskId != nil && scheduleExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scheduleExpanded = false
                    }
                }
            }
            .alert("New Category", isPresented: $showingNewCategoryAlert) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Create") { createAndMoveToCategory() }
            } message: {
                Text("Enter a name for the new category.")
            }
            .sheet(isPresented: $showingRescheduleSheet) {
                if let schedule = schedule {
                    rescheduleSheet(for: schedule)
                }
            }
            .alert(isSubtask ? "Delete subtask?" : "Delete task?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    _Concurrency.Task { @MainActor in
                        if isSubtask, let parentId = task.parentTaskId {
                            await viewModel.deleteSubtask(task, parentId: parentId)
                        } else if schedule != nil {
                            await focusViewModel.permanentlyDeleteTask(task)
                        } else {
                            await viewModel.deleteTask(task)
                        }
                        dismiss()
                    }
                }
            } message: {
                Text(isSubtask ? "This will permanently delete this subtask." : "This will permanently delete this task and all its schedules.")
            }
        }
    }

    // MARK: - Title Card

    @ViewBuilder
    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Task title", text: $taskTitle, axis: .vertical)
                .font(.inter(.title3))
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .onSubmit { saveTitle() }
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.vertical, AppStyle.Spacing.section)

            if isSubtask, let parent = parentTask {
                Text(parent.title)
                    .font(.inter(.caption))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, AppStyle.Spacing.content)
                    .padding(.top, -AppStyle.Spacing.compact)
                    .padding(.bottom, AppStyle.Spacing.comfortable)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Spacing.comfortable))
        .padding(.horizontal, AppStyle.Spacing.section)
        .padding(.top, AppStyle.Spacing.compact)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTitleFocused = true
            }
            checkExistingSchedules()
        }
    }

    // MARK: - Subtasks Card

    @ViewBuilder
    private var subtasksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: "Subtasks" label + "Break Down" button
            HStack {
                Text("Subtasks")
                    .font(.inter(.subheadline, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                if !task.isCompleted {
                    Button {
                        generateBreakdown()
                    } label: {
                        HStack(spacing: AppStyle.Spacing.small) {
                            if isGeneratingBreakdown {
                                ProgressView()
                                    .tint(.primary)
                            } else {
                                Image(systemName: hasGeneratedBreakdown ? "arrow.clockwise" : "sparkles")
                                    .symbolRenderingMode(.monochrome)
                                    .font(.inter(.subheadline, weight: .semiBold))
                            }
                            Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Breakdown"))
                                .font(.inter(.caption, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, AppStyle.Spacing.content)
                        .padding(.vertical, AppStyle.Spacing.compact)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingBreakdown)
                }
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.top, AppStyle.Spacing.comfortable)
            .padding(.bottom, AppStyle.Spacing.medium)

            VStack(spacing: AppStyle.Spacing.content) {
                ForEach(subtasks) { subtask in
                    compactSubtaskRow(subtask)
                }

                // Draft AI suggestions (not yet saved)
                ForEach(draftSuggestions) { draft in
                    HStack(spacing: AppStyle.Spacing.compact) {
                        Image(systemName: "sparkles")
                            .font(.inter(.caption2))
                            .foregroundColor(.purple.opacity(0.6))

                        TextField("Subtask", text: draftBinding(for: draft.id))
                            .font(.inter(.body))
                            .textFieldStyle(.plain)

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                draftSuggestions.removeAll { $0.id == draft.id }
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.inter(.caption))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove suggestion")
                    }
                }

                // New subtask entry (shown when focused)
                if showNewSubtaskField || !newSubtaskTitle.isEmpty {
                    HStack(spacing: AppStyle.Spacing.compact) {
                        Image(systemName: "circle")
                            .font(.inter(.caption2))
                            .foregroundColor(.secondary.opacity(0.5))

                        TextField("Subtask", text: $newSubtaskTitle)
                            .font(.inter(.body))
                            .textFieldStyle(.plain)
                            .focused($isNewSubtaskFocused)
                            .onAppear { isNewSubtaskFocused = true }
                            .onSubmit { addSubtask() }

                        Button {
                            newSubtaskTitle = ""
                            showNewSubtaskField = false
                            isNewSubtaskFocused = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.inter(.caption))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel")
                    }
                }

                // "+ Sub-task" pill button
                if !task.isCompleted {
                    HStack {
                        Button {
                            if !newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                                addSubtask()
                            }
                            showNewSubtaskField = true
                            isNewSubtaskFocused = true
                        } label: {
                            HStack(spacing: AppStyle.Spacing.tiny) {
                                Image(systemName: "plus")
                                    .font(.inter(.caption))
                                Text("Sub-task")
                                    .font(.inter(.caption))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, AppStyle.Spacing.medium)
                            .padding(.vertical, AppStyle.Spacing.small)
                            .glassEffect(.regular.tint(.black).interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, AppStyle.Spacing.content)
            .padding(.vertical, AppStyle.Spacing.medium)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Spacing.comfortable))
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - Compact Subtask Row

    @ViewBuilder
    private func compactSubtaskRow(_ subtask: FocusTask) -> some View {
        HStack(spacing: AppStyle.Spacing.compact) {
            Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.inter(.caption2))
                .foregroundColor(subtask.isCompleted ? Color.focusBlue.opacity(0.6) : .secondary.opacity(0.5))

            // Editable title
            SubtaskTextField(subtask: subtask, viewModel: viewModel, focusedId: $focusedSubtaskId)

            // Delete X button (staged — scheduled on save)
            if !subtask.isCompleted {
                Button {
                    pendingDeletions.insert(subtask.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.inter(.caption))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete subtask")
            }
        }
    }

    // MARK: - Action Pills Row

    private var currentCategoryName: String {
        if let id = selectedCategoryId,
           let cat = categories.first(where: { $0.id == id }) {
            return cat.name
        }
        return "Category"
    }

    @ViewBuilder
    private var actionPillsRow: some View {
        HStack(spacing: AppStyle.Spacing.compact) {
            // Priority pill (parent tasks only)
            if !isSubtask {
                Menu {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Button {
                            selectedPriority = priority
                        } label: {
                            if selectedPriority == priority {
                                Label(priority.displayName, systemImage: "checkmark")
                            } else {
                                Text(priority.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.small) {
                        Circle()
                            .fill(selectedPriority.dotColor)
                            .frame(width: AppStyle.Layout.dotSize, height: AppStyle.Layout.dotSize)
                        Text(LocalizedStringKey(selectedPriority.displayName))
                            .font(.inter(.subheadline, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, AppStyle.Spacing.comfortable)
                    .padding(.vertical, AppStyle.Spacing.medium)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }

            // Category pill (only in Log view, parent tasks)
            if !isSubtask && schedule == nil {
                Menu {
                    Button {
                        selectedCategoryId = nil
                    } label: {
                        if selectedCategoryId == nil {
                            Label("None", systemImage: "checkmark")
                        } else {
                            Text("None")
                        }
                    }
                    ForEach(categories) { category in
                        Button {
                            selectedCategoryId = category.id
                        } label: {
                            if selectedCategoryId == category.id {
                                Label(category.name, systemImage: "checkmark")
                            } else {
                                Text(category.name)
                            }
                        }
                    }
                    Divider()
                    Button {
                        showingNewCategoryAlert = true
                    } label: {
                        Label("New Category", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.small) {
                        Image(systemName: "folder")
                            .font(.inter(.subheadline))
                        Text(LocalizedStringKey(currentCategoryName))
                            .font(.inter(.subheadline, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, AppStyle.Spacing.comfortable)
                    .padding(.vertical, AppStyle.Spacing.medium)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }

            // Schedule pill (only when not scheduled)
            if schedule == nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scheduleExpanded.toggle()
                    }
                    if scheduleExpanded {
                        isTitleFocused = false
                        focusedSubtaskId = nil
                        isNewSubtaskFocused = false
                    }
                } label: {
                    HStack(spacing: AppStyle.Spacing.small) {
                        Image(systemName: "calendar")
                            .font(.inter(.subheadline))
                        Text(scheduleDateLabel)
                            .font(.inter(.subheadline, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(schedulePillIsActive ? .white : .primary)
                    .padding(.horizontal, AppStyle.Spacing.comfortable)
                    .padding(.vertical, AppStyle.Spacing.medium)
                    .glassEffect(
                        schedulePillIsActive
                            ? .regular.tint(.appRed).interactive()
                            : .regular.interactive(),
                        in: .capsule
                    )
                }
                .buttonStyle(.plain)
            }

            // Clear pending schedule pill
            if pendingSchedule != nil, let onClearSchedule {
                Button {
                    onClearSchedule()
                    dismiss()
                } label: {
                    HStack(spacing: AppStyle.Spacing.small) {
                        Image(systemName: "xmark.circle")
                            .font(.inter(.subheadline))
                        Text("Clear")
                            .font(.inter(.subheadline, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, AppStyle.Spacing.comfortable)
                    .padding(.vertical, AppStyle.Spacing.medium)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Delete circle
            Button {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.inter(.body, weight: .semiBold))
                    .foregroundColor(.red)
                    .frame(width: AppStyle.Layout.touchTarget, height: AppStyle.Layout.touchTarget)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete task")
        }
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - Contextual Actions Card

    private var contextualActionsVisible: Bool {
        schedule != nil
    }

    @ViewBuilder
    private var contextualActionsCard: some View {
        VStack(spacing: 0) {
            // Unschedule from Focus (when scheduled)
            if let schedule = schedule {
                DrawerActionRow(
                    icon: "minus.circle",
                    text: schedule.timeframe.unscheduleLabel
                ) {
                    _Concurrency.Task {
                        await focusViewModel.removeSchedule(schedule)
                        dismiss()
                    }
                }
            }

            // Schedule to lower timeframe (non-daily schedules)
            if let schedule = schedule,
               schedule.canBreakdown,
               let childTimeframe = schedule.childTimeframe {
                DrawerActionRow(icon: "arrow.down.forward.circle", text: "Schedule to \(childTimeframe.displayName)") {
                    focusViewModel.selectedScheduleForSchedule = schedule
                    focusViewModel.showScheduleSheet = true
                    dismiss()
                }
            }

            // Schedule Subtask to lower timeframe
            if isSubtask && schedule == nil {
                if let parentId = task.parentTaskId,
                   let parentSchedule = focusViewModel.schedules.first(where: {
                       $0.taskId == parentId &&
                       focusViewModel.isSameTimeframe($0.scheduleDate, timeframe: focusViewModel.selectedTimeframe, selectedDate: focusViewModel.selectedDate)
                   }),
                   parentSchedule.timeframe != .daily {
                    DrawerActionRow(icon: "arrow.down.forward.circle", text: "Schedule to \(parentSchedule.childTimeframe?.displayName ?? "...")") {
                        focusViewModel.selectedSubtaskForSchedule = task
                        focusViewModel.selectedParentScheduleForSubtaskSchedule = parentSchedule
                        focusViewModel.showSubtaskScheduleSheet = true
                        dismiss()
                    }
                }
            }

            // Reschedule (scheduled, non-completed parent task)
            if schedule != nil, !isSubtask, !task.isCompleted {
                DrawerActionRow(icon: "calendar", text: "Reschedule") {
                    showingRescheduleSheet = true
                }
            }

            // Unschedule (remove from timeline, keep schedule)
            if let schedule = schedule, schedule.scheduledTime != nil {
                DrawerActionRow(icon: "calendar.badge.minus", text: "Unschedule") {
                    _Concurrency.Task { @MainActor in
                        await focusViewModel.unscheduleSchedule(schedule.id)
                        dismiss()
                    }
                }
            }

            // Push to Next (scheduled, non-completed parent task)
            if let schedule = schedule, !isSubtask, !task.isCompleted {
                DrawerActionRow(icon: "arrow.right", text: "Push to \(schedule.timeframe.nextTimeframeLabel)") {
                    _Concurrency.Task {
                        let success = await focusViewModel.pushScheduleToNext(schedule)
                        if success { dismiss() }
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Spacing.comfortable))
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - Note Card

    @ViewBuilder
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Note")
                .font(.inter(.subheadline, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.top, AppStyle.Spacing.comfortable)
                .padding(.bottom, AppStyle.Spacing.small)

            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text("Add a note...")
                        .font(.inter(.body))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, AppStyle.Spacing.medium)
                        .padding(.vertical, AppStyle.Spacing.compact)
                }
                TextEditor(text: $noteText)
                    .font(.inter(.body))
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, AppStyle.Spacing.small)
                    .padding(.vertical, AppStyle.Spacing.micro)
            }
            .padding(.horizontal, AppStyle.Spacing.compact)
            .padding(.bottom, AppStyle.Spacing.medium)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Spacing.comfortable))
        .padding(.horizontal, AppStyle.Spacing.section)
    }

    // MARK: - Inline Schedule Card

    @ViewBuilder
    private var inlineScheduleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Calendar picker
            ScrollView {
                UnifiedCalendarPicker(
                    selectedDates: $scheduleDates,
                    selectedTimeframe: $scheduleTimeframe
                )
                .padding(.horizontal, AppStyle.Spacing.content)
                .padding(.vertical, AppStyle.Spacing.medium)
            }
            .frame(maxHeight: 350)

            NotificationToggleRow(
                isEnabled: $notificationEnabled,
                selectedTime: $notificationTime
            )
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.Spacing.comfortable))
        .padding(.horizontal, AppStyle.Spacing.section)
        .onAppear {
            if let pending = pendingSchedule {
                scheduleTimeframe = pending.timeframe
                scheduleSection = pending.section
                scheduleDates = pending.dates
                originalScheduleDates = pending.dates
            } else if onScheduleCallback == nil {
                fetchTaskSchedules()
            }
        }
        .onChange(of: scheduleTimeframe) {
            if onScheduleCallback == nil { fetchTaskSchedules() }
        }
        .onChange(of: scheduleSection) {
            if onScheduleCallback == nil { fetchTaskSchedules() }
        }
    }

    // MARK: - Schedule Data

    private func checkExistingSchedules() {
        _Concurrency.Task {
            do {
                let schedules = try await ScheduleRepository().fetchSchedules(forTask: task.id)
                await MainActor.run {
                    hasExistingSchedules = !schedules.isEmpty
                }
            } catch {
                // Silently fail
            }
        }
    }

    private func fetchTaskSchedules() {
        _Concurrency.Task {
            do {
                let scheduleRepository = ScheduleRepository()
                let schedules = try await scheduleRepository.fetchSchedules(forTask: task.id)

                let filtered = schedules.filter {
                    $0.timeframe == scheduleTimeframe && $0.section == scheduleSection
                }

                await MainActor.run {
                    originalSchedules = filtered
                    originalScheduleDates = Set(filtered.map { Calendar.current.startOfDay(for: $0.scheduleDate) })
                    scheduleDates = Set(filtered.map { $0.scheduleDate })
                }
            } catch {
                // Silently fail
            }
        }
    }

    private func saveScheduleChanges() {
        let currentDates = Set(scheduleDates.map { Calendar.current.startOfDay(for: $0) })

        if let onScheduleCallback {
            if !currentDates.isEmpty {
                onScheduleCallback(scheduleTimeframe, scheduleSection, currentDates)
            }
            return
        }

        guard originalScheduleDates != currentDates else { return }

        let capturedOriginalSchedules = originalSchedules
        let capturedSection = scheduleSection
        let capturedTimeframe = scheduleTimeframe

        _Concurrency.Task {
            do {
                let scheduleRepository = ScheduleRepository()
                let allSchedules = try await scheduleRepository.fetchSchedules(forTask: task.id)
                let otherSection: Section = capturedSection == .focus ? .todo : .focus

                let datesToAdd = currentDates.subtracting(originalScheduleDates)
                let datesToRemove = originalScheduleDates.subtracting(currentDates)

                for date in datesToRemove {
                    if let schedule = capturedOriginalSchedules.first(where: {
                        Calendar.current.startOfDay(for: $0.scheduleDate) == date
                    }) {
                        try await scheduleRepository.deleteSchedule(id: schedule.id)
                    }
                }

                for date in datesToAdd {
                    if let conflicting = allSchedules.first(where: {
                        $0.section == otherSection &&
                        $0.timeframe == capturedTimeframe &&
                        Calendar.current.startOfDay(for: $0.scheduleDate) == Calendar.current.startOfDay(for: date)
                    }) {
                        try await scheduleRepository.deleteSchedule(id: conflicting.id)
                    }

                    let newSchedule = Schedule(
                        userId: task.userId,
                        taskId: task.id,
                        timeframe: capturedTimeframe,
                        section: capturedSection,
                        scheduleDate: date,
                        sortOrder: 0
                    )
                    _ = try await scheduleRepository.createSchedule(newSchedule)
                }

                await focusViewModel.fetchSchedules()
            } catch {
                // Silently fail
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func rescheduleSheet(for schedule: Schedule) -> some View {
        RescheduleSheet(
            schedule: schedule,
            focusViewModel: focusViewModel
        )
        .drawerStyle()
    }

    private func saveTitle() {
        guard taskTitle != task.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(task, newTitle: taskTitle)
        }
    }

    private func saveNote() {
        guard hasNoteChanges else { return }
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        _Concurrency.Task {
            await viewModel.updateTaskNote(task, newNote: note.isEmpty ? nil : note)
        }
    }

    private func saveCategory() {
        guard selectedCategoryId != task.categoryId else { return }
        _Concurrency.Task {
            await viewModel.moveTaskToCategory(task, categoryId: selectedCategoryId)
        }
    }

    private func savePriority() {
        guard selectedPriority != task.priority else { return }
        _Concurrency.Task {
            await viewModel.updateTaskPriority(task, priority: selectedPriority)
        }
    }

    private func saveNotification() {
        guard notificationEnabled != task.notificationEnabled || notificationEnabled else { return }

        let notificationDate: Date? = if notificationEnabled, let firstDate = scheduleDates.sorted().first {
            combineDateTime(date: firstDate, time: notificationTime)
        } else if notificationEnabled, let scheduleDate = schedule?.scheduleDate {
            combineDateTime(date: scheduleDate, time: notificationTime)
        } else {
            nil
        }

        _Concurrency.Task {
            do {
                try await TaskRepository().updateTaskNotification(
                    id: task.id,
                    enabled: notificationEnabled,
                    date: notificationDate
                )
            } catch {
                // Silently fail
            }

            if notificationEnabled, let date = notificationDate {
                NotificationService.shared.scheduleNotification(
                    taskId: task.id,
                    title: task.title,
                    date: date
                )
            } else {
                NotificationService.shared.cancelNotification(taskId: task.id)
            }
        }
    }

    private func combineDateTime(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: date)
        let timeComponents = cal.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return cal.date(from: components) ?? date
    }

    private func savePendingDeletions() {
        let allSubtasks = viewModel.getSubtasks(for: task.id)
        for subtaskId in pendingDeletions {
            if let subtask = allSubtasks.first(where: { $0.id == subtaskId }) {
                _Concurrency.Task {
                    await viewModel.deleteSubtask(subtask, parentId: task.id)
                }
            }
        }
    }

    private func addSubtask() {
        guard !newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let title = newSubtaskTitle
        newSubtaskTitle = ""
        isNewSubtaskFocused = true
        _Concurrency.Task {
            if let schedule = schedule {
                await focusViewModel.createSubtask(title: title, parentId: task.id, parentSchedule: schedule)
            } else {
                await viewModel.createSubtask(title: title, parentId: task.id)
            }
        }
    }

    private func generateBreakdown() {
        isGeneratingBreakdown = true
        let existingTitles = subtasks.map { $0.title } + draftSuggestions.map { $0.title }

        _Concurrency.Task { @MainActor in
            do {
                let suggestions = try await AIService().generateSubtasks(
                    title: task.title,
                    description: task.description,
                    existingSubtasks: existingTitles.isEmpty ? nil : existingTitles
                )
                withAnimation(.easeInOut(duration: 0.2)) {
                    // Keep manually-added drafts, replace AI-generated ones
                    let manualDrafts = draftSuggestions.filter { !$0.isAISuggested }
                    draftSuggestions = manualDrafts + suggestions.map {
                        DraftSubtaskEntry(title: $0, isAISuggested: true)
                    }
                }
                hasGeneratedBreakdown = true
            } catch {
                // Silently fail — user can retry or add manually
            }
            isGeneratingBreakdown = false
        }
    }

    private func saveDraftSuggestions() {
        for draft in draftSuggestions {
            let title = draft.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            _Concurrency.Task {
                if let schedule = schedule {
                    await focusViewModel.createSubtask(title: title, parentId: task.id, parentSchedule: schedule)
                } else {
                    await viewModel.createSubtask(title: title, parentId: task.id)
                }
            }
        }
    }

    private func draftBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { draftSuggestions.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let idx = draftSuggestions.firstIndex(where: { $0.id == id }) {
                    draftSuggestions[idx].title = newValue
                }
            }
        )
    }

    private func createAndMoveToCategory() {
        let name = newCategoryName
        newCategoryName = ""
        _Concurrency.Task {
            await viewModel.createCategoryAndMove(name: name, task: task)
            dismiss()
        }
    }
}

// MARK: - Inline Subtask TextField

private struct SubtaskTextField<VM: TaskEditingViewModel>: View {
    let subtask: FocusTask
    @ObservedObject var viewModel: VM
    var focusedId: FocusState<UUID?>.Binding
    @State private var editingTitle: String

    init(subtask: FocusTask, viewModel: VM, focusedId: FocusState<UUID?>.Binding) {
        self.subtask = subtask
        self.viewModel = viewModel
        self.focusedId = focusedId
        _editingTitle = State(initialValue: subtask.title)
    }

    var body: some View {
        TextField("Subtask", text: $editingTitle)
            .font(.inter(.body))
            .textFieldStyle(.plain)
            .strikethrough(subtask.isCompleted)
            .foregroundColor(subtask.isCompleted ? .secondary : .primary)
            .focused(focusedId, equals: subtask.id)
            .onSubmit { saveTitle() }
            .onChange(of: focusedId.wrappedValue) { _, newValue in
                if newValue != subtask.id {
                    saveTitle()
                }
            }
    }

    private func saveTitle() {
        guard editingTitle != subtask.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(subtask, newTitle: editingTitle)
        }
    }
}
