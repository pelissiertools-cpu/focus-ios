//
//  TimelineDropPreviewView.swift
//  Focus IOS
//

import SwiftUI

/// Dashed-border preview block shown on the timeline grid during drag-to-schedule.
/// Lives inside the ScrollView content — its position on the grid IS its time.
struct TimelineDropPreviewView: View {
    let yPosition: CGFloat
    let hourHeight: CGFloat
    let labelWidth: CGFloat
    let taskTitle: String

    private var blockHeight: CGFloat {
        30.0 * (hourHeight / 60.0)  // 30-minute default duration
    }

    /// Snap Y to 15-minute grid
    private var snappedY: CGFloat {
        let quarterHourHeight = hourHeight / 4.0
        return (yPosition / quarterHourHeight).rounded() * quarterHourHeight
    }

    private var timeLabel: String {
        let totalMinutes = (snappedY / hourHeight) * 60
        let snappedMinutes = (Int(totalMinutes) / 15) * 15
        let hour = snappedMinutes / 60
        let minute = snappedMinutes % 60

        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)

        let endMinutes = snappedMinutes + 30
        let endHour = endMinutes / 60
        let endMinute = endMinutes % 60
        let endPeriod = endHour < 12 ? "AM" : "PM"
        let endDisplayHour = endHour == 0 ? 12 : (endHour > 12 ? endHour - 12 : endHour)

        return String(format: "%d:%02d %@ - %d:%02d %@",
                       displayHour, minute, period,
                       endDisplayHour, endMinute, endPeriod)
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: labelWidth + 8)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.appRed.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.appRed, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                )
                .overlay(
                    VStack(alignment: .leading, spacing: 2) {
                        Text(taskTitle)
                            .font(.inter(.caption, weight: .medium))
                            .foregroundColor(.appRed)
                            .lineLimit(1)
                        Text(timeLabel)
                            .font(.inter(.caption2))
                            .foregroundColor(.appRed.opacity(0.6))
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4),
                    alignment: .topLeading
                )
                .frame(height: blockHeight)
                .padding(.trailing, 16)
        }
        .offset(y: snappedY)
    }
}
