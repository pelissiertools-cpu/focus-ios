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
    var onSomeday: (() -> Void)? = nil
    var isSomedayTask: Bool = false
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

    private var isParentTask: Bool {
        task.parentTaskId == nil && subtaskCount > 0
    }

    private var isPendingMode: Bool {
        pendingSchedule != nil
    }

    private var hasChanges: Bool {
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
            ScrollView {
                VStack(spacing: 12) {
                    // Task title card
                    VStack(alignment: .leading, spacing: 4) {
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Section picker + calendar card
                    VStack(spacing: 0) {
                        Picker("Section", selection: $selectedSection) {
                            Text("Focus").tag(Section.focus)
                            Text("To-Do").tag(Section.todo)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        Divider()

                        UnifiedCalendarPicker(
                            selectedDates: $selectedDates,
                            selectedTimeframe: $selectedTimeframe
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Someday pill
                    if let onSomeday, !isSomedayTask {
                        HStack {
                            Button {
                                onSomeday()
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    HourglassIcon()
                                        .fill(.primary, style: FillStyle(eoFill: true))
                                        .frame(width: 15, height: 15)
                                    Text("Someday")
                                        .font(.inter(.subheadline, weight: .medium))
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                    }

                    // Clear scheduling pill (only in pending mode)
                    if isPendingMode {
                        HStack {
                            Button {
                                onClearSchedule?()
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle")
                                        .font(.inter(.subheadline))
                                    Text("Clear Scheduling")
                                        .font(.inter(.subheadline, weight: .medium))
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
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

            // Refresh focus view
            await focusViewModel.fetchSchedules()

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSaving = false
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
