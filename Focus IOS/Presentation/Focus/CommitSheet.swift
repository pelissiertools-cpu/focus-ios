//
//  BreakdownSheet.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-07.
//

import SwiftUI

/// Sheet for committing a task to a lower timeframe
struct CommitSheet: View {
    let commitment: Commitment
    let task: FocusTask
    @ObservedObject var viewModel: FocusTabViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedTargetTimeframe: Timeframe
    @State private var selectedDates: Set<Date> = []
    @State private var isSaving = false

    /// Available timeframes for breakdown (all lower than current)
    private var availableTimeframes: [Timeframe] {
        commitment.timeframe.availableBreakdownTimeframes
    }

    /// Existing child commitments for the selected timeframe
    private var existingChildrenForTimeframe: [Commitment] {
        viewModel.getChildCommitments(for: commitment.id)
            .filter { $0.timeframe == selectedTargetTimeframe }
    }

    init(commitment: Commitment, task: FocusTask, viewModel: FocusTabViewModel) {
        self.commitment = commitment
        self.task = task
        self.viewModel = viewModel
        // Default to first available timeframe
        _selectedTargetTimeframe = State(initialValue: commitment.timeframe.availableBreakdownTimeframes.first ?? .daily)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header info
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title)
                        .font(.headline)

                    HStack {
                        Image(systemName: "arrow.down.forward.circle")
                            .foregroundColor(.blue)
                        Text("Commit to lower timeframe")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

                Divider()

                // Existing breakdown summary
                if !existingChildrenForTimeframe.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("\(existingChildrenForTimeframe.count) already committed to \(selectedTargetTimeframe.displayName.lowercased())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                // Calendar picker with timeframe selector
                BreakdownCalendarPicker(
                    selectedDates: $selectedDates,
                    selectedTimeframe: $selectedTargetTimeframe,
                    availableTimeframes: availableTimeframes,
                    commitment: commitment,
                    viewModel: viewModel
                )
                .padding(.top, 8)

                Spacer()
            }
            .navigationTitle("Commit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        Task {
                            await addSelectedCommitments()
                        }
                    }
                    .disabled(selectedDates.isEmpty || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedTargetTimeframe) { _ in
                // Clear selections when timeframe changes
                selectedDates.removeAll()
            }
        }
    }

    private func addSelectedCommitments() async {
        isSaving = true

        for date in selectedDates.sorted() {
            await viewModel.commitToTimeframe(commitment, toDate: date, targetTimeframe: selectedTargetTimeframe)
        }

        isSaving = false
        dismiss()
    }
}

/// Calendar picker variant for breakdown that only shows lower timeframes
struct BreakdownCalendarPicker: View {
    @Binding var selectedDates: Set<Date>
    @Binding var selectedTimeframe: Timeframe
    let availableTimeframes: [Timeframe]
    let commitment: Commitment
    @ObservedObject var viewModel: FocusTabViewModel

    /// Dates already broken down for the selected timeframe
    private var excludedDates: Set<Date> {
        let calendar = Calendar.current
        let existingChildren = viewModel.getChildCommitments(for: commitment.id)
            .filter { $0.timeframe == selectedTimeframe }
        return Set(existingChildren.map { calendar.startOfDay(for: $0.commitmentDate) })
    }

