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
    @ObservedObject var viewModel: FocusTabViewModel

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
                        ForEach(viewModel.timedCommitments) { commitment in
                            if let task = viewModel.tasksMap[commitment.taskId] {
                                TimelineTaskBlockView(
                                    commitment: commitment,
                                    task: task,
                                    hourHeight: TimelineGridView.hourHeight,
                                    labelWidth: TimelineGridView.labelWidth,
                                    isBeingDragged: viewModel.timelineBlockDragId == commitment.id,
                                    onTap: {
                                        viewModel.selectedTaskForDetails = task
                                    },
                                    onMoveChanged: { translationHeight in
                                        viewModel.handleTimelineBlockMoveChanged(
                                            translationHeight: translationHeight,
                                            commitment: commitment,
                                            task: task
                                        )
                                    },
                                    onMoveEnded: { translationHeight in
                                        viewModel.handleTimelineBlockMoveEnded(
                                            translationHeight: translationHeight
                                        )
                                    },
                                    onTopResizeChanged: { delta in
                                        viewModel.handleTimelineBlockTopResizeChanged(
                                            commitmentId: commitment.id,
                                            dragDelta: delta
                                        )
                                    },
                                    onTopResizeEnded: { delta in
                                        viewModel.handleTimelineBlockTopResizeEnded(
                                            commitmentId: commitment.id,
                                            dragDelta: delta
                                        )
                                    },
                                    onBottomResizeChanged: { delta in
                                        viewModel.handleTimelineBlockBottomResizeChanged(
                                            commitmentId: commitment.id,
                                            dragDelta: delta
                                        )
                                    },
                                    onBottomResizeEnded: { delta in
                                        viewModel.handleTimelineBlockBottomResizeEnded(
                                            commitmentId: commitment.id,
                                            dragDelta: delta
                                        )
                                    }
                                )
                            }
                        }

                        // Drop preview during drag (inside ScrollView so position = time)
                        if viewModel.isTimelineDropTargeted {
                            TimelineDropPreviewView(
                                yPosition: viewModel.timelineDropPreviewY,
                                hourHeight: TimelineGridView.hourHeight,
                                labelWidth: TimelineGridView.labelWidth,
                                taskTitle: viewModel.scheduleDragInfo?.taskTitle ?? ""
                            )
                        }

                        // Current time indicator (only for today)
                        if Calendar.current.isDateInToday(viewModel.selectedDate) {
                            CurrentTimeIndicatorView(
                                hourHeight: TimelineGridView.hourHeight,
                                labelWidth: TimelineGridView.labelWidth
                            )
                        }
                    }
                    .padding(.top, 8)
                }
                .onPreferenceChange(TimelineContentOriginPreference.self) { origin in
                    viewModel.timelineContentOriginY = origin
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, newOffset in
                    viewModel.timelineScrollOffset = newOffset
                }
                .onAppear {
                    scrollToCurrentTime(proxy: proxy)
                }
                .onChange(of: viewModel.selectedDate) {
                    if Calendar.current.isDateInToday(viewModel.selectedDate) {
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
