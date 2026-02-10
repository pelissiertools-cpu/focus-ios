//
//  TimeframePickers.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-06.
//

import SwiftUI

/// Unified date navigator that adapts based on selected timeframe
struct DateNavigator<LeadingContent: View>: View {
    @Binding var selectedDate: Date
    let timeframe: Timeframe
    let compact: Bool
    let onTap: () -> Void
    let leadingContent: LeadingContent

    init(
        selectedDate: Binding<Date>,
        timeframe: Timeframe,
        compact: Bool = false,
        onTap: @escaping () -> Void,
        @ViewBuilder leadingContent: () -> LeadingContent
    ) {
        self._selectedDate = selectedDate
        self.timeframe = timeframe
        self.compact = compact
        self.onTap = onTap
        self.leadingContent = leadingContent()
    }

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        return cal
    }

    var body: some View {
        HStack {
            // Optional leading content (e.g. view mode toggle)
            leadingContent

            Spacer(minLength: 0)

            if !compact {
                // Left chevron - navigate previous period
                Button {
                    navigatePrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }

            // Center: tappable title/subtitle
            Button(action: onTap) {
                if compact {
                    Text(compactTitleText)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                } else {
                    VStack(spacing: 4) {
                        Text(titleText)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        if let subtitle = subtitleText {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(16)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            if !compact {
                // Right chevron - navigate next period
                Button {
                    navigateNext()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Navigation

    private func navigatePrevious() {
        let component: Calendar.Component
        switch timeframe {
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        case .yearly: component = .year
        }
        selectedDate = calendar.date(byAdding: component, value: -1, to: selectedDate) ?? selectedDate
    }

    private func navigateNext() {
        let component: Calendar.Component
        switch timeframe {
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        case .yearly: component = .year
        }
        selectedDate = calendar.date(byAdding: component, value: 1, to: selectedDate) ?? selectedDate
    }

    // MARK: - Compact Title (Schedule mode)

    /// "Tue Feb 10" — abbreviated single-line format
    private var compactTitleText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: selectedDate)
    }

    // MARK: - Title Text

    private var titleText: String {
        switch timeframe {
        case .daily:
            // "Sunday"
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: selectedDate)

        case .weekly:
            // "Week 6"
            let weekOfYear = calendar.component(.weekOfYear, from: selectedDate)
            return "Week \(weekOfYear)"

        case .monthly:
            // "February 2026"
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: selectedDate)

        case .yearly:
            // "2026"
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy"
            return formatter.string(from: selectedDate)
        }
    }

    // MARK: - Subtitle Text

    private var subtitleText: String? {
        switch timeframe {
        case .daily:
            // "Feb 8th, 2026"
            return formattedDateWithOrdinal(selectedDate)

        case .weekly:
            // "Feb 2 - Feb 8, 2026"
            return weekRangeText

        case .monthly, .yearly:
            return nil
        }
    }

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

// Convenience init when no leading content is needed
extension DateNavigator where LeadingContent == EmptyView {
    init(
        selectedDate: Binding<Date>,
        timeframe: Timeframe,
        compact: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.init(selectedDate: selectedDate, timeframe: timeframe, compact: compact, onTap: onTap) {
            EmptyView()
        }
    }
}
