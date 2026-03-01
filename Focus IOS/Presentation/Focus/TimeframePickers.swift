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
                // Profile button row
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
                            Text(LocalizedStringKey(selectedTimeframe.displayName))
                                .font(.inter(.subheadline, weight: .medium))
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
                                            .foregroundColor(.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.inter(size: 8, weight: .semiBold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.bottom, 4)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
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
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = weekStart
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text("W\(weekNum)")
                                    .font(.montserratHeader(.caption, weight: .bold))
                                Text(shortWeekRange(from: weekStart))
                                    .font(.montserratHeader(.caption2))
                            }
                            .foregroundColor(isSelected ? .white : (isCurrent ? Color.appRed : .primary))
                            .frame(width: 68, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? Color.appRed : Color(.secondarySystemBackground))
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
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = monthDate
                            }
                        } label: {
                            Text({
                                formatter.dateFormat = "MMM"
                                formatter.locale = LanguageManager.shared.locale
                                return formatter.string(from: monthDate).uppercased()
                            }())
                                .font(.montserratHeader(.subheadline, weight: .medium))
                                .foregroundColor(isSelected ? .white : (isCurrent ? Color.appRed : .primary))
                                .frame(width: 64, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isSelected ? Color.appRed : Color(.secondarySystemBackground))
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
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if let newDate = calendar.date(from: DateComponents(year: year, month: calendar.component(.month, from: selectedDate), day: 1)) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedDate = newDate
                                }
                            }
                        } label: {
                            Text(String(year))
                                .font(.montserratHeader(.subheadline, weight: .medium))
                                .foregroundColor(isSelected ? .white : (isCurrent ? Color.appRed : .primary))
                                .frame(width: 64, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isSelected ? Color.appRed : Color(.secondarySystemBackground))
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
