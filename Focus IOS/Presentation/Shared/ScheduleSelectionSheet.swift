//
//  ScheduleSelectionSheet.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-06.
//

import SwiftUI

struct ScheduleSelectionSheet: View {
    let task: FocusTask
    @ObservedObject var focusViewModel: FocusTabViewModel
    var onSchedule: ((Timeframe, Section, Set<Date>) -> Void)? = nil
    var pendingSchedule: PendingScheduleInfo? = nil
    var onClearSchedule: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss

    @State private var selectedTimeframe: Timeframe = .daily
    @State private var selectedSection: Section = .todo
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var subtaskCount = 0
    @State private var isSaving = false

    // Track selected dates (toggled by tapping)
    @State private var selectedDates: Set<Date> = []
    // Track original schedules to know what to add/remove
    @State private var originalSchedules: [Schedule] = []
    // Track original pending dates to detect changes
    @State private var originalPendingDates: Set<Date> = []

    // Notification
    @State private var notificationEnabled: Bool = false
    @State private var notificationTime: Date = {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }()

    private var isParentTask: Bool {
        task.parentTaskId == nil && subtaskCount > 0
    }

    private var isPendingMode: Bool {
        pendingSchedule != nil
    }

    private var hasNotificationChanges: Bool {
        notificationEnabled != task.notificationEnabled ||
        (notificationEnabled && !Calendar.current.isDate(notificationTime, equalTo: task.notificationDate ?? Date.distantPast, toGranularity: .minute))
    }

    private var hasChanges: Bool {
        if hasNotificationChanges { return true }
        if isPendingMode {
            let currentDates = Set(selectedDates.map { normalizeDate($0) })
            return originalPendingDates != currentDates
        }
        let originalDates = Set(originalSchedules.map { normalizeDate($0.scheduleDate) })
        let currentDates = Set(selectedDates.map { normalizeDate($0) })
        return originalDates != currentDates
    }

