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
    var onProfileTap: (() -> Void)? = nil
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var visibleWeekStart: Date?
    @State private var visibleMonthPage: Date?
    @State private var visibleYearPageDate: Date?
    @State private var showCalendarPicker = false

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        return cal
    }

    private var dayAbbreviations: [String] {
        var cal = Calendar.current
        cal.locale = LanguageManager.shared.locale
        return cal.shortWeekdaySymbols.map { $0.replacingOccurrences(of: ".", with: "").uppercased() }
    }

    var body: some View {
        if compact {
            // Schedule mode: same day pill row, no segmented picker
            VStack(spacing: 0) {
                EmptyView()
                    .frame(height: 32)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()
                    .padding(.horizontal, 16)

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
                    .padding(.horizontal, 16)

                Text(compactSubtitleText)
                    .font(.montserratHeader(.subheadline, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.vertical, 8)

                Divider()
                    .padding(.horizontal, 16)
            }
        } else {
            // Focus mode: full layout
            VStack(spacing: 0) {
                // Profile button row with centered To-Do title
                if let onProfileTap {
                    HStack {
                        Spacer()
                        Button(action: onProfileTap) {
                            Image(systemName: "person")
                                .font(.inter(.body, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 36, height: 36)
                                .glassEffect(.regular.tint(.glassTint).interactive(), in: .circle)
                        }
                    }
                    .padding(.trailing, 32)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                }

                // Date navigator container
                VStack(spacing: 0) {
                    // Upper section: dropdown + date display
                    VStack(alignment: .leading, spacing: 0) {
                        // Timeframe dropdown
                        Menu {
                            ForEach(Timeframe.allCases, id: \.self) { timeframe in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedTimeframe = timeframe
                                } label: {
                                    if selectedTimeframe == timeframe {
                                        Label(timeframe.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(timeframe.displayName)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(LocalizedStringKey(selectedTimeframe.displayName))
                                    .font(.inter(.subheadline, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.inter(size: 8, weight: .semiBold))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .padding(.top, 10)

                        // Date display
                        HStack(alignment: .bottom, spacing: 8) {
                            Text(primaryDateText)
                                .font(.inter(size: 32, weight: .regular))
                                .foregroundColor(.primary)

                            Spacer()

                            if let secondary = secondaryDateText {
                                Button {
                                    showCalendarPicker = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(secondary)
                                            .font(.montserratHeader(.subheadline, weight: .medium))
                                            .foregroundColor(.primary)
                                        Image(systemName: "chevron.right")
                                            .font(.inter(size: 8, weight: .semiBold))
                                            .foregroundColor(.primary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.bottom, 4)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    }
                    .padding(.horizontal)
                    // Pill row (always visible) — 14pt side margin to match focus container
                    timeframePillRow
                        .frame(height: 64)
                        .padding(.bottom, 8)
                }
                .clipped()
                .sheet(isPresented: $showCalendarPicker) {
                    SingleSelectCalendarPicker(
                        selectedDate: $selectedDate,
                        timeframe: selectedTimeframe
                    )
                    .drawerStyle()
                }
            }
        }
    }

    // MARK: - Primary Date Text (large, centered)

    private var primaryDateText: String {
        let locale = LanguageManager.shared.locale
        let formatter = DateFormatter()
        formatter.locale = locale

        switch selectedTimeframe {
        case .daily:
            formatter.dateFormat = "EEEE"
            return formatter.string(from: selectedDate)
        case .weekly:
            let weekNum = calendar.component(.weekOfYear, from: selectedDate)
            return "Week \(weekNum)"
        case .monthly:
            formatter.dateFormat = "MMMM"
            return formatter.string(from: selectedDate)
        case .yearly:
            return String(calendar.component(.year, from: selectedDate))
        }
    }

    // MARK: - Secondary Date Text (smaller, below primary)

    private var secondaryDateText: String? {
        switch selectedTimeframe {
        case .daily:
            return formattedDateWithOrdinalFull(selectedDate)
        case .weekly:
            return weekRangeText
        case .monthly:
            return String(calendar.component(.year, from: selectedDate))
        case .yearly:
            return nil
        }
    }

    // MARK: - Navigation

    private func navigatePrev() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            switch selectedTimeframe {
            case .daily:
                selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            case .weekly:
                selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
            case .monthly:
                selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
            case .yearly:
                selectedDate = calendar.date(byAdding: .year, value: -1, to: selectedDate) ?? selectedDate
            }
        }
    }

    private func navigateNext() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            switch selectedTimeframe {
            case .daily:
                selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            case .weekly:
                selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
            case .monthly:
                selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
            case .yearly:
                selectedDate = calendar.date(byAdding: .year, value: 1, to: selectedDate) ?? selectedDate
            }
        }
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

    // MARK: - Daily Pill Row (paged week view, Sun–Sat)

    private func weekStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
    }

    private func daysInWeek(from weekStart: Date) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var displayWeekStarts: [Date] {
        let anchor = weekStart(for: Date())
        return (-52...52).compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: offset, to: anchor)
        }
    }

    private var dailyPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(displayWeekStarts, id: \.self) { ws in
                    weekDayRow(for: ws)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $visibleWeekStart)
        .onAppear {
            visibleWeekStart = weekStart(for: selectedDate)
        }
        .onChange(of: visibleWeekStart) {
            guard let newWeekStart = visibleWeekStart else { return }
            // Only update selectedDate if it's not already in the visible week
            if weekStart(for: selectedDate) != newWeekStart {
                let currentWeekday = calendar.component(.weekday, from: selectedDate)
                let offset = currentWeekday - calendar.component(.weekday, from: newWeekStart)
                if let newDate = calendar.date(byAdding: .day, value: offset, to: newWeekStart) {
                    selectedDate = newDate
                }
            }
        }
        .onChange(of: selectedDate) {
            let newWeek = weekStart(for: selectedDate)
            if visibleWeekStart != newWeek {
                withAnimation {
                    visibleWeekStart = newWeek
                }
            }
        }
    }

    private func weekDayRow(for weekStart: Date) -> some View {
        let days = daysInWeek(from: weekStart)
        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { date in
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(date)
                let weekdayIndex = calendar.component(.weekday, from: date) - 1
                let dayNumber = calendar.component(.day, from: date)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedDate = date
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(String(dayAbbreviations[weekdayIndex].prefix(1)))
                            .font(.montserratHeader(.caption2, weight: .medium))
                            .foregroundColor(isSelected ? .primary : .secondary)

                        Text("\(dayNumber)")
                            .font(.montserratHeader(.body, weight: isSelected || isToday ? .bold : .regular))
                            .foregroundColor(isSelected ? .white : .secondary)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.darkGray : Color.clear)
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Weekly Pill Row (paged by month, shows weeks of the month)

    private func monthStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private var displayMonthPages: [Date] {
        let anchor = monthStart(for: Date())
        return (-24...24).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: anchor)
        }
    }

    private func weeksInMonth(_ month: Date) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        var weeks: [Date] = []
        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: month) else { continue }
            let ws = weekStart(for: date)
            if !weeks.contains(where: { calendar.isDate($0, equalTo: ws, toGranularity: .weekOfYear) }) {
                weeks.append(ws)
            }
        }
        return weeks.sorted()
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

    private func shortWeekRange(from weekStart: Date) -> String {
        let startDay = calendar.component(.day, from: weekStart)
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return "\(startDay)"
        }
        let endDay = calendar.component(.day, from: weekEnd)
        return "\(startDay)-\(endDay)"
    }

    private func weekNumberInMonth(_ ws: Date, month: Date) -> Int {
        let weeks = weeksInMonth(month)
        return (weeks.firstIndex(where: { calendar.isDate($0, equalTo: ws, toGranularity: .weekOfYear) }) ?? 0) + 1
    }

    private var weeklyPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(displayMonthPages, id: \.self) { month in
                    weekPageRow(for: month)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $visibleMonthPage)
        .onAppear {
            visibleMonthPage = monthStart(for: selectedDate)
        }
        .onChange(of: visibleMonthPage) {
            guard let newMonth = visibleMonthPage else { return }
            if monthStart(for: selectedDate) != newMonth {
                // Move to same week-of-month in new month
                let currentWeeks = weeksInMonth(monthStart(for: selectedDate))
                let currentIdx = currentWeeks.firstIndex(where: { isSelectedWeek($0) }) ?? 0
                let newWeeks = weeksInMonth(newMonth)
                let clampedIdx = min(currentIdx, newWeeks.count - 1)
                if clampedIdx >= 0 && clampedIdx < newWeeks.count {
                    selectedDate = newWeeks[clampedIdx]
                }
            }
        }
        .onChange(of: selectedDate) {
            let newMonth = monthStart(for: selectedDate)
            if visibleMonthPage != newMonth {
                withAnimation {
                    visibleMonthPage = newMonth
                }
            }
        }
    }

    private func weekPageRow(for month: Date) -> some View {
        let weeks = weeksInMonth(month)
        return HStack(spacing: 0) {
            ForEach(weeks, id: \.self) { ws in
                let isSelected = isSelectedWeek(ws)
                let isCurrent = isCurrentWeek(ws)
                let weekInMonth = weekNumberInMonth(ws, month: month)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedDate = ws
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text("W\(weekInMonth)")
                            .font(.montserratHeader(.caption2, weight: .medium))
                            .foregroundColor(isSelected ? .primary : .secondary)

                        Text(shortWeekRange(from: ws))
                            .font(.montserratHeader(.body, weight: isSelected || isCurrent ? .bold : .regular))
                            .foregroundColor(isSelected ? .white : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.darkGray : Color.clear)
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Monthly Pill Row (paged by half-year, shows 6 months per page)

    private func halfYearStart(for date: Date) -> Date {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let startMonth = month <= 6 ? 1 : 7
        return calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? date
    }

    private var displayHalfYearPages: [Date] {
        let anchor = halfYearStart(for: Date())
        // Generate half-year pages: each year has 2 pages (Jan, Jul)
        return (-20...20).compactMap { offset in
            calendar.date(byAdding: .month, value: offset * 6, to: anchor)
        }
    }

    private func monthsInHalfYear(_ start: Date) -> [Date] {
        (0..<6).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
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

    private func shortMonthName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.locale = LanguageManager.shared.locale
        return formatter.string(from: date).uppercased()
    }

    private var monthlyPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(displayHalfYearPages, id: \.self) { halfYear in
                    monthPageRow(for: halfYear)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $visibleYearPageDate)
        .onAppear {
            visibleYearPageDate = halfYearStart(for: selectedDate)
        }
        .onChange(of: visibleYearPageDate) {
            guard let newHalf = visibleYearPageDate else { return }
            if halfYearStart(for: selectedDate) != newHalf {
                // Move to same relative month in new half-year
                let currentHalf = halfYearStart(for: selectedDate)
                let currentMonth = calendar.component(.month, from: selectedDate)
                let offsetInHalf = calendar.component(.month, from: currentHalf)
                let relativeOffset = currentMonth - offsetInHalf
                let newHalfMonth = calendar.component(.month, from: newHalf)
                let targetMonth = newHalfMonth + min(relativeOffset, 5)
                if let newDate = calendar.date(from: DateComponents(
                    year: calendar.component(.year, from: newHalf),
                    month: targetMonth,
                    day: 1
                )) {
                    selectedDate = newDate
                }
            }
        }
        .onChange(of: selectedDate) {
            let newHalf = halfYearStart(for: selectedDate)
            if visibleYearPageDate != newHalf {
                withAnimation {
                    visibleYearPageDate = newHalf
                }
            }
        }
    }

    private func monthPageRow(for halfYearStart: Date) -> some View {
        let months = monthsInHalfYear(halfYearStart)
        return HStack(spacing: 0) {
            ForEach(months, id: \.self) { monthDate in
                let isSelected = isSelectedMonth(monthDate)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedDate = monthDate
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(shortMonthName(for: monthDate))
                            .font(.montserratHeader(.footnote, weight: .medium))
                            .foregroundColor(isSelected ? .white : .secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Color.darkGray : Color.clear)
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Yearly Pill Row (fixed: 2026–2030)

    private var yearlyPillRow: some View {
        let years = Array(2026...2030)
        let selectedYear = calendar.component(.year, from: selectedDate)
        return HStack(spacing: 0) {
            ForEach(years, id: \.self) { year in
                let isSelected = year == selectedYear

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let newDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = newDate
                        }
                    }
                } label: {
                    Text(String(year))
                        .font(.montserratHeader(.footnote, weight: .medium))
                        .foregroundColor(isSelected ? .white : .secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.darkGray : Color.clear)
                        )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Compact Subtitle (Schedule mode — always daily)

    private var compactSubtitleText: String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
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

        let locale = LanguageManager.shared.locale
        let startFormatter = DateFormatter()
        startFormatter.locale = locale
        startFormatter.dateFormat = "MMM d"

        let endFormatter = DateFormatter()
        endFormatter.locale = locale
        endFormatter.dateFormat = "MMM d, yyyy"

        return "\(startFormatter.string(from: weekStart)) - \(endFormatter.string(from: weekEnd))"
    }

    /// Full month format for date display: "February 20th, 2026"
    private func formattedDateWithOrdinalFull(_ date: Date) -> String {
        let day = calendar.component(.day, from: date)
        let ordinal = ordinalSuffix(for: day)

        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: date)

        formatter.dateFormat = "yyyy"
        let year = formatter.string(from: date)

        return "\(month) \(day)\(ordinal), \(year)"
    }

    /// Short month format for compact subtitle: "Feb 20th, 2026"
    private func formattedDateWithOrdinal(_ date: Date) -> String {
        let day = calendar.component(.day, from: date)
        let ordinal = ordinalSuffix(for: day)

        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
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
