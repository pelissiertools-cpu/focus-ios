//
//  TimeframePickers.swift
//  Focus IOS
//
//  Created by Claude Code on 2026-02-06.
//

import SwiftUI

/// Unified date navigator that adapts based on selected timeframe
struct DateNavigator: View {
    @Binding var selectedDate: Date
    let timeframe: Timeframe
    let onTap: () -> Void

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday
        return cal
    }

    var body: some View {
        HStack {
            // Left chevron - navigate previous period
            Button {
                navigatePrevious()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            // Center: tappable title/subtitle
            Button(action: onTap) {
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
            .buttonStyle(.plain)

            Spacer()

            // Right chevron - navigate next period
            Button {
                navigateNext()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
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
