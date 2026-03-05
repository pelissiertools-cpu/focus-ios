//
//  DayAssignmentSheet.swift
//  Focus IOS
//

import SwiftUI

/// Sheet for assigning a weekly/monthly/yearly commitment to a specific day.
/// Reschedules the commitment from its current timeframe to daily at the selected date.
struct DayAssignmentSheet: View {
    let commitment: Commitment
    @ObservedObject var viewModel: FocusTabViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedDates: Set<Date> = []
    @State private var isSaving = false

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal
    }

    var body: some View {
        DrawerContainer(
            title: "Day Assignment",
            leadingButton: .cancel { dismiss() },
            trailingButton: .save(
                action: { _Concurrency.Task { await save() } },
                disabled: selectedDates.isEmpty || isSaving
            )
        ) {
            VStack(spacing: 0) {
                DailyCalendarView(
                    selectedDates: $selectedDates,
                    initialDate: commitment.commitmentDate
                )
                .padding(.top, 8)

                Spacer()
            }
            .onChange(of: selectedDates) {
                // Enforce single selection — keep only the newest date
                if selectedDates.count > 1,
                   let newest = selectedDates.sorted().last {
                    selectedDates = [newest]
                }
            }
        }
    }

    private func save() async {
        guard let date = selectedDates.first else { return }
        isSaving = true
        await viewModel.assignToDay(commitment, date: date)
        isSaving = false
        dismiss()
    }
}