    var body: some View {
        VStack(spacing: 16) {
            // Timeframe picker (only show if multiple options)
            if availableTimeframes.count > 1 {
                Picker("Timeframe", selection: $selectedTimeframe) {
                    ForEach(availableTimeframes, id: \.self) { tf in
                        Text(tf.displayName).tag(tf)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }

            // Calendar view based on selected timeframe
            switch selectedTimeframe {
            case .daily:
                BreakdownDailyCalendarView(
                    selectedDates: $selectedDates,
                    excludedDates: excludedDates,
                    commitment: commitment
                )
            case .weekly:
                BreakdownWeeklyCalendarView(
                    selectedDates: $selectedDates,
                    excludedDates: excludedDates,
                    commitment: commitment
                )
            case .monthly:
                BreakdownMonthlyCalendarView(
                    selectedDates: $selectedDates,
                    excludedDates: excludedDates,
                    commitment: commitment
                )
            case .yearly:
                // Should not happen - yearly is never a breakdown target
                EmptyView()
            }
        }
    }
}

// MARK: - Breakdown Daily Calendar View

/// Daily calendar for breakdown, scoped to parent commitment's date range
struct BreakdownDailyCalendarView: View {
    @Binding var selectedDates: Set<Date>
    let excludedDates: Set<Date>
    let commitment: Commitment

    @State private var displayMonth: Date

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        return cal
    }

    private let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    init(selectedDates: Binding<Set<Date>>, excludedDates: Set<Date>, commitment: Commitment) {
        self._selectedDates = selectedDates
        self.excludedDates = excludedDates
        self.commitment = commitment
        // Initialize display month based on commitment date
        _displayMonth = State(initialValue: commitment.commitmentDate)
    }

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
                        BreakdownDayCell(
                            date: day,
                            selectedDates: $selectedDates,
                            excludedDates: excludedDates,
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

/// Day cell for breakdown calendar
struct BreakdownDayCell: View {
    let date: Date
    @Binding var selectedDates: Set<Date>
    let excludedDates: Set<Date>
    let isToday: Bool
    let calendar: Calendar

    private var normalizedDate: Date {
        calendar.startOfDay(for: date)
    }

    private var isExcluded: Bool {
        excludedDates.contains(normalizedDate)
    }

    private var isSelected: Bool {
        selectedDates.contains { calendar.isDate($0, inSameDayAs: date) }
    }

    private var dayNumber: String {
        let day = calendar.component(.day, from: date)
        return "\(day)"
    }

    private var backgroundColor: Color {
        if isExcluded {
            return Color.green.opacity(0.3)
        } else if isSelected {
            return .blue
        } else if isToday {
            return Color.gray.opacity(0.3)
        } else {
            return .clear
        }
    }

    private var textColor: Color {
        if isExcluded {
            return .secondary
        } else if isSelected {
            return .white
        } else {
            return .primary
        }
    }

    var body: some View {
        Button {
            if !isExcluded {
                toggleSelection()
            }
        } label: {
            Text(dayNumber)
                .font(.body)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundColor(textColor)
                .frame(width: 36, height: 36)
                .background(backgroundColor)
                .clipShape(Circle())
                .overlay(
                    isExcluded ?
                        Image(systemName: "checkmark")
                            .font(.caption2)
                            .foregroundColor(.green) : nil
                )
        }
        .buttonStyle(.plain)
        .disabled(isExcluded)
    }

    private func toggleSelection() {
        if let existingDate = selectedDates.first(where: { calendar.isDate($0, inSameDayAs: date) }) {
            selectedDates.remove(existingDate)
        } else {
            selectedDates.insert(normalizedDate)
        }
    }
}

// MARK: - Breakdown Weekly Calendar View

/// Weekly calendar for breakdown
struct BreakdownWeeklyCalendarView: View {
    @Binding var selectedDates: Set<Date>
    let excludedDates: Set<Date>
    let commitment: Commitment

    @State private var displayMonth: Date

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        return cal
    }

    init(selectedDates: Binding<Set<Date>>, excludedDates: Set<Date>, commitment: Commitment) {
        self._selectedDates = selectedDates
        self.excludedDates = excludedDates
        self.commitment = commitment
        _displayMonth = State(initialValue: commitment.commitmentDate)
    }

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

            // Week pills for the month
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(weeksInDisplayMonth, id: \.self) { weekStart in
                        BreakdownWeekPillView(
                            weekStart: weekStart,
                            selectedDates: $selectedDates,
                            excludedDates: excludedDates,
                            calendar: calendar
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var monthYearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayMonth)
    }

    private var weeksInDisplayMonth: [Date] {
        var weeks: [Date] = []

        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth)),
              let monthRange = calendar.range(of: .day, in: .month, for: displayMonth) else {
            return weeks
        }

        for day in monthRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }

            guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) else {
                continue
            }

            if !weeks.contains(where: { calendar.isDate($0, equalTo: weekStart, toGranularity: .weekOfYear) }) {
                weeks.append(weekStart)
            }
        }

        return weeks.sorted()
    }
}

/// Week pill for breakdown
struct BreakdownWeekPillView: View {
    let weekStart: Date
    @Binding var selectedDates: Set<Date>
    let excludedDates: Set<Date>
    let calendar: Calendar

