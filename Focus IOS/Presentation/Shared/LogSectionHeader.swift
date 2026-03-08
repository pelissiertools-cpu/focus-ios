//
//  LogSectionHeader.swift
//  Focus IOS
//

import SwiftUI

struct LogSectionHeader: View {
    let title: String
    let count: Int
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(title)
                        .font(AppStyle.Typography.sectionHeader)

                    HStack(spacing: 4) {
                        if count > 0 {
                            Text("\(count)")
                                .font(AppStyle.Typography.countBadge)
                                .foregroundColor(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(AppStyle.Typography.chevron)
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .clipShape(Capsule())
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - 1 }
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            }
            .accessibilityLabel("\(title), \(count) items")
            .accessibilityHint(isCollapsed ? "Double-tap to expand" : "Double-tap to collapse")
            .padding(.vertical, 6)
            .padding(.horizontal, 12)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
    }
}
