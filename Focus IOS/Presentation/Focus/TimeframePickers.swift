//
//  TimeframePickers.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-06.
//

import SwiftUI

/// Unified date navigator with horizontal scrollable pills, adapted per timeframe
struct DateNavigator: View {
    @Binding var selectedDate: Date
    @Binding var selectedTimeframe: Timeframe
    @Binding var viewMode: FocusViewMode
    let compact: Bool
    let onCalendarTap: () -> Void

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        return cal
    }

    private let dayAbbreviations = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    var body: some View {
        if compact {
            // Schedule mode: same day pill row, no segmented picker
            VStack(spacing: 0) {
                // Row 1: (compact mode — currently unreachable, schedule hidden)
                EmptyView()
                    .frame(height: 32)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()

                // Row 2: Daily pill row with edge fade (same as focus daily)
                dailyPillRow
                    .frame(height: 56)
                    .mask(
                        HStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 24)
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 24)
                        }
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()

                // Row 3: Tappable date subtitle
                Button(action: onCalendarTap) {
                    Text(compactSubtitleText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)

                Divider()
            }
        } else {
            // Focus mode: full 3-row layout with dividers
            VStack(spacing: 0) {
                // Row 1: Segmented timeframe picker
                Picker("Timeframe", selection: $selectedTimeframe) {
                    Text("Daily").tag(Timeframe.daily)
                    Text("Weekly").tag(Timeframe.weekly)
                    Text("Monthly").tag(Timeframe.monthly)
                    Text("Yearly").tag(Timeframe.yearly)
                }
                .pickerStyle(.segmented)
                .frame(height: 32)
                .padding(.horizontal)
                .padding(.top, 40)
                .padding(.bottom, 14)

                Divider()

                // Row 2: Horizontal scrollable pills with edge fade (fixed height)
                timeframePillRow
                    .frame(height: 64)
                    .mask(
                        HStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 24)
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 24)
                        }
                    )
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                Divider()

                // Row 3: Tappable subtitle
                Button(action: onCalendarTap) {
                    Text(subtitleText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)

                Divider()
            }
        }
    }

    // MARK: - View Mode Toggle Icons (Schedule mode hidden)
    // To re-enable schedule mode, restore the HStack with focus/calendar toggle buttons below.

    private var viewModeIcons: some View {
        EmptyView()
    }

    // MARK: - Pill Row (switches on timeframe)

    @ViewBuilder
    private var timeframePillRow: some View {
        switch selectedTimeframe {
        case .daily:
            dailyPillRow
        case .weekly:
            weeklyPillRow
        case .monthly:
            monthlyPillRow
        case .yearly:
            yearlyPillRow
        }
    }

    // MARK: - Daily Pill Row (infinite scroll)

    private var displayDays: [Date] {
        (-14...14).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: selectedDate)
        }
    }

    private func dayPillId(for date: Date) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return "day-\(y)-\(m)-\(d)"
    }

    private var dailyPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                HStack(spacing: 8) {
                    ForEach(displayDays, id: \.self) { date in
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                        let isToday = calendar.isDateInToday(date)
                        let weekdayIndex = calendar.component(.weekday, from: date) - 1
                        let dayNumber = calendar.component(.day, from: date)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = date
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(dayAbbreviations[weekdayIndex])
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(isSelected ? .blue : .secondary)

                                Text("\(dayNumber)")
                                    .font(.body)
                                    .fontWeight(isSelected || isToday ? .bold : .regular)
                                    .foregroundColor(isSelected ? .white : (isToday ? .blue : .primary))
                                    .frame(width: 40, height: 40)
                                    .background(
                                        Circle()
                                            .fill(isSelected ? Color.blue : Color.clear)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(isToday && !isSelected ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                            }
                            .frame(width: 44)
                        }
                        .buttonStyle(.plain)
                        .id(dayPillId(for: date))
                    }
                }
                .padding(.horizontal)
                .onAppear {
                    proxy.scrollTo(dayPillId(for: selectedDate), anchor: .center)
                }
                .onChange(of: selectedDate) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(dayPillId(for: selectedDate), anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Weekly Pill Row

    private var displayWeeks: [Date] {
        guard let currentWeekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        ) else { return [] }
        return (-4...4).compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: offset, to: currentWeekStart)
        }
    }

    private func weekPillId(for date: Date) -> String {
        let w = calendar.component(.weekOfYear, from: date)
        let y = calendar.component(.yearForWeekOfYear, from: date)
        return "week-\(y)-\(w)"
    }

    private func shortWeekRange(from weekStart: Date) -> String {
        let startDay = calendar.component(.day, from: weekStart)
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return "\(startDay)"
        }
        let endDay = calendar.component(.day, from: weekEnd)
        return "\(startDay)-\(endDay)"
    }

    private func isSelectedWeek(_ weekStart: Date) -> Bool {
        let w1 = calendar.component(.weekOfYear, from: weekStart)
        let y1 = calendar.component(.yearForWeekOfYear, from: weekStart)
        let w2 = calendar.component(.weekOfYear, from: selectedDate)
        let y2 = calendar.component(.yearForWeekOfYear, from: selectedDate)
        return w1 == w2 && y1 == y2
    }

    private func isCurrentWeek(_ weekStart: Date) -> Bool {
        let w1 = calendar.component(.weekOfYear, from: weekStart)
        let y1 = calendar.component(.yearForWeekOfYear, from: weekStart)
        let w2 = calendar.component(.weekOfYear, from: Date())
        let y2 = calendar.component(.yearForWeekOfYear, from: Date())
        return w1 == w2 && y1 == y2
    }

    private var weeklyPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                HStack(spacing: 8) {
                    ForEach(displayWeeks, id: \.self) { weekStart in
                        let isSelected = isSelectedWeek(weekStart)
                        let isCurrent = isCurrentWeek(weekStart)
                        let weekNum = calendar.component(.weekOfYear, from: weekStart)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = weekStart
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text("W\(weekNum)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                Text(shortWeekRange(from: weekStart))
                                    .font(.caption2)
                            }
                            .foregroundColor(isSelected ? .white : .primary)
                            .frame(width: 68, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? Color.blue : Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isCurrent && !isSelected ? Color.blue : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(weekPillId(for: weekStart))
                    }
                }
                .padding(.horizontal)
                .onAppear {
                    proxy.scrollTo(weekPillId(for: selectedDate), anchor: .center)
                }
                .onChange(of: selectedDate) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(weekPillId(for: selectedDate), anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Monthly Pill Row

    private var displayMonths: [Date] {
        guard let currentMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: selectedDate)
        ) else { return [] }
        return (-3...8).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: currentMonthStart)
        }
    }

    private func monthPillId(for date: Date) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        return "month-\(y)-\(m)"
    }

    private func isSelectedMonth(_ date: Date) -> Bool {
        calendar.component(.month, from: date) == calendar.component(.month, from: selectedDate) &&
        calendar.component(.year, from: date) == calendar.component(.year, from: selectedDate)
    }

    private func isCurrentMonth(_ date: Date) -> Bool {
        let now = Date()
        return calendar.component(.month, from: date) == calendar.component(.month, from: now) &&
               calendar.component(.year, from: date) == calendar.component(.year, from: now)
    }

    private var monthlyPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                HStack(spacing: 8) {
                    ForEach(displayMonths, id: \.self) { monthDate in
                        let isSelected = isSelectedMonth(monthDate)
                        let isCurrent = isCurrentMonth(monthDate)
                        let formatter = DateFormatter()

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = monthDate
                            }
                        } label: {
                            Text({
                                formatter.dateFormat = "MMM"
                                return formatter.string(from: monthDate).uppercased()
                            }())
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(isSelected ? .white : .primary)
                                .frame(width: 64, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isSelected ? Color.blue : Color(.secondarySystemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isCurrent && !isSelected ? Color.blue : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .id(monthPillId(for: monthDate))
                    }
                }
                .padding(.horizontal)
                .onAppear {
                    proxy.scrollTo(monthPillId(for: selectedDate), anchor: .center)
                }
                .onChange(of: selectedDate) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(monthPillId(for: selectedDate), anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Yearly Pill Row

    private var displayYears: [Int] {
        let currentYear = calendar.component(.year, from: selectedDate)
        return Array((currentYear - 3)...(currentYear + 3))
    }

    private var yearlyPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                HStack(spacing: 8) {
                    ForEach(displayYears, id: \.self) { year in
                        let selectedYear = calendar.component(.year, from: selectedDate)
                        let currentYear = calendar.component(.year, from: Date())
                        let isSelected = year == selectedYear
                        let isCurrent = year == currentYear

                        Button {
                            if let newDate = calendar.date(from: DateComponents(year: year, month: calendar.component(.month, from: selectedDate), day: 1)) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedDate = newDate
                                }
                            }
                        } label: {
                            Text(String(year))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(isSelected ? .white : .primary)
                                .frame(width: 64, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isSelected ? Color.blue : Color(.secondarySystemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isCurrent && !isSelected ? Color.blue : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .id("year-\(year)")
                    }
                }
                .padding(.horizontal)
                .onAppear {
                    let selectedYear = calendar.component(.year, from: selectedDate)
                    proxy.scrollTo("year-\(selectedYear)", anchor: .center)
                }
                .onChange(of: selectedDate) {
                    let selectedYear = calendar.component(.year, from: selectedDate)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("year-\(selectedYear)", anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Subtitle Text

    private var subtitleText: String {
        switch selectedTimeframe {
        case .daily:
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE MMM d, yyyy"
            return formatter.string(from: selectedDate)

        case .weekly:
            return weekRangeText

        case .monthly:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM, yyyy"
            return formatter.string(from: selectedDate)

        case .yearly:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy"
            return formatter.string(from: selectedDate)
        }
    }

    // MARK: - Compact Subtitle (Schedule mode — always daily)

    private var compactSubtitleText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: selectedDate)
        return "\(dayName) – \(formattedDateWithOrdinal(selectedDate))"
    }

    // MARK: - Date Formatting Helpers

    private var weekRangeText: String {
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)),
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return ""
        }

        let startFormatter = DateFormatter()
        startFormatter.dateFormat = "MMM d"

        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "MMM d, yyyy"

        return "\(startFormatter.string(from: weekStart)) - \(endFormatter.string(from: weekEnd))"
    }

    private func formattedDateWithOrdinal(_ date: Date) -> String {
        let day = calendar.component(.day, from: date)
        let ordinal = ordinalSuffix(for: day)

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let month = formatter.string(from: date)

        formatter.dateFormat = "yyyy"
        let year = formatter.string(from: date)

        return "\(month) \(day)\(ordinal), \(year)"
    }

    private func ordinalSuffix(for day: Int) -> String {
        switch day {
        case 1, 21, 31: return "st"
        case 2, 22: return "nd"
        case 3, 23: return "rd"
        default: return "th"
        }
    }
}
