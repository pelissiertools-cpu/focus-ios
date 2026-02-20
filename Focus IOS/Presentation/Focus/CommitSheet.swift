//
//  BreakdownSheet.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-07.
//

import SwiftUI

/// Sheet for committing a task to a lower timeframe
struct CommitSheet: View {
    let commitment: Commitment
    let task: FocusTask
    @ObservedObject var viewModel: FocusTabViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedTargetTimeframe: Timeframe
    @State private var selectedDates: Set<Date> = []
    @State private var isSaving = false

    /// Available timeframes for breakdown (all lower than current)
    private var availableTimeframes: [Timeframe] {
        commitment.timeframe.availableBreakdownTimeframes
    }

    /// Existing child commitments for the selected timeframe
    private var existingChildrenForTimeframe: [Commitment] {
        viewModel.getChildCommitments(for: commitment.id)
            .filter { $0.timeframe == selectedTargetTimeframe }
    }

    init(commitment: Commitment, task: FocusTask, viewModel: FocusTabViewModel) {
        self.commitment = commitment
        self.task = task
        self.viewModel = viewModel
        // Default to first available timeframe
        _selectedTargetTimeframe = State(initialValue: commitment.timeframe.availableBreakdownTimeframes.first ?? .daily)
    }

    var body: some View {
        DrawerContainer(
            title: "Commit",
            leadingButton: .cancel { dismiss() },
            trailingButton: .add(
                action: { _Concurrency.Task { await addSelectedCommitments() } },
                disabled: selectedDates.isEmpty || isSaving
            )
        ) {
            VStack(spacing: 0) {
                // Header info
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title)
                        .font(.sf(.headline))

                    HStack {
                        Image(systemName: "arrow.down.forward.circle")
                            .foregroundColor(.blue)
                        Text("Commit to lower timeframe")
                            .font(.sf(.subheadline))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

                Divider()

                // Existing breakdown summary
                if !existingChildrenForTimeframe.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("\(existingChildrenForTimeframe.count) already committed to \(selectedTargetTimeframe.displayName.lowercased())")
                            .font(.sf(.caption))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                // Calendar picker with timeframe selector
                BreakdownCalendarPicker(
                    selectedDates: $selectedDates,
                    selectedTimeframe: $selectedTargetTimeframe,
                    availableTimeframes: availableTimeframes,
                    commitment: commitment,
                    viewModel: viewModel
                )
                .padding(.top, 8)

                Spacer()
            }
            .onChange(of: selectedTargetTimeframe) {
                // Clear selections when timeframe changes
                selectedDates.removeAll()
            }
        }
    }

    private func addSelectedCommitments() async {
        isSaving = true

        for date in selectedDates.sorted() {
            await viewModel.commitToTimeframe(commitment, toDate: date, targetTimeframe: selectedTargetTimeframe)
        }

        isSaving = false
        dismiss()
    }
}

/// Calendar picker variant for breakdown that only shows lower timeframes
struct BreakdownCalendarPicker: View {
    @Binding var selectedDates: Set<Date>
    @Binding var selectedTimeframe: Timeframe
    let availableTimeframes: [Timeframe]
    let commitment: Commitment
    @ObservedObject var viewModel: FocusTabViewModel

    /// Dates already broken down for the selected timeframe
    private var excludedDates: Set<Date> {
        let calendar = Calendar.current
        let existingChildren = viewModel.getChildCommitments(for: commitment.id)
            .filter { $0.timeframe == selectedTimeframe }
        return Set(existingChildren.map { calendar.startOfDay(for: $0.commitmentDate) })
    }

