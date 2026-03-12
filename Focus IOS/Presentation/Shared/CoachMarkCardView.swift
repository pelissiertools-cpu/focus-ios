//
//  CoachMarkCardView.swift
//  Focus IOS
//

import SwiftUI

struct CoachMarkCardView: View {
    let section: CoachMarkSection
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.comfortable) {
            HStack(spacing: AppStyle.Spacing.compact) {
                Image(systemName: section.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text(section.title)
                    .font(.inter(.headline, weight: .bold))
                    .foregroundColor(.white)
            }

            Text(section.description)
                .font(.inter(.subheadline))
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onDismiss) {
                Text("Got it")
                    .font(.inter(.subheadline, weight: .semiBold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppStyle.Spacing.compact)
                    .background(Color.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.CornerRadius.pill))
            }
            .buttonStyle(.plain)
        }
        .padding(AppStyle.Spacing.section)
        .background(Color.charcoal, in: RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card))
        .padding(.horizontal, AppStyle.Spacing.page)
    }
}
