//
//  CalendarTimelineView.swift
//  Focus IOS
//

import SwiftUI

/// Preference key to track the timeline content origin in global coordinate space
struct TimelineContentOriginPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Apple Calendar-style daily timeline with week day selector and 24-hour scrollable grid
struct CalendarTimelineView: View {
    @ObservedObject var timelineVM: TimelineViewModel
    @ObservedObject var focusVM: FocusTabViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 24-hour scrollable timeline
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // Hour grid background
                        TimelineGridView()
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: TimelineContentOriginPreference.self,
                                        value: geo.frame(in: .global).minY
                                    )
                                }
                            )

                        // Scheduled task blocks
                        ForEach(timelineVM.timedCommitments) { commitment in
                            if let task = focusVM.tasksMap[commitment.taskId] {
                                TimelineTaskBlockView(
                                    commitment: commitment,
                                    task: task,
                                    hourHeight: TimelineGridView.hourHeight,
                                    labelWidth: TimelineGridView.labelWidth,
                                    isBeingDragged: timelineVM.timelineBlockDragId == commitment.id,
                                    onTap: {
                                        focusVM.selectedTaskForDetails = task
                                    },
                                    onMoveChanged: { translationHeight in
                                        timelineVM.handleTimelineBlockMoveChanged(
                                            translationHeight: translationHeight,
                                            commitment: commitment,
                                            task: task
                                        )
                                    },
                                    onMoveEnded: { translationHeight in
                                        timelineVM.handleTimelineBlockMoveEnded(
                                            translationHeight: translationHeight
                                        )
                                    },
                                    onTopResizeChanged: { delta in
                                        timelineVM.handleTimelineBlockTopResizeChanged(
                                            commitmentId: commitment.id,
                                            dragDelta: delta
                                        )
                                    },
                                    onTopResizeEnded: { delta in
                                        timelineVM.handleTimelineBlockTopResizeEnded(
                                            commitmentId: commitment.id,
                                            dragDelta: delta
                                        )
                                    },
                                    onBottomResizeChanged: { delta in
                                        timelineVM.handleTimelineBlockBottomResizeChanged(
                                            commitmentId: commitment.id,
                                            dragDelta: delta
                                        )
                                    },
                                    onBottomResizeEnded: { delta in
                                        timelineVM.handleTimelineBlockBottomResizeEnded(
                                            commitmentId: commitment.id,
                                            dragDelta: delta
                                        )
                                    }
                                )
                            }
                        }

                        // Drop preview during drag (inside ScrollView so position = time)
                        if timelineVM.isTimelineDropTargeted {
                            TimelineDropPreviewView(
                                yPosition: timelineVM.timelineDropPreviewY,
                                hourHeight: TimelineGridView.hourHeight,
                                labelWidth: TimelineGridView.labelWidth,
                                taskTitle: timelineVM.scheduleDragInfo?.taskTitle ?? ""
                            )
                        }

                        // Current time indicator (only for today)
                        if Calendar.current.isDateInToday(focusVM.selectedDate) {
                            CurrentTimeIndicatorView(
                                hourHeight: TimelineGridView.hourHeight,
                                labelWidth: TimelineGridView.labelWidth
                            )
                        }
                    }
                    .padding(.top, 8)
                }
                .onPreferenceChange(TimelineContentOriginPreference.self) { origin in
                    timelineVM.timelineContentOriginY = origin
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, newOffset in
                    timelineVM.timelineScrollOffset = newOffset
                }
                .onAppear {
                    scrollToCurrentTime(proxy: proxy)
                }
                .onChange(of: focusVM.selectedDate) {
                    if Calendar.current.isDateInToday(focusVM.selectedDate) {
                        scrollToCurrentTime(proxy: proxy)
                    } else {
                        // Scroll to 8 AM for non-today dates
                        withAnimation {
                            proxy.scrollTo(8, anchor: .top)
                        }
                    }
                }
            }
        }
    }

    private func scrollToCurrentTime(proxy: ScrollViewProxy) {
        let hour = Calendar.current.component(.hour, from: Date())
        // Scroll to ~2 hours before current time so it's visible but not at the very top
        let scrollTarget = max(0, hour - 2)
        withAnimation {
            proxy.scrollTo(scrollTarget, anchor: .top)
        }
    }
}
