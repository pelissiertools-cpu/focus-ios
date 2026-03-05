//
//  CurrentTimeIndicatorView.swift
//  Focus IOS
//

import SwiftUI
import Combine

/// Red horizontal line indicating the current time on the timeline
struct CurrentTimeIndicatorView: View {
    let hourHeight: CGFloat
    let labelWidth: CGFloat

    /// Updates every minute
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var yOffset: CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: currentTime)
        let minute = calendar.component(.minute, from: currentTime)
        return CGFloat(hour) * hourHeight + CGFloat(minute) * (hourHeight / 60)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Red dot aligned with the label area
            Spacer()
                .frame(width: labelWidth - 4)

            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)

            // Red line
            Rectangle()
                .fill(Color.red)
                .frame(height: 1.5)
        }
        .offset(y: yOffset - 5) // Center the dot vertically on the line
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
}
