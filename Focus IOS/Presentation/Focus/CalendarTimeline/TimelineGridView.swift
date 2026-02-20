//
//  TimelineGridView.swift
//  Focus IOS
//

import SwiftUI

/// 24-hour grid with hour labels and divider lines (1440pt total height, 60pt per hour)
struct TimelineGridView: View {
    static let hourHeight: CGFloat = 60
    static let totalHeight: CGFloat = hourHeight * 24

    /// Left margin width for hour labels
    static let labelWidth: CGFloat = 56

    private let hours = Array(0..<24)

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Hour rows
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 0) {
                        // Hour label
                        Text(hourLabel(for: hour))
                            .font(.sf(.caption))
                            .foregroundColor(.secondary)
                            .frame(width: Self.labelWidth, alignment: .trailing)
                            .padding(.trailing, 8)
                            .offset(y: -7) // Center label on the divider line

                        // Divider line
                        VStack(spacing: 0) {
                            Divider()
                            Spacer()
                        }
                    }
                    .frame(height: Self.hourHeight)
                    .id(hour) // For ScrollViewReader
                }
            }
        }
        .frame(height: Self.totalHeight)
    }

    private func hourLabel(for hour: Int) -> String {
        if hour == 0 { return "" }
        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour == 12 ? 12 : hour % 12
        return "\(displayHour) \(period)"
    }
}