    var body: some View {
        DrawerContainer(
            title: task.type == .list ? "Schedule List" : "Schedule Task",
            leadingButton: .cancel { dismiss() },
            trailingButton: .save(
                action: { _Concurrency.Task { await saveChanges() } },
                disabled: !hasChanges || isSaving
            )
        ) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: AppStyle.Spacing.comfortable) {
                        // Task title card
                        VStack(alignment: .leading, spacing: AppStyle.Spacing.tiny) {
                            Text(task.title)
                                .font(.inter(.headline))
                            if isParentTask {
                                let itemLabel = task.type == .list ? "item" : "subtask"
                                Text("Includes \(subtaskCount) \(itemLabel)\(subtaskCount == 1 ? "" : "s")")
                                    .font(.inter(.caption))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppStyle.Spacing.content)
                        .padding(.vertical, AppStyle.Spacing.comfortable)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Section picker + calendar card
                        VStack(spacing: 0) {
                            Picker("Section", selection: $selectedSection) {
                                Text("Focus").tag(Section.focus)
                                Text("To-Do").tag(Section.todo)
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, AppStyle.Spacing.content)
                            .padding(.top, AppStyle.Spacing.comfortable)
                            .padding(.bottom, AppStyle.Spacing.compact)

                            Divider()

                            UnifiedCalendarPicker(
                                selectedDates: $selectedDates,
                                selectedTimeframe: $selectedTimeframe
                            )
                            .padding(.horizontal, AppStyle.Spacing.content)
                            .padding(.vertical, AppStyle.Spacing.compact)

                            NotificationToggleRow(
                                isEnabled: $notificationEnabled,
                                selectedTime: $notificationTime
                            )
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Clear scheduling pill (only in pending mode)
                        if isPendingMode {
                            HStack {
                                Button {
                                    onClearSchedule?()
                                    dismiss()
                                } label: {
                                    HStack(spacing: AppStyle.Spacing.small) {
                                        Image(systemName: "xmark.circle")
                                            .font(.inter(.subheadline))
                                        Text("Clear Scheduling")
                                            .font(.inter(.subheadline, weight: .medium))
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, AppStyle.Spacing.content)
                                    .padding(.vertical, AppStyle.Spacing.medium)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, AppStyle.Spacing.section)
                    .padding(.vertical, AppStyle.Spacing.comfortable)
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
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                notificationEnabled = task.notificationEnabled
                if let date = task.notificationDate {
                    notificationTime = date
                }
                fetchSubtaskCount()
                if let pending = pendingSchedule {
                    selectedTimeframe = pending.timeframe
                    selectedSection = pending.section
                    selectedDates = pending.dates
                    originalPendingDates = Set(pending.dates.map { normalizeDate($0) })
                } else {
                    fetchTaskSchedules()
                }
            }
            .onChange(of: selectedTimeframe) {
                if !isPendingMode { fetchTaskSchedules() }
            }
            .onChange(of: selectedSection) {
                if !isPendingMode { fetchTaskSchedules() }
            }
            .onChange(of: selectedDates) { oldValue, newValue in
                // Enforce single-date selection — selecting a new date replaces the previous one
                if newValue.count > 1 {
                    if let newest = newValue.first(where: { !oldValue.contains($0) }) {
                        selectedDates = [newest]
                    }
                }
            }
        }
    }

    private func normalizeDate(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func saveChanges() async {
        isSaving = true

        if let onSchedule {
            let normalizedDates = Set(selectedDates.map { normalizeDate($0) })
            if normalizedDates.isEmpty {
                onClearSchedule?()
            } else {
                onSchedule(selectedTimeframe, selectedSection, normalizedDates)
            }
            dismiss()
            isSaving = false
            return
        }

        do {
            let scheduleRepository = ScheduleRepository()

            // Fetch ALL schedules for this task (both sections) to check for conflicts
            let allSchedules = try await scheduleRepository.fetchSchedules(forTask: task.id)
            let otherSection: Section = selectedSection == .focus ? .todo : .focus

            let originalDates = Set(originalSchedules.map { normalizeDate($0.scheduleDate) })
            let currentDates = Set(selectedDates.map { normalizeDate($0) })

            // Find dates to add (in current but not in original)
            let datesToAdd = currentDates.subtracting(originalDates)

            // Find dates to remove (in original but not in current)
            let datesToRemove = originalDates.subtracting(currentDates)

            // Delete removed schedules from current section
            for date in datesToRemove {
                if let schedule = originalSchedules.first(where: { normalizeDate($0.scheduleDate) == date }) {
                    try await scheduleRepository.deleteSchedule(id: schedule.id)
                }
            }

            // For new dates, check if there's a conflict in the other section and remove it
            for date in datesToAdd {
                // Find and delete any conflicting schedule in the other section
                if let conflicting = allSchedules.first(where: {
                    $0.section == otherSection &&
                    $0.timeframe == selectedTimeframe &&
                    normalizeDate($0.scheduleDate) == normalizeDate(date)
                }) {
                    try await scheduleRepository.deleteSchedule(id: conflicting.id)
                }

                // Create the new schedule in selected section
                let schedule = Schedule(
                    userId: task.userId,
                    taskId: task.id,
                    timeframe: selectedTimeframe,
                    section: selectedSection,
                    scheduleDate: date,
                    sortOrder: 0
                )
                _ = try await scheduleRepository.createSchedule(schedule)
            }

            // Save notification
            await saveNotification()

            // Refresh focus view
            await focusViewModel.fetchSchedules()

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSaving = false
    }

    private func saveNotification() async {
        let notificationDate: Date? = if notificationEnabled, let firstDate = selectedDates.sorted().first {
            combineDateTime(date: firstDate, time: notificationTime)
        } else {
            nil
        }

        do {
            try await TaskRepository().updateTaskNotification(
                id: task.id,
                enabled: notificationEnabled,
                date: notificationDate
            )
        } catch {
            // Silently fail — scheduling itself succeeded
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

    private func combineDateTime(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: date)
        let timeComponents = cal.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return cal.date(from: components) ?? date
    }

    private func fetchSubtaskCount() {
        Task {
            do {
                let subtasks = try await TaskRepository().fetchSubtasks(parentId: task.id)
                await MainActor.run {
                    subtaskCount = subtasks.count
                }
            } catch {
                // Silently fail
            }
        }
    }

    private func fetchTaskSchedules() {
        Task {
            do {
                let scheduleRepository = ScheduleRepository()
                let schedules = try await scheduleRepository.fetchSchedules(forTask: task.id)

                // Filter by current timeframe AND section
                let filtered = schedules.filter {
                    $0.timeframe == selectedTimeframe && $0.section == selectedSection
                }

                await MainActor.run {
                    originalSchedules = filtered
                    selectedDates = Set(filtered.map { $0.scheduleDate })
                }
            } catch {
                // Silently fail
            }
        }
    }
}
