//
//  UnifiedCalendarPicker.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-06.
//

import SwiftUI

/// Unified calendar picker that adapts based on selected timeframe
struct UnifiedCalendarPicker: View {
    @Binding var selectedDate: Date
    @Binding var selectedTimeframe: Timeframe

    var body: some View {
        VStack(spacing: 16) {
            // Timeframe Toggle
            Picker("Timeframe", selection: $selectedTimeframe) {
                Text("Day").tag(Timeframe.daily)
                Text("Week").tag(Timeframe.weekly)
                Text("Month").tag(Timeframe.monthly)
                Text("Year").tag(Timeframe.yearly)
            }
            .pickerStyle(.segmented)

            // Adaptive Calendar View
            switch selectedTimeframe {
            case .daily:
                DailyCalendarView(selectedDate: $selectedDate)
            case .weekly:
                WeeklyCalendarView(selectedDate: $selectedDate)
            case .monthly:
                MonthlyCalendarView(selectedDate: $selectedDate)
            case .yearly:
                YearlyCalendarView(selectedDate: $selectedDate)
            }
        }
    }
}

// MARK: - Daily Calendar View

/// Daily calendar: Full month calendar using graphical date picker
struct DailyCalendarView: View {
    @Binding var selectedDate: Date

    var body: some View {
        DatePicker("", selection: $selectedDate, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
    }
}

// MARK: - Weekly Calendar View

/// Weekly calendar: Month header with list of week pills
struct WeeklyCalendarView: View {
    @Binding var selectedDate: Date
    @State private var displayMonth: Date = Date()
    @State private var showingMonthPicker = false

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        return cal
    }

    var body: some View {
        VStack(spacing: 0) {
            // Month header with navigation (matching Daily style)
            HStack {
                Button {
                    displayMonth = calendar.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    showingMonthPicker = true
                } label: {
                    Text(monthYearText)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    displayMonth = calendar.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()
                .padding(.bottom, 8)

            // Week pills for the month
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(weeksInDisplayMonth, id: \.self) { weekStart in
                        WeekPillView(
                            weekStart: weekStart,
                            selectedDate: $selectedDate,
                            calendar: calendar
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .sheet(isPresented: $showingMonthPicker) {
            MonthYearPickerSheet(selectedDate: $displayMonth)
        }
    }

    private var monthYearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayMonth)
    }

    private var weeksInDisplayMonth: [Date] {
        var weeks: [Date] = []

        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth)) else {
            return weeks
        }

        guard let monthRange = calendar.range(of: .day, in: .month, for: displayMonth) else {
            return weeks
        }

        // Get all days in the month
        for day in monthRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }

            // Get the start of the week for this date
            guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) else {
                continue
            }

            // Only add if we haven't seen this week yet
            if !weeks.contains(where: { calendar.isDate($0, equalTo: weekStart, toGranularity: .weekOfYear) }) {
                weeks.append(weekStart)
            }
        }

        return weeks.sorted()
    }
}

/// Sheet for picking month and year (barrel/wheel picker)
struct MonthYearPickerSheet: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "Select Month",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
            }
            .navigationTitle("Select Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Individual week pill row
struct WeekPillView: View {
    let weekStart: Date
    @Binding var selectedDate: Date
    let calendar: Calendar

    private var isSelected: Bool {
        guard let selectedWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) else {
            return false
        }
        return calendar.isDate(weekStart, equalTo: selectedWeekStart, toGranularity: .weekOfYear)
    }

    private var weekNumber: Int {
        calendar.component(.weekOfYear, from: weekStart)
    }

    private var dateRangeText: String {
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let startText = formatter.string(from: weekStart)
        let endText = formatter.string(from: weekEnd)

        return "\(startText) - \(endText)"
    }

    var body: some View {
        Button {
            selectedDate = weekStart
        } label: {
            HStack(spacing: 12) {
                // Week badge
                Text("W\(weekNumber)")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.purple : Color.gray.opacity(0.2))
                    .clipShape(Circle())

                // Date range
                Text(dateRangeText)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Monthly Calendar View

/// Monthly calendar: Year header with 4x3 grid of months
struct MonthlyCalendarView: View {
    @Binding var selectedDate: Date
    @State private var displayYear: Date = Date()
    @State private var showingYearPicker = false

    private var calendar: Calendar {
        Calendar.current
    }

    private let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Year header with navigation (matching Daily/Weekly style)
            HStack {
                Button {
                    displayYear = calendar.date(byAdding: .year, value: -1, to: displayYear) ?? displayYear
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    showingYearPicker = true
                } label: {
                    Text(yearText)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    displayYear = calendar.date(byAdding: .year, value: 1, to: displayYear) ?? displayYear
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()
                .padding(.bottom, 8)

            // Month grid (4x3)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<12, id: \.self) { monthIndex in
                        MonthButton(
                            monthIndex: monthIndex,
                            monthName: monthNames[monthIndex],
                            displayYear: displayYear,
                            selectedDate: $selectedDate,
                            calendar: calendar
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .sheet(isPresented: $showingYearPicker) {
            YearPickerSheet(selectedDate: $displayYear)
        }
    }

    private var yearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: displayYear)
    }
}

/// Sheet for picking year
struct YearPickerSheet: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "Select Year",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
            }
            .navigationTitle("Select Year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Individual month button
struct MonthButton: View {
    let monthIndex: Int
    let monthName: String
    let displayYear: Date
    @Binding var selectedDate: Date
    let calendar: Calendar

    private var isSelected: Bool {
        let selectedMonth = calendar.component(.month, from: selectedDate)
        let selectedYear = calendar.component(.year, from: selectedDate)
        let displayYear = calendar.component(.year, from: self.displayYear)

        return selectedMonth == monthIndex + 1 && selectedYear == displayYear
    }

    var body: some View {
        Button {
            let year = calendar.component(.year, from: displayYear)
            var components = DateComponents()
            components.year = year
            components.month = monthIndex + 1
            components.day = 1

            if let newDate = calendar.date(from: components) {
                selectedDate = newDate
            }
        } label: {
            Text(monthName)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(isSelected ? Color.purple : Color(.secondarySystemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Yearly Calendar View

/// Yearly calendar: Scrollable grid of years
struct YearlyCalendarView: View {
    @Binding var selectedDate: Date

    private var calendar: Calendar {
        Calendar.current
    }

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private var years: [Int] {
        let currentYear = calendar.component(.year, from: Date())
        return Array((currentYear - 5)...(currentYear + 20))
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(years, id: \.self) { year in
                    YearButton(
                        year: year,
                        selectedDate: $selectedDate,
                        calendar: calendar
                    )
                }
            }
            .padding()
        }
        .frame(maxHeight: 400)
    }
}

/// Individual year button
struct YearButton: View {
    let year: Int
    @Binding var selectedDate: Date
    let calendar: Calendar

    private var isSelected: Bool {
        let selectedYear = calendar.component(.year, from: selectedDate)
        return selectedYear == year
    }

    var body: some View {
        Button {
            var components = DateComponents()
            components.year = year
            components.month = 1
            components.day = 1

            if let newDate = calendar.date(from: components) {
                selectedDate = newDate
            }
        } label: {
            Text("\(year)")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(isSelected ? Color.purple : Color(.secondarySystemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}
