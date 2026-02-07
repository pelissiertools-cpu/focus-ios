//
//  UnifiedCalendarPicker.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-06.
//

import SwiftUI

/// Unified calendar picker that adapts based on selected timeframe
struct UnifiedCalendarPicker: View {
    @Binding var selectedDates: Set<Date>
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
                DailyCalendarView(selectedDates: $selectedDates)
            case .weekly:
                WeeklyCalendarView(selectedDates: $selectedDates)
            case .monthly:
                MonthlyCalendarView(selectedDates: $selectedDates)
            case .yearly:
                YearlyCalendarView(selectedDates: $selectedDates)
            }
        }
    }
}

// MARK: - Daily Calendar View

/// Daily calendar: Custom grid with toggle selection
struct DailyCalendarView: View {
    @Binding var selectedDates: Set<Date>
    @State private var displayMonth: Date = Date()

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        return cal
    }

    private let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            // Month header with navigation
            HStack {
                Button {
                    displayMonth = calendar.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(monthYearText)
                    .font(.headline)
                    .foregroundColor(.primary)

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

            // Weekday headers
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .padding(.horizontal)

            // Calendar grid
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(daysInMonth, id: \.self) { day in
                    if let day = day {
                        DayCell(
                            date: day,
                            selectedDates: $selectedDates,
                            isToday: calendar.isDateInToday(day),
                            calendar: calendar
                        )
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var monthYearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayMonth)
    }

    private var daysInMonth: [Date?] {
        var days: [Date?] = []

        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth)),
              let monthRange = calendar.range(of: .day, in: .month, for: displayMonth) else {
            return days
        }

        // Add empty cells for days before the first of the month
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let emptyDays = firstWeekday - 1
        for _ in 0..<emptyDays {
            days.append(nil)
        }

        // Add all days in the month
        for day in monthRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                days.append(date)
            }
        }

        return days
    }
}

/// Individual day cell in the calendar
struct DayCell: View {
    let date: Date
    @Binding var selectedDates: Set<Date>
    let isToday: Bool
    let calendar: Calendar

    private var normalizedDate: Date {
        calendar.startOfDay(for: date)
    }

    private var isSelected: Bool {
        selectedDates.contains { calendar.isDate($0, inSameDayAs: date) }
    }

    private var dayNumber: String {
        let day = calendar.component(.day, from: date)
        return "\(day)"
    }

    private var backgroundColor: Color {
        if isSelected {
            return .blue
        } else if isToday {
            return Color.gray.opacity(0.3)
        } else {
            return .clear
        }
    }

    private var textColor: Color {
        if isSelected {
            return .white
        } else {
            return .primary
        }
    }

