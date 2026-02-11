//
//  TimelineTaskBlockView.swift
//  Focus IOS
//

import SwiftUI

/// Renders a scheduled task as a colored block on the calendar timeline
/// with Apple Calendar-style interactions: tap to edit, long-press drag to move, resize handles.
struct TimelineTaskBlockView: View {
    let commitment: Commitment
    let task: FocusTask
    let hourHeight: CGFloat
    let labelWidth: CGFloat
    let isBeingDragged: Bool

    // Callbacks
    var onTap: () -> Void = {}
    var onMoveChanged: (CGPoint) -> Void = { _ in }
    var onMoveEnded: (CGPoint) -> Void = { _ in }
    var onTopResizeChanged: (CGFloat) -> Void = { _ in }
    var onTopResizeEnded: (CGFloat) -> Void = { _ in }
    var onBottomResizeChanged: (CGFloat) -> Void = { _ in }
    var onBottomResizeEnded: (CGFloat) -> Void = { _ in }

    @State private var isLongPressed = false

    private var yOffset: CGFloat {
        guard let time = commitment.scheduledTime else { return 0 }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)
        return CGFloat(hour) * hourHeight + CGFloat(minute) * (hourHeight / 60.0)
    }

    private var blockHeight: CGFloat {
        let minutes = CGFloat(commitment.durationMinutes ?? 30)
        return max(minutes * (hourHeight / 60.0), hourHeight / 4) // min 15-min height
    }

    private let handleTapSize: CGFloat = 24 // generous tap target
    private let dotSize: CGFloat = 8 // visible dot diameter

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: labelWidth + 8)

            // Main block body with overlay-based resize handles
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.blue, lineWidth: 1.5)
                )
                .overlay(
                    Text(task.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4),
                    alignment: .topLeading
                )
                .frame(height: blockHeight)
                // Top-right resize handle (Apple Calendar: white dot with blue stroke, on the border)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(Color.blue, lineWidth: 1.5))
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: dotSize / 2, y: -dotSize / 2)
                        .frame(width: handleTapSize, height: handleTapSize)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { value in
                                    onTopResizeChanged(value.translation.height)
                                }
                                .onEnded { value in
                                    onTopResizeEnded(value.translation.height)
                                }
                        )
                }
                // Bottom-left resize handle (Apple Calendar: white dot with blue stroke, on the border)
                .overlay(alignment: .bottomLeading) {
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(Color.blue, lineWidth: 1.5))
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: -dotSize / 2, y: dotSize / 2)
                        .frame(width: handleTapSize, height: handleTapSize)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { value in
                                    onBottomResizeChanged(value.translation.height)
                                }
                                .onEnded { value in
                                    onBottomResizeEnded(value.translation.height)
                                }
                        )
                }
            .padding(.trailing, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { value in
                        switch value {
                        case .first(true):
                            if !isLongPressed {
                                isLongPressed = true
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                        case .second(true, let drag):
                            if let drag = drag {
                                onMoveChanged(drag.location)
                            }
                        default:
                            break
                        }
                    }
                    .onEnded { value in
                        switch value {
                        case .second(true, let drag):
                            if let drag = drag {
                                onMoveEnded(drag.location)
                            }
                        default:
                            break
                        }
                        isLongPressed = false
                    }
            )
            .scaleEffect(isLongPressed || isBeingDragged ? 1.03 : 1.0)
            .opacity(isBeingDragged ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isLongPressed)
            .animation(.easeInOut(duration: 0.15), value: isBeingDragged)
        }
        .offset(y: yOffset)
    }
}