    var body: some View {
        VStack(spacing: 16) {
            // Timeframe picker (only show if multiple options)
            if availableTimeframes.count > 1 {
                Picker("Timeframe", selection: $selectedTimeframe) {
                    ForEach(availableTimeframes, id: \.self) { tf in
                        Text(tf.displayName).tag(tf)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }

            // Calendar view based on selected timeframe
            switch selectedTimeframe {
            case .daily:
                DailyCalendarView(
                    selectedDates: $selectedDates,
                    excludedDates: excludedDates,
                    initialDate: commitment.commitmentDate
                )
            case .weekly:
                WeeklyCalendarView(
                    selectedDates: $selectedDates,
                    excludedDates: excludedDates,
                    initialDate: commitment.commitmentDate,
                    showMonthPicker: false
                )
            case .monthly:
                MonthlyCalendarView(
                    selectedDates: $selectedDates,
                    excludedDates: excludedDates,
                    fixedYear: Calendar.current.component(.year, from: commitment.commitmentDate)
                )
            case .yearly:
                // Should not happen - yearly is never a breakdown target
                EmptyView()
            }
        }
    }
}

// MARK: - Subtask Commit Sheet

/// Sheet for committing a subtask to a lower timeframe
/// Creates a commitment for the subtask at the target timeframe
struct SubtaskCommitSheet: View {
    let subtask: FocusTask
    let parentCommitment: Commitment
    @ObservedObject var viewModel: FocusTabViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedTargetTimeframe: Timeframe
    @State private var selectedDates: Set<Date> = []
    @State private var isSaving = false

    /// Available timeframes for breakdown (all lower than parent's current)
    private var availableTimeframes: [Timeframe] {
        parentCommitment.timeframe.availableBreakdownTimeframes
    }

    init(subtask: FocusTask, parentCommitment: Commitment, viewModel: FocusTabViewModel) {
        self.subtask = subtask
        self.parentCommitment = parentCommitment
        self.viewModel = viewModel
        // Default to first available timeframe
        _selectedTargetTimeframe = State(initialValue: parentCommitment.timeframe.availableBreakdownTimeframes.first ?? .daily)
    }

    var body: some View {
        DrawerContainer(
            title: "Commit Subtask",
            leadingButton: .cancel { dismiss() },
            trailingButton: .add(
                action: { _Concurrency.Task { await addSelectedCommitments() } },
                disabled: selectedDates.isEmpty || isSaving
            )
        ) {
            VStack(spacing: 0) {
                // Header info
                VStack(alignment: .leading, spacing: 8) {
                    Text(subtask.title)
                        .font(.sf(.headline))

                    HStack {
                        Image(systemName: "arrow.down.forward.circle")
                            .foregroundColor(.blue)
                        Text("Commit subtask to lower timeframe")
                            .font(.sf(.subheadline))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

                Divider()

                // Calendar picker with timeframe selector
                SubtaskCommitCalendarPicker(
                    selectedDates: $selectedDates,
                    selectedTimeframe: $selectedTargetTimeframe,
                    availableTimeframes: availableTimeframes,
                    parentCommitment: parentCommitment
                )
                .padding(.top, 8)

                Spacer()
            }
            .onChange(of: selectedTargetTimeframe) {
                // Clear selections when timeframe changes
                selectedDates.removeAll()
            }
        }
    }

    private func addSelectedCommitments() async {
        isSaving = true

        for date in selectedDates.sorted() {
            await viewModel.commitSubtask(subtask, parentCommitment: parentCommitment, toDate: date, targetTimeframe: selectedTargetTimeframe)
        }

        isSaving = false
        dismiss()
    }
}

/// Calendar picker for subtask commit - uses parent commitment's date range
struct SubtaskCommitCalendarPicker: View {
    @Binding var selectedDates: Set<Date>
    @Binding var selectedTimeframe: Timeframe
    let availableTimeframes: [Timeframe]
    let parentCommitment: Commitment

    var body: some View {
        VStack(spacing: 16) {
            // Timeframe picker (only show if multiple options)
            if availableTimeframes.count > 1 {
                Picker("Timeframe", selection: $selectedTimeframe) {
                    ForEach(availableTimeframes, id: \.self) { tf in
                        Text(tf.displayName).tag(tf)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }

            // Calendar view based on selected timeframe
            // Uses parent commitment as the scoping reference
            switch selectedTimeframe {
            case .daily:
                DailyCalendarView(
                    selectedDates: $selectedDates,
                    initialDate: parentCommitment.commitmentDate
                )
            case .weekly:
                WeeklyCalendarView(
                    selectedDates: $selectedDates,
                    initialDate: parentCommitment.commitmentDate,
                    showMonthPicker: false
                )
            case .monthly:
                MonthlyCalendarView(
                    selectedDates: $selectedDates,
                    fixedYear: Calendar.current.component(.year, from: parentCommitment.commitmentDate)
                )
            case .yearly:
                // Should not happen - yearly is never a breakdown target
                EmptyView()
            }
        }
    }
}

#Preview {
    CommitSheet(
        commitment: Commitment(
            userId: UUID(),
            taskId: UUID(),
            timeframe: .yearly,
            section: .focus,
            commitmentDate: Date()
        ),
        task: FocusTask(
            id: UUID(),
            userId: UUID(),
            title: "Learn Spanish",
            type: .task,
            isCompleted: false,
            createdDate: Date(),
            modifiedDate: Date(),
            sortOrder: 0,
            isInLog: true
        ),
        viewModel: FocusTabViewModel(authService: AuthService())
    )
}
