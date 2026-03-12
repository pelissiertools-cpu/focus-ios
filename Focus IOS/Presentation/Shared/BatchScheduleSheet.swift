//
//  BatchScheduleSheet.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-09.
//

import SwiftUI

struct BatchScheduleSheet<VM: LogFilterable>: View {
    @ObservedObject var viewModel: VM
    @EnvironmentObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) var dismiss

    /// Optional override: supply tasks directly instead of using `viewModel.selectedItems`
    var tasks: [FocusTask]?
    /// Optional callback when scheduling completes (instead of `viewModel.exitEditMode()`)
    var onComplete: (() -> Void)?
    /// Optional callback to intercept scheduling instead of writing to DB
    var onBatchSchedule: (([FocusTask], Timeframe, Section, Set<Date>) -> Void)? = nil

    @State private var selectedTimeframe: Timeframe = .daily
    @State private var selectedSection: Section = .todo
    @State private var selectedDates: Set<Date> = []
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    // Notification
    @State private var notificationEnabled = false
    @State private var notificationExpanded = false
    @State private var notificationTime: Date = {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }()

    private var itemCount: Int { tasks?.count ?? viewModel.selectedCount }

    var body: some View {
        DrawerContainer(
            title: "Schedule Items",
            leadingButton: .cancel { dismiss() },
            trailingButton: .save(
                action: { _Concurrency.Task { await saveSchedules() } },
                disabled: selectedDates.isEmpty || isSaving
            )
        ) {
            ScrollViewReader { proxy in
                List {
                    SwiftUI.Section("Items") {
                        Text("\(itemCount) item\(itemCount == 1 ? "" : "s") selected")
                            .font(.inter(.headline))
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                    }

                    SwiftUI.Section("Select Dates") {
                        UnifiedCalendarPicker(
                            selectedDates: $selectedDates,
                            selectedTimeframe: $selectedTimeframe
                        )
                        .listRowBackground(Color(.secondarySystemGroupedBackground))

                        NotificationToggleRow(
                            isEnabled: $notificationEnabled,
                            selectedTime: $notificationTime,
                            isExpanded: $notificationExpanded
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .alert("Error", isPresented: $showError) {
                    Button("OK") {}
                } message: {
                    Text(errorMessage)
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
        }
    }

    private func saveSchedules() async {
        isSaving = true
        let items = tasks ?? viewModel.selectedItems

        if let onBatchSchedule {
            let normalizedDates = Set(selectedDates.map { Calendar.current.startOfDay(for: $0) })
            onBatchSchedule(items, selectedTimeframe, selectedSection, normalizedDates)
            if let onComplete {
                onComplete()
            } else {
                viewModel.exitEditMode()
            }
            dismiss()
            isSaving = false
            return
        }

        let scheduleRepository = ScheduleRepository()

        do {
            for item in items {
                for date in selectedDates {
                    let schedule = Schedule(
                        userId: item.userId,
                        taskId: item.id,
                        timeframe: selectedTimeframe,
                        section: selectedSection,
                        scheduleDate: Calendar.current.startOfDay(for: date),
                        sortOrder: 0
                    )
                    _ = try await scheduleRepository.createSchedule(schedule)
                }
            }

            // Save notifications for all items
            if notificationEnabled, let firstDate = selectedDates.sorted().first {
                let taskRepo = TaskRepository()
                for item in items {
                    let notifDate = combineDateTime(date: firstDate, time: notificationTime)
                    try await taskRepo.updateTaskNotification(
                        id: item.id,
                        enabled: true,
                        date: notifDate
                    )
                    NotificationService.shared.scheduleNotification(
                        taskId: item.id,
                        title: item.title,
                        date: notifDate
                    )
                }
            }

            await focusViewModel.fetchSchedules()
            await viewModel.fetchScheduledTaskIds()

            if let onComplete {
                onComplete()
            } else {
                viewModel.exitEditMode()
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSaving = false
    }

    private func combineDateTime(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: date)
        let timeComponents = cal.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return cal.date(from: components) ?? date
    }
}