    var body: some View {
        Button {
            toggleSelection()
        } label: {
            Text(dayNumber)
                .font(.body)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundColor(textColor)
                .frame(width: 36, height: 36)
                .background(backgroundColor)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection() {
        if let existingDate = selectedDates.first(where: { calendar.isDate($0, inSameDayAs: date) }) {
            selectedDates.remove(existingDate)
        } else {
            selectedDates.insert(normalizedDate)
        }
    }
}

// MARK: - Weekly Calendar View

/// Weekly calendar: Month header with list of week pills
struct WeeklyCalendarView: View {
    @Binding var selectedDates: Set<Date>
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
                            selectedDates: $selectedDates,
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
    @Binding var selectedDates: Set<Date>
    let calendar: Calendar

    private var isSelected: Bool {
        selectedDates.contains { date in
            let dateWeek = calendar.component(.weekOfYear, from: date)
            let dateYear = calendar.component(.yearForWeekOfYear, from: date)
            let weekStartWeek = calendar.component(.weekOfYear, from: weekStart)
            let weekStartYear = calendar.component(.yearForWeekOfYear, from: weekStart)
            return dateWeek == weekStartWeek && dateYear == weekStartYear
        }
    }

    private var isCurrentWeek: Bool {
        let today = Date()
        let todayWeek = calendar.component(.weekOfYear, from: today)
        let todayYear = calendar.component(.yearForWeekOfYear, from: today)
        let weekStartWeek = calendar.component(.weekOfYear, from: weekStart)
        let weekStartYear = calendar.component(.yearForWeekOfYear, from: weekStart)
        return todayWeek == weekStartWeek && todayYear == weekStartYear
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

    private var badgeColor: Color {
        if isSelected {
            return .blue
        } else if isCurrentWeek {
            return Color.gray.opacity(0.4)
        } else {
            return Color.gray.opacity(0.2)
        }
    }

    var body: some View {
        Button {
            toggleSelection()
        } label: {
            HStack(spacing: 12) {
                // Week badge
                Text("W\(weekNumber)")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(width: 44, height: 44)
                    .background(badgeColor)
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
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection() {
        if let existingDate = selectedDates.first(where: { date in
            let dateWeek = calendar.component(.weekOfYear, from: date)
            let dateYear = calendar.component(.yearForWeekOfYear, from: date)
            let weekStartWeek = calendar.component(.weekOfYear, from: weekStart)
            let weekStartYear = calendar.component(.yearForWeekOfYear, from: weekStart)
            return dateWeek == weekStartWeek && dateYear == weekStartYear
        }) {
            selectedDates.remove(existingDate)
        } else {
            selectedDates.insert(weekStart)
        }
    }
}

// MARK: - Monthly Calendar View

/// Monthly calendar: Year header with 4x3 grid of months
struct MonthlyCalendarView: View {
    @Binding var selectedDates: Set<Date>
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
                            selectedDates: $selectedDates,
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
    @Binding var selectedDates: Set<Date>
    let calendar: Calendar

    private var displayYearValue: Int {
        calendar.component(.year, from: displayYear)
    }

    private var isSelected: Bool {
        selectedDates.contains { date in
            let dateMonth = calendar.component(.month, from: date)
            let dateYear = calendar.component(.year, from: date)
            return dateMonth == monthIndex + 1 && dateYear == displayYearValue
        }
    }

    private var isCurrentMonth: Bool {
        let today = Date()
        let currentMonth = calendar.component(.month, from: today)
        let currentYear = calendar.component(.year, from: today)
        return currentMonth == monthIndex + 1 && currentYear == displayYearValue
    }

    private var backgroundColor: Color {
        if isSelected {
            return .blue
        } else if isCurrentMonth {
            return Color.gray.opacity(0.3)
        } else {
            return Color(.secondarySystemBackground)
        }
    }

    var body: some View {
        Button {
            toggleSelection()
        } label: {
            Text(monthName)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(backgroundColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection() {
        let year = displayYearValue
        var components = DateComponents()
        components.year = year
        components.month = monthIndex + 1
        components.day = 1

        guard let monthDate = calendar.date(from: components) else { return }

        if let existingDate = selectedDates.first(where: { date in
            let dateMonth = calendar.component(.month, from: date)
            let dateYear = calendar.component(.year, from: date)
            return dateMonth == monthIndex + 1 && dateYear == year
        }) {
            selectedDates.remove(existingDate)
        } else {
            selectedDates.insert(monthDate)
        }
    }
}

// MARK: - Yearly Calendar View

/// Yearly calendar: Scrollable grid of years
struct YearlyCalendarView: View {
    @Binding var selectedDates: Set<Date>

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
                        selectedDates: $selectedDates,
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
    @Binding var selectedDates: Set<Date>
    let calendar: Calendar

    private var isSelected: Bool {
        selectedDates.contains { date in
            calendar.component(.year, from: date) == year
        }
    }

    private var isCurrentYear: Bool {
        calendar.component(.year, from: Date()) == year
    }

    private var backgroundColor: Color {
        if isSelected {
            return .blue
        } else if isCurrentYear {
            return Color.gray.opacity(0.3)
        } else {
            return Color(.secondarySystemBackground)
        }
    }

    var body: some View {
        Button {
            toggleSelection()
        } label: {
            Text("\(year)")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(backgroundColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection() {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1

        guard let yearDate = calendar.date(from: components) else { return }

        if let existingDate = selectedDates.first(where: { date in
            calendar.component(.year, from: date) == year
        }) {
            selectedDates.remove(existingDate)
        } else {
            selectedDates.insert(yearDate)
        }
    }
}
