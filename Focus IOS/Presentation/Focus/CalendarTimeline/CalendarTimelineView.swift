//
//  CalendarTimelineView.swift
//  Focus IOS
//

import SwiftUI

/// Apple Calendar-style daily timeline with week day selector and 24-hour scrollable grid
struct CalendarTimelineView: View {
    @ObservedObject var viewModel: FocusTabViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Week day selector strip
            WeekDaySelectorView(selectedDate: $viewModel.selectedDate)

            Divider()

            // 24-hour scrollable timeline
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // Hour grid background
                        TimelineGridView()

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
