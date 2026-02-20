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
    var onProfileTap: (() -> Void)? = nil
    @EnvironmentObject var languageManager: LanguageManager
    @Namespace private var timeframeAnimation

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
                // Row 1: (compact mode — currently unreachable, schedule hidden)
                EmptyView()
                    .frame(height: 32)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()
                    .padding(.horizontal, 16)

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
                    .padding(.horizontal, 16)

                // Row 3: Tappable date subtitle
                Button(action: onCalendarTap) {
                    Text(compactSubtitleText)
                        .font(.montserratHeader(.subheadline, weight: .medium))
                        .foregroundColor(.black)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)

                Divider()
                    .padding(.horizontal, 16)
            }
        } else {
            // Focus mode: full layout with dividers
            VStack(spacing: 0) {
                // Row 0: Profile button — own row, left-aligned
                if let onProfileTap {
                    HStack {
                        Button(action: onProfileTap) {
                            Image(systemName: "person")
                                .font(.sf(.body, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 36, height: 36)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        Spacer()
                    }
                    .padding(.leading, 20)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                }

                // Row 1: Glass timeframe picker
                HStack(spacing: 0) {
                    ForEach(Timeframe.allCases, id: \.self) { timeframe in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                selectedTimeframe = timeframe
                            }
                        } label: {
                            Text(LocalizedStringKey(timeframe.displayName))
                                .font(.sf(.subheadline, weight: selectedTimeframe == timeframe ? .semibold : .medium))
                                .foregroundStyle(selectedTimeframe == timeframe ? .primary : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background {
                                    if selectedTimeframe == timeframe {
                                        Color.clear
                                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                                            .matchedGeometryEffect(id: "activeTimeframe", in: timeframeAnimation)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 14)

                // Date navigator container: pills + date subtitle
                VStack(spacing: 0) {
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
                        .padding(.bottom, 8)

                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white, lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                .padding(.horizontal)

                // Date label container
                HStack {
                    Spacer()
                    Button(action: onCalendarTap) {
                        Text(subtitleText)
                            .font(.montserratHeader(.subheadline, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
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
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = date
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(String(dayAbbreviations[weekdayIndex].prefix(1)))
                                    .font(.montserratHeader(.caption2, weight: .medium))
                                    .foregroundColor(.primary)

                                Text("\(dayNumber)")
                                    .font(.montserratHeader(.body, weight: isSelected || isToday ? .bold : .regular))
                                    .foregroundColor(isSelected ? .white : (isToday ? Color(red: 0xF8/255, green: 0x1E/255, blue: 0x1D/255) : .primary))
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(isSelected ? Color(red: 0xF8/255, green: 0x1E/255, blue: 0x1D/255) : Color.clear)
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
                            .foregroundColor(isSelected ? .white : (isCurrent ? Color(red: 0xF8/255, green: 0x1E/255, blue: 0x1D/255) : .primary))
                            .frame(width: 68, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? Color(red: 0xF8/255, green: 0x1E/255, blue: 0x1D/255) : Color(.secondarySystemBackground))
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
                                .foregroundColor(isSelected ? .white : (isCurrent ? Color(red: 0xF8/255, green: 0x1E/255, blue: 0x1D/255) : .primary))
                                .frame(width: 64, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isSelected ? Color(red: 0xF8/255, green: 0x1E/255, blue: 0x1D/255) : Color(.secondarySystemBackground))
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
                                .foregroundColor(isSelected ? .white : (isCurrent ? Color(red: 0xF8/255, green: 0x1E/255, blue: 0x1D/255) : .primary))
                                .frame(width: 64, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isSelected ? Color(red: 0xF8/255, green: 0x1E/255, blue: 0x1D/255) : Color(.secondarySystemBackground))
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
        let locale = LanguageManager.shared.locale
        switch selectedTimeframe {
        case .daily:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "EEE MMM d, yyyy"
            return formatter.string(from: selectedDate)

        case .weekly:
            return weekRangeText

        case .monthly:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "MMMM, yyyy"
            return formatter.string(from: selectedDate)

        case .yearly:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "yyyy"
            return formatter.string(from: selectedDate)
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