    private var normalizedWeekStart: Date {
        calendar.startOfDay(for: weekStart)
    }

    private var isExcluded: Bool {
        excludedDates.contains(normalizedWeekStart)
    }

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

        return "\(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd))"
    }

    private var badgeColor: Color {
        if isExcluded {
            return .green.opacity(0.6)
        } else if isSelected {
            return .blue
        } else if isCurrentWeek {
            return Color.gray.opacity(0.4)
        } else {
            return Color.gray.opacity(0.2)
        }
    }

    var body: some View {
        Button {
            if !isExcluded {
                toggleSelection()
            }
        } label: {
            HStack(spacing: 12) {
                // Week badge
                ZStack {
                    Text("W\(weekNumber)")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(isSelected ? .white : (isExcluded ? .secondary : .primary))
                        .frame(width: 44, height: 44)
                        .background(badgeColor)
                        .clipShape(Circle())

                    if isExcluded {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .offset(x: 14, y: 14)
                    }
                }

                // Date range
                Text(dateRangeText)
                    .font(.body)
                    .foregroundColor(isExcluded ? .secondary : .primary)

                Spacer()

                if isExcluded {
                    Text("Already added")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
        .disabled(isExcluded)
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

// MARK: - Breakdown Monthly Calendar View

/// Monthly calendar for breakdown (only shown for yearly commitments)
struct BreakdownMonthlyCalendarView: View {
    @Binding var selectedDates: Set<Date>
    let excludedDates: Set<Date>
    let commitment: Commitment

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

    private var displayYear: Int {
        calendar.component(.year, from: commitment.commitmentDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Year header (fixed to commitment year)
            Text(String(displayYear))
                .font(.headline)
                .padding(.vertical, 8)

            Divider()
                .padding(.bottom, 8)

            // Month grid (4x3)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<12, id: \.self) { monthIndex in
                        BreakdownMonthButton(
                            monthIndex: monthIndex,
                            monthName: monthNames[monthIndex],
                            displayYear: displayYear,
                            selectedDates: $selectedDates,
                            excludedDates: excludedDates,
                            calendar: calendar
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Month button for breakdown
struct BreakdownMonthButton: View {
    let monthIndex: Int
    let monthName: String
    let displayYear: Int
    @Binding var selectedDates: Set<Date>
    let excludedDates: Set<Date>
    let calendar: Calendar

    private var monthDate: Date? {
        var components = DateComponents()
        components.year = displayYear
        components.month = monthIndex + 1
        components.day = 1
        return calendar.date(from: components)
    }

    private var isExcluded: Bool {
        guard let date = monthDate else { return false }
        return excludedDates.contains(calendar.startOfDay(for: date))
    }

    private var isSelected: Bool {
        selectedDates.contains { date in
            let dateMonth = calendar.component(.month, from: date)
            let dateYear = calendar.component(.year, from: date)
            return dateMonth == monthIndex + 1 && dateYear == displayYear
        }
    }

    private var isCurrentMonth: Bool {
        let today = Date()
        let currentMonth = calendar.component(.month, from: today)
        let currentYear = calendar.component(.year, from: today)
        return currentMonth == monthIndex + 1 && currentYear == displayYear
    }

    private var backgroundColor: Color {
        if isExcluded {
            return .green.opacity(0.3)
        } else if isSelected {
            return .blue
        } else if isCurrentMonth {
            return Color.gray.opacity(0.3)
        } else {
            return Color(.secondarySystemBackground)
        }
    }

    var body: some View {
        Button {
            if !isExcluded {
                toggleSelection()
            }
        } label: {
            ZStack {
                Text(monthName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : (isExcluded ? .secondary : .primary))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(backgroundColor)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )

                if isExcluded {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.green)
                        .offset(x: 25, y: -15)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isExcluded)
    }

    private func toggleSelection() {
        guard let date = monthDate else { return }

        if let existingDate = selectedDates.first(where: { d in
            let dateMonth = calendar.component(.month, from: d)
            let dateYear = calendar.component(.year, from: d)
            return dateMonth == monthIndex + 1 && dateYear == displayYear
        }) {
            selectedDates.remove(existingDate)
        } else {
            selectedDates.insert(date)
        }
    }
}

// MARK: - Subtask Commit Sheet

/// Sheet for committing a subtask to a lower timeframe
/// Creates a commitment for the subtask at the target timeframe
struct SubtaskCommitSheet: View {
    let subtask: FocusTask
    let parentCommitment: Commitment
    @ObservedObject var viewModel: FocusTabViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedTargetTimeframe: Timeframe
    @State private var selectedDates: Set<Date> = []
    @State private var isSaving = false

    /// Available timeframes for breakdown (all lower than parent's current)
    private var availableTimeframes: [Timeframe] {
        parentCommitment.timeframe.availableBreakdownTimeframes
    }

    init(subtask: FocusTask, parentCommitment: Commitment, viewModel: FocusTabViewModel) {
        self.subtask = subtask
        self.parentCommitment = parentCommitment
        self.viewModel = viewModel
        // Default to first available timeframe
        _selectedTargetTimeframe = State(initialValue: parentCommitment.timeframe.availableBreakdownTimeframes.first ?? .daily)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header info
                VStack(alignment: .leading, spacing: 8) {
                    Text(subtask.title)
                        .font(.headline)

                    HStack {
                        Image(systemName: "arrow.down.forward.circle")
                            .foregroundColor(.blue)
                        Text("Commit subtask to lower timeframe")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

                Divider()

                // Calendar picker with timeframe selector
                SubtaskCommitCalendarPicker(
                    selectedDates: $selectedDates,
                    selectedTimeframe: $selectedTargetTimeframe,
                    availableTimeframes: availableTimeframes,
                    parentCommitment: parentCommitment
                )
                .padding(.top, 8)

                Spacer()
            }
            .navigationTitle("Commit Subtask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        Task {
                            await addSelectedCommitments()
                        }
                    }
                    .disabled(selectedDates.isEmpty || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: selectedTargetTimeframe) { _ in
                // Clear selections when timeframe changes
                selectedDates.removeAll()
            }
        }
    }

    private func addSelectedCommitments() async {
        isSaving = true

        for date in selectedDates.sorted() {
            await viewModel.commitSubtask(subtask, parentCommitment: parentCommitment, toDate: date, targetTimeframe: selectedTargetTimeframe)
        }

        isSaving = false
        dismiss()
    }
}

/// Calendar picker for subtask commit - uses parent commitment's date range
struct SubtaskCommitCalendarPicker: View {
    @Binding var selectedDates: Set<Date>
    @Binding var selectedTimeframe: Timeframe
    let availableTimeframes: [Timeframe]
    let parentCommitment: Commitment

    var body: some View {
        VStack(spacing: 16) {
            // Timeframe picker (only show if multiple options)
            if availableTimeframes.count > 1 {
                Picker("Timeframe", selection: $selectedTimeframe) {
                    ForEach(availableTimeframes, id: \.self) { tf in
                        Text(tf.displayName).tag(tf)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }

            // Calendar view based on selected timeframe
            // Uses parent commitment as the scoping reference
            switch selectedTimeframe {
            case .daily:
                BreakdownDailyCalendarView(
                    selectedDates: $selectedDates,
                    excludedDates: [],  // No existing children for new subtask
                    commitment: parentCommitment
                )
            case .weekly:
                BreakdownWeeklyCalendarView(
                    selectedDates: $selectedDates,
                    excludedDates: [],
                    commitment: parentCommitment
                )
            case .monthly:
                BreakdownMonthlyCalendarView(
                    selectedDates: $selectedDates,
                    excludedDates: [],
                    commitment: parentCommitment
                )
            case .yearly:
                // Should not happen - yearly is never a breakdown target
                EmptyView()
            }
        }
    }
}

#Preview {
    CommitSheet(
        commitment: Commitment(
            userId: UUID(),
            taskId: UUID(),
            timeframe: .yearly,
            section: .focus,
            commitmentDate: Date()
        ),
        task: FocusTask(
            id: UUID(),
            userId: UUID(),
            title: "Learn Spanish",
            type: .task,
            isCompleted: false,
            createdDate: Date(),
            modifiedDate: Date(),
            sortOrder: 0,
            isInLibrary: true
        ),
        viewModel: FocusTabViewModel(authService: AuthService())
    )
}
