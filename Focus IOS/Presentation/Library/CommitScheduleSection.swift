//
//  CommitScheduleSection.swift
//  Focus IOS
//

import SwiftUI

struct CommitScheduleSection: View {
    @Binding var commitAfterCreate: Bool
    @Binding var selectedTimeframe: Timeframe
    @Binding var selectedSection: Section
    @Binding var selectedDates: Set<Date>
    @Binding var hasScheduledTime: Bool
    @Binding var scheduledTime: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $commitAfterCreate.animation(.easeInOut(duration: 0.2))) {
                Label("Commit", systemImage: "arrow.right.circle")
                    .font(.subheadline.weight(.medium))
            }
            .tint(.blue)

            if commitAfterCreate {
                Picker("Section", selection: $selectedSection) {
                    Text("Focus").tag(Section.focus)
                    Text("Extra").tag(Section.extra)
                }
                .pickerStyle(.segmented)

                UnifiedCalendarPicker(
                    selectedDates: $selectedDates,
                    selectedTimeframe: $selectedTimeframe
                )

                Toggle(isOn: $hasScheduledTime.animation(.easeInOut(duration: 0.2))) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundColor(.blue)
                        Text("Select a time")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .tint(.blue)

                if hasScheduledTime {
                    DatePicker(
                        "Time",
                        selection: $scheduledTime,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }
            }
        }
        .onChange(of: commitAfterCreate) { _, isOn in
            if !isOn {
                hasScheduledTime = false
            }
        }
    }
}
