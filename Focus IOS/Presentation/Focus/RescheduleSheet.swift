//
//  RescheduleSheet.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-08.
//

import SwiftUI

struct RescheduleSheet: View {
    let commitment: Commitment
    @ObservedObject var focusViewModel: FocusTabViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedTimeframe: Timeframe
    @State private var selectedDate: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(commitment: Commitment, focusViewModel: FocusTabViewModel) {
        self.commitment = commitment
        self.focusViewModel = focusViewModel
        _selectedTimeframe = State(initialValue: commitment.timeframe)
        _selectedDate = State(initialValue: commitment.commitmentDate)
    }

    private var hasChanges: Bool {
        selectedTimeframe != commitment.timeframe ||
        !Calendar.current.isDate(selectedDate, inSameDayAs: commitment.commitmentDate)
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
            ScrollView {
                VStack(spacing: 12) {
                    // Current schedule card
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Current Schedule")
                            .font(.sf(.footnote, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                        Divider()

                        HStack {
                            Text("Timeframe")
                            Spacer()
                            Text(commitment.timeframe.displayName)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        Divider()

                        HStack {
                            Text("Date")
                            Spacer()
                            Text(formatDate(commitment.commitmentDate, for: commitment.timeframe))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // New schedule card
                    VStack(alignment: .leading, spacing: 0) {
                        Text("New Schedule")
                            .font(.sf(.footnote, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                        Divider()

                        Picker("Timeframe", selection: $selectedTimeframe) {
                            Text("Day").tag(Timeframe.daily)
                            Text("Week").tag(Timeframe.weekly)
                            Text("Month").tag(Timeframe.monthly)
                            Text("Year").tag(Timeframe.yearly)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 8)

                        Divider()

                        RescheduleDatePicker(
                            selectedDate: $selectedDate,
                            timeframe: selectedTimeframe
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        let success = await focusViewModel.rescheduleCommitment(
            commitment,
            to: selectedDate,
            newTimeframe: selectedTimeframe
        )

        if success {
            dismiss()
        } else {
            // Error message is set by rescheduleCommitment
            errorMessage = focusViewModel.errorMessage
            isSaving = false
        }
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
