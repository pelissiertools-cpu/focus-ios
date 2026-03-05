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
    @State private var draftSuggestions: [DraftSubtaskEntry] = []
    @State private var isGeneratingBreakdown = false
    @State private var hasGeneratedBreakdown = false

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
            title: "Schedule Breakdown",
            leadingButton: .cancel { dismiss() },
            trailingButton: .add(
                action: { _Concurrency.Task { await addSelectedCommitments() } },
                disabled: (selectedDates.isEmpty && draftSuggestions.isEmpty) || isSaving
            )
        ) {
            VStack(spacing: 0) {
                // Header info
                HStack {
                    Text(task.title)
                        .font(.inter(.headline))
                    Spacer()
                    Button {
                        generateBreakdown()
                    } label: {
                        HStack(spacing: 6) {
                            if isGeneratingBreakdown {
                                ProgressView()
                                    .tint(.primary)
                            } else {
                                Image(systemName: hasGeneratedBreakdown ? "arrow.clockwise" : "sparkles")
                                    .font(.inter(.subheadline, weight: .semiBold))
                            }
                            Text(LocalizedStringKey(hasGeneratedBreakdown ? "Regenerate" : "Suggest Breakdown"))
                                .font(.inter(.caption, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingBreakdown)
                }
                .padding()

                Divider()

                // Draft AI suggestions (not yet saved)
                if !draftSuggestions.isEmpty {
                    VStack(spacing: 14) {
                        ForEach(draftSuggestions) { draft in
                            HStack(spacing: 8) {
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
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                    Divider()
                }

                // Existing breakdown summary
                if !existingChildrenForTimeframe.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("\(existingChildrenForTimeframe.count) already scheduled to \(selectedTargetTimeframe.displayName.lowercased())")
                            .font(.inter(.caption))
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

        let draftsToSave = draftSuggestions.map { $0.title.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for title in draftsToSave {
            await viewModel.createSubtask(title: title, parentId: task.id)
        }

        isSaving = false
        dismiss()
    }

    private func generateBreakdown() {
        isGeneratingBreakdown = true
        let existingTitles = draftSuggestions.map { $0.title }

        _Concurrency.Task { @MainActor in
            do {
                let suggestions = try await AIService().generateSubtasks(
                    title: task.title,
                    description: task.description,
                    existingSubtasks: existingTitles.isEmpty ? nil : existingTitles
                )
                withAnimation(.easeInOut(duration: 0.2)) {
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

    private func draftBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { draftSuggestions.first(where: { $0.id == id })?.title ?? "" },
            set: { newValue in
                if let index = draftSuggestions.firstIndex(where: { $0.id == id }) {
                    draftSuggestions[index].title = newValue
                }
            }
        )
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
            title: "Schedule Subtask",
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
                        .font(.inter(.headline))

                    HStack {
                        Image(systemName: "arrow.down.forward.circle")
                            .foregroundColor(.appRed)
                        Text("Schedule subtask to lower timeframe")
                            .font(.inter(.subheadline))
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
