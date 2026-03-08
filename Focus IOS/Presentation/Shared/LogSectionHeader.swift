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
            HStack(spacing: AppStyle.Spacing.comfortable) {
                HStack(alignment: .lastTextBaseline, spacing: AppStyle.Spacing.compact) {
                    Text(title)
                        .font(AppStyle.Typography.sectionHeader)

                    HStack(spacing: AppStyle.Spacing.tiny) {
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
                    .padding(.horizontal, AppStyle.Spacing.compact)
                    .padding(.vertical, AppStyle.Spacing.tiny)
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
            .padding(.vertical, AppStyle.Spacing.small)
            .padding(.horizontal, AppStyle.Spacing.comfortable)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.horizontal, AppStyle.Spacing.section)
    }
}
