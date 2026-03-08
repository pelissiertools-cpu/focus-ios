//
//  AppStyle.swift
//  Focus IOS
//
//  Centralized style tokens — change once, apply everywhere.
//

import SwiftUI

enum AppStyle {

    // MARK: - Typography

    enum Typography {
        /// Page/screen titles (Home, Inbox, Today, Backlog, Archive, Scheduled, etc.)
        static let pageTitle: Font = .helveticaNeue(size: 26.14)
        static let pageTitleTracking: CGFloat = -0.272

        /// Section headers — collapsible sections in Backlog, CategoryDetail, Scheduled, Archive, etc.
        static let sectionHeader: Font = .roboto(size: 22, weight: .semiBold)

        /// Home screen section labels (PINNED, CATEGORIES) — smaller uppercase style, distinct from sectionHeader
        static let homeSectionLabel: Font = .roboto(size: 14.63, weight: .regular)
        static let homeSectionLabelTracking: CGFloat = 0.686
        static let homeSectionLabelLineSpacing: CGFloat = 17.56 - 14.63

        /// Task / item row titles
        static let itemTitle: Font = .helveticaNeue(.body)

        /// Subtask / sub-item row titles
        static let itemSubtitle: Font = .helveticaNeue(.subheadline)

        /// Empty-state primary text
        static let emptyTitle: Font = .helveticaNeue(.headline, weight: .bold)

        /// Empty-state secondary text
        static let emptySubtitle: Font = .helveticaNeue(.subheadline)

        /// Count badges next to section headers
        static let countBadge: Font = .inter(.caption)

        /// Small collapse / expand chevrons
        static let chevron: Font = .inter(size: 8, weight: .semiBold)

        /// Home card title (Inbox, Today, Scheduled, All, Completed, Someday)
        static let homeCardTitle: Font = .helveticaNeue(size: 15.22, weight: .medium)
        static let homeCardTitleTracking: CGFloat = -0.158

        /// Home card count badge
        static let homeCardCount: Font = .helveticaNeue(size: 11.08, weight: .medium)
        static let homeCardCountTracking: CGFloat = -0.11
        static let homeCardCountLineSpacing: CGFloat = 13.4 - 11.08

        /// Home card icon
        static let homeCardIcon: Font = .helveticaNeue(size: 17.3, weight: .medium)

        /// Home compact card title (Quick lists, Projects, Goals)
        static let homeCardCompactTitle: Font = .helveticaNeue(size: 13, weight: .medium)
        static let homeCardCompactTitleTracking: CGFloat = -0.135

        /// Home compact card count badge
        static let homeCardCompactCount: Font = .helveticaNeue(size: 10, weight: .medium)

        /// Home compact card icon
        static let homeCardCompactIcon: Font = .helveticaNeue(size: 17.3, weight: .medium)

        /// Pinned item row title
        static let pinnedItemTitle: Font = .helveticaNeue(.body, weight: .bold)

        /// Pinned item row icon
        static let pinnedItemIcon: Font = .inter(.body, weight: .medium)

    }

    // MARK: - Opacity

    enum Opacity {
        /// Disabled controls, inactive toggles
        static let disabled: Double = 0.5
        /// Ghost hints, placeholder-like elements
        static let ghost: Double = 0.3
        /// Section divider lines
        static let divider: Double = 0.3
    }
}

// MARK: - View Modifiers

extension View {
    /// Page title style: HelveticaNeue 26.14pt + tracking
    func pageTitleStyle() -> some View {
        self.font(AppStyle.Typography.pageTitle)
            .tracking(AppStyle.Typography.pageTitleTracking)
    }

    /// Home section label style: Roboto 14.63pt + tracking + line spacing
    func homeSectionLabelStyle() -> some View {
        self.font(AppStyle.Typography.homeSectionLabel)
            .tracking(AppStyle.Typography.homeSectionLabelTracking)
            .lineSpacing(AppStyle.Typography.homeSectionLabelLineSpacing)
    }
}
