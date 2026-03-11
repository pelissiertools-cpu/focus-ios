//
//  RescheduleSheet.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-08.
//

import SwiftUI

struct RescheduleSheet: View {
    let schedule: Schedule
    @ObservedObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedTimeframe: Timeframe
    @State private var selectedDate: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Notification
    @State private var notificationEnabled = false
    @State private var notificationExpanded = false
    @State private var notificationTime: Date = {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }()
    @State private var taskForNotification: FocusTask?

    init(schedule: Schedule, focusViewModel: FocusTabViewModel) {
        self.schedule = schedule
        self.focusViewModel = focusViewModel
        _selectedTimeframe = State(initialValue: schedule.timeframe)
        _selectedDate = State(initialValue: schedule.scheduleDate)
    }

    private var hasNotificationChanges: Bool {
        guard let task = taskForNotification else { return notificationEnabled }
        return notificationEnabled != task.notificationEnabled ||
        (notificationEnabled && !Calendar.current.isDate(notificationTime, equalTo: task.notificationDate ?? Date.distantPast, toGranularity: .minute))
    }

    private var hasChanges: Bool {
        hasNotificationChanges ||
        selectedTimeframe != schedule.timeframe ||
        !Calendar.current.isDate(selectedDate, inSameDayAs: schedule.scheduleDate)
    }

    var body: some View {
        DrawerContainer(
            title: "Reschedule Task",
            leadingButton: .cancel { dismiss() },
            trailingButton: .save(
                action: { _Concurrency.Task { await save() } },
                disabled: !hasChanges || isSaving
            )
        ) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: AppStyle.Spacing.comfortable) {
                        // Current schedule card
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Current Schedule")
                                .font(.inter(.footnote, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, AppStyle.Spacing.content)
                                .padding(.top, AppStyle.Spacing.comfortable)
                                .padding(.bottom, AppStyle.Spacing.compact)

                            Divider()

                            HStack {
                                Text("Timeframe")
                                Spacer()
                                Text(schedule.timeframe.displayName)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, AppStyle.Spacing.content)
                            .padding(.vertical, AppStyle.Spacing.comfortable)

                            Divider()

                            HStack {
                                Text("Date")
                                Spacer()
                                Text(formatDate(schedule.scheduleDate, for: schedule.timeframe))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, AppStyle.Spacing.content)
                            .padding(.vertical, AppStyle.Spacing.comfortable)
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // New schedule card
                        VStack(alignment: .leading, spacing: 0) {
                            Text("New Schedule")
                                .font(.inter(.footnote, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, AppStyle.Spacing.content)
                                .padding(.top, AppStyle.Spacing.comfortable)
                                .padding(.bottom, AppStyle.Spacing.compact)

                            Divider()

                            Picker("Timeframe", selection: $selectedTimeframe) {
                                Text("Day").tag(Timeframe.daily)
                                Text("Week").tag(Timeframe.weekly)
                                Text("Month").tag(Timeframe.monthly)
                                Text("Year").tag(Timeframe.yearly)
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, AppStyle.Spacing.content)
                            .padding(.top, AppStyle.Spacing.compact)
                            .padding(.bottom, AppStyle.Spacing.compact)

                            Divider()

                            RescheduleDatePicker(
                                selectedDate: $selectedDate,
                                timeframe: selectedTimeframe
                            )
                            .padding(.horizontal, AppStyle.Spacing.content)
                            .padding(.vertical, AppStyle.Spacing.compact)

                            NotificationToggleRow(
                                isEnabled: $notificationEnabled,
                                selectedTime: $notificationTime,
                                isExpanded: $notificationExpanded
                            )
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        if let error = errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.red)
                                .padding(.horizontal, AppStyle.Spacing.content)
                                .padding(.vertical, AppStyle.Spacing.comfortable)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .onAppear {
                fetchTaskNotificationState()
            }
        }
    }

    private func fetchTaskNotificationState() {
        _Concurrency.Task {
            do {
                let tasks = try await TaskRepository().fetchTasksByIds([schedule.taskId])
                if let task = tasks.first {
                    await MainActor.run {
                        taskForNotification = task
                        notificationEnabled = task.notificationEnabled
                        if let date = task.notificationDate {
                            notificationTime = date
                        }
                    }
                }
            } catch {
                // Silently fail
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        let success = await focusViewModel.rescheduleSchedule(
            schedule,
            to: selectedDate,
            newTimeframe: selectedTimeframe
        )

        if success {
            await saveNotification()
            dismiss()
        } else {
            // Error message is set by rescheduleSchedule
            errorMessage = focusViewModel.errorMessage
            isSaving = false
        }
    }

    private func saveNotification() async {
        let notificationDate: Date? = if notificationEnabled {
            combineDateTime(date: selectedDate, time: notificationTime)
        } else {
            nil
        }

        do {
            try await TaskRepository().updateTaskNotification(
                id: schedule.taskId,
                enabled: notificationEnabled,
                date: notificationDate
            )
        } catch {
            // Silently fail
        }

        if notificationEnabled, let date = notificationDate {
            let title = taskForNotification?.title ?? ""
            NotificationService.shared.scheduleNotification(
                taskId: schedule.taskId,
                title: title,
                date: date
            )
        } else {
            NotificationService.shared.cancelNotification(taskId: schedule.taskId)
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

    private func formatDate(_ date: Date, for timeframe: Timeframe) -> String {
        let formatter = DateFormatter()
        switch timeframe {
        case .daily:
            formatter.dateFormat = "EEEE, MMM d, yyyy"
        case .weekly:
            formatter.dateFormat = "'Week' w, yyyy"
        case .monthly:
            formatter.dateFormat = "MMMM yyyy"
        case .yearly:
            formatter.dateFormat = "yyyy"
        }
        return formatter.string(from: date)
    }
}

// MARK: - Reschedule Date Picker

/// Single-select date picker that adapts to timeframe
struct RescheduleDatePicker: View {
    @Binding var selectedDate: Date
    let timeframe: Timeframe

    // Use Set internally for compatibility with calendar views
    @State private var selectedDates: Set<Date> = []

    var body: some View {
        VStack(spacing: 0) {
            switch timeframe {
            case .daily:
                DailyCalendarView(selectedDates: $selectedDates)
            case .weekly:
                WeeklyCalendarView(selectedDates: $selectedDates)
            case .monthly:
                MonthlyCalendarView(selectedDates: $selectedDates)
            case .yearly:
                YearlyCalendarView(selectedDates: $selectedDates)
            }
        }
        .onAppear {
            selectedDates = [selectedDate]
        }
        .onChange(of: selectedDates) { oldValue, newValue in
            // Enforce single selection - keep only the newest selection
            if newValue.count > 1 {
                // Find the new date (not in old set)
                if let newest = newValue.first(where: { !oldValue.contains($0) }) {
                    selectedDates = [newest]
                    selectedDate = newest
                }
            } else if let first = newValue.first {
                selectedDate = first
            }
        }
        .onChange(of: timeframe) { _, _ in
            // Reset selection when timeframe changes
            selectedDates = [selectedDate]
        }
    }
}
