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
        /// Scrim overlays (add bar backdrop, etc.)
        static let scrim: Double = 0.15
        /// Card shadow color opacity
        static let cardShadow: Double = 0.04
        /// Bottom bar / FAB shadow color opacity
        static let barShadow: Double = 0.06
    }

    // MARK: - Spacing

    enum Spacing {
        /// 2pt — hairline gaps, minor adjustments
        static let micro: CGFloat = 2
        /// 4pt — tight gaps, small bottom margins
        static let tiny: CGFloat = 4
        /// 6pt — minimal row spacing, tight padding
        static let small: CGFloat = 6
        /// 8pt — standard row vertical padding, compact spacing
        static let compact: CGFloat = 8
        /// 10pt — button/icon horizontal padding
        static let medium: CGFloat = 10
        /// 12pt — component spacing, medium padding
        static let comfortable: CGFloat = 12
        /// 14pt — content padding inside cards/sections
        static let content: CGFloat = 14
        /// 16pt — section-level padding
        static let section: CGFloat = 16
        /// 20pt — page-level horizontal padding
        static let page: CGFloat = 20
        /// 24pt — large section separation
        static let expanded: CGFloat = 24
    }

    // MARK: - Layout

    enum Layout {
        /// 8pt — bullet points, small indicators
        static let dotSize: CGFloat = 8
        /// 18pt — small badges, tiny icons
        static let tinyIcon: CGFloat = 18
        /// 20pt — small indicators
        static let smallIcon: CGFloat = 20
        /// 24pt — icon frame inside pill/capsule
        static let pillButton: CGFloat = 24
        /// 30pt — small icon buttons (ellipsis, close pill)
        static let compactButton: CGFloat = 30
        /// 36pt — medium action buttons (save, confirm)
        static let iconButton: CGFloat = 36
        /// 44pt — standard touch target (back, nav buttons)
        static let touchTarget: CGFloat = 44
        /// 52pt — large secondary actions
        static let largeButton: CGFloat = 52
        /// 56pt — floating action button
        static let fab: CGFloat = 56
        /// 28pt — icon badge frame (Today, Inbox, Scheduled, etc.)
        static let iconBadge: CGFloat = 28
        /// 14pt — section divider icon
        static let sectionDividerIcon: CGFloat = 14
        /// 20pt — bottom bar notch radius
        static let notchRadius: CGFloat = 20
        /// 40pt — app logo height
        static let logoHeight: CGFloat = 40
        /// 280pt — top gradient mist height
        static let gradientMistHeight: CGFloat = 280
    }

    // MARK: - Insets

    enum Insets {
        /// Standard list row insets (0, 20, 0, 20)
        static let row = EdgeInsets(top: 0, leading: Spacing.page, bottom: 0, trailing: Spacing.page)
        /// Indented subtask/nested row insets (0, 32, 0, 32)
        static let nestedRow = EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32)
        /// Zero insets
        static let zero = EdgeInsets()
    }
    // MARK: - Corner Radius

    enum CornerRadius {
        /// 7pt — icon badge containers
        static let iconBadge: CGFloat = 7
        /// 10pt — pill backgrounds
        static let pill: CGFloat = 10
        /// 12pt — cards, drawers, sheets
        static let card: CGFloat = 12
        /// 16pt — FAB, project cards (continuous)
        static let fab: CGFloat = 16
        /// 25pt — large auth buttons
        static let button: CGFloat = 25
    }

    // MARK: - Border

    enum Border {
        /// 0.33pt — thin card borders, divider lines
        static let thin: CGFloat = 0.33
        /// 1pt — standard field/button borders
        static let standard: CGFloat = 1
        /// 2pt — focused / selected state borders
        static let focused: CGFloat = 2
    }

    // MARK: - Shadow

    enum Shadow {
        /// Card shadow: subtle downward lift
        static let cardRadius: CGFloat = 4
        static let cardY: CGFloat = 1
        /// Bottom bar shadow: upward lift
        static let barRadius: CGFloat = 4
        static let barY: CGFloat = -2
        /// FAB shadow: floating elevation
        static let fabRadius: CGFloat = 6
        static let fabY: CGFloat = 2
    }

    // MARK: - Animation

    enum Anim {
        /// 0.2s ease — toggle, state changes
        static let toggle: Animation = .easeInOut(duration: 0.2)
        /// 0.3s ease — expand/collapse sections
        static let expand: Animation = .easeInOut(duration: 0.3)
        /// 0.15s ease — quick dismissals
        static let quick: Animation = .easeInOut(duration: 0.15)
        /// Spring — mode/selection switches
        static let modeSwitch: Animation = .spring(response: 0.35, dampingFraction: 0.85)
        /// Spring — button press feedback
        static let buttonTap: Animation = .spring(response: 0.3, dampingFraction: 0.8)
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

    /// Card shadow: black 4% opacity, radius 4, y 1
    func cardShadow() -> some View {
        self.shadow(
            color: .black.opacity(AppStyle.Opacity.cardShadow),
            radius: AppStyle.Shadow.cardRadius,
            x: 0, y: AppStyle.Shadow.cardY
        )
    }

    /// Bottom bar shadow: black 6% opacity, radius 4, y -2
    func barShadow() -> some View {
        self.shadow(
            color: .black.opacity(AppStyle.Opacity.barShadow),
            radius: AppStyle.Shadow.barRadius,
            x: 0, y: AppStyle.Shadow.barY
        )
    }

    /// FAB shadow: black 6% opacity, radius 6, y 2
    func fabShadow() -> some View {
        self.shadow(
            color: .black.opacity(AppStyle.Opacity.barShadow),
            radius: AppStyle.Shadow.fabRadius,
            x: 0, y: AppStyle.Shadow.fabY
        )
    }

    /// Standard card border overlay: cardBorder color, 0.33pt, 12pt radius
    func cardBorderOverlay() -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: AppStyle.CornerRadius.card)
                .stroke(Color.cardBorder, lineWidth: AppStyle.Border.thin)
        )
    }
}
