//
//  TimeframePickers.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-06.
//

import SwiftUI

// Week Picker
struct WeekPicker: View {
    @Binding var selectedDate: Date

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        return cal
    }

    var body: some View {
        HStack {
            Button {
                selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Spacer()

            Text(weekText)
                .font(.headline)

            Spacer()

            Button {
                selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var weekText: String {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday

        let weekOfYear = calendar.component(.weekOfYear, from: selectedDate)

        // Get start and end of week
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)),
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return "Week \(weekOfYear)"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Week \(weekOfYear): \(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd))"
    }
}

// Month Picker
struct MonthPicker: View {
    @Binding var selectedDate: Date

    var body: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Spacer()

            Text(monthText)
                .font(.headline)

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var monthText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }
}

// Year Picker
struct YearPicker: View {
    @Binding var selectedDate: Date

    var body: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .year, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Spacer()

            Text(yearText)
                .font(.headline)

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .year, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var yearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: selectedDate)
    }
}
