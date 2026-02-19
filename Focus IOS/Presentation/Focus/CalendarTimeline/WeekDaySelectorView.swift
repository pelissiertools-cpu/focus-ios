//
//  WeekDaySelectorView.swift
//  Focus IOS
//

import SwiftUI

/// Horizontal SUN–SAT day strip for selecting a day within the current week
struct WeekDaySelectorView: View {
    @Binding var selectedDate: Date

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        return cal
    }

    /// The 7 days of the week containing `selectedDate`
    private var weekDays: [Date] {
        guard let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        ) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private let dayAbbreviations = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekDays.enumerated()), id: \.offset) { index, date in
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(date)
                let dayNumber = calendar.component(.day, from: date)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedDate = date
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(dayAbbreviations[index])
                            .font(.montserratHeader(.caption2, weight: .medium))
                            .foregroundColor(.secondary)

                        Text("\(dayNumber)")
                            .font(.montserratHeader(.body, weight: isSelected ? .bold : .regular))
                            .foregroundColor(isSelected ? .white : (isToday ? Color(red: 1.0, green: 0.443, blue: 0.129) : .primary))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(isSelected ? Color(red: 1.0, green: 0.443, blue: 0.129) : Color.clear)
                            )
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}
