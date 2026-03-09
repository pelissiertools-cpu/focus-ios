import SwiftUI

extension Color {
    /// App-wide red accent color (#F81E1D)
    static let appRed = Color(red: 0xF8/255.0, green: 0x1E/255.0, blue: 0x1D/255.0)
    /// Priority high dot color (#E85757)
    static let priorityRed = Color(red: 0xE8/255.0, green: 0x57/255.0, blue: 0x57/255.0)
    /// Priority orange (#F2841E)
    static let priorityOrange = Color(red: 0xF2/255.0, green: 0x84/255.0, blue: 0x1E/255.0)
    /// Priority blue for Low (#729FFF)
    static let priorityBlue = Color(red: 0x72/255.0, green: 0x9F/255.0, blue: 0xFF/255.0)
    /// Blue for Focus section (#2E59F4)
    static let focusBlue = Color(red: 0x2E/255.0, green: 0x59/255.0, blue: 0xF4/255.0)
    /// Dark gray for small plus buttons and filter pill backgrounds — charcoal in dark mode
    static let darkGray = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x2C/255.0, green: 0x2C/255.0, blue: 0x2E/255.0, alpha: 1)
            : UIColor(red: 0xC7/255.0, green: 0xC6/255.0, blue: 0xC6/255.0, alpha: 1)
    })
    /// Charcoal for FAB background
    static let charcoal = Color(red: 0x2C/255.0, green: 0x2C/255.0, blue: 0x2E/255.0)
    /// App-wide page background — single source of truth for all screens (#ECECEE light, systemBackground dark)
    static let appBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x18/255.0, green: 0x17/255.0, blue: 0x16/255.0, alpha: 1)
            : UIColor(red: 0xFC/255.0, green: 0xFC/255.0, blue: 0xFC/255.0, alpha: 1)
    })
    /// Pill background for section headers — visible in light, subtle in dark
    static let pillBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.1)
            : UIColor.white.withAlphaComponent(0.6)
    })
    /// Card border color (#EBEBEB light, subtle white in dark)
    static let cardBorder = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor(red: 0xD8/255.0, green: 0xD8/255.0, blue: 0xD8/255.0, alpha: 1)
    })
    /// Primary text color (#32312F light, primary dark)
    static let appText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.label
            : UIColor(red: 0x32/255.0, green: 0x31/255.0, blue: 0x2F/255.0, alpha: 1)
    })
    /// Card / bottom bar surface — white in light, elevated dark in dark
    static let cardBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x22/255.0, green: 0x21/255.0, blue: 0x20/255.0, alpha: 1)
            : UIColor.white
    })
    /// Category pill background — #F5F4F4 light, #32302F dark
    static let categoryBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x32/255.0, green: 0x30/255.0, blue: 0x2F/255.0, alpha: 1)
            : UIColor(red: 0xF5/255.0, green: 0xF4/255.0, blue: 0xF4/255.0, alpha: 1)
    })
    /// Icon badge neutral background — #F5F4F4 light, subtle in dark
    static let iconBadgeBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.tertiarySystemBackground
            : UIColor(red: 0xF5/255.0, green: 0xF4/255.0, blue: 0xF4/255.0, alpha: 1)
    })
    /// Subtle glass tint — reduces white glare in light mode, invisible in dark
    static let glassTint = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.5, alpha: 0.01)
            : UIColor(white: 0.5, alpha: 0.12)
    })

    // MARK: - Icon Badge Colors

    /// Today badge background — #CDD6F8 light, focusBlue@20% dark
    static let todayBadge = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x2E/255.0, green: 0x59/255.0, blue: 0xF4/255.0, alpha: 0.2)
            : UIColor(red: 0xCD/255.0, green: 0xD6/255.0, blue: 0xF8/255.0, alpha: 1)
    })
    /// Inbox badge background — #EBF6EC light, green@20% dark
    static let inboxBadge = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x02/255.0, green: 0x7B/255.0, blue: 0x3A/255.0, alpha: 0.2)
            : UIColor(red: 0xEB/255.0, green: 0xF6/255.0, blue: 0xEC/255.0, alpha: 1)
    })
    /// Scheduled badge background — #F6EBEB light, appRed@20% dark
    static let scheduledBadge = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xF8/255.0, green: 0x1E/255.0, blue: 0x1D/255.0, alpha: 0.2)
            : UIColor(red: 0xF6/255.0, green: 0xEB/255.0, blue: 0xEB/255.0, alpha: 1)
    })
    /// Section divider badge background — #F3E9E1 light, orange@20% dark
    static let dividerBadge = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xFF/255.0, green: 0x8D/255.0, blue: 0x00/255.0, alpha: 0.2)
            : UIColor(red: 0xF3/255.0, green: 0xE9/255.0, blue: 0xE1/255.0, alpha: 1)
    })

    // MARK: - Named Foreground Colors

    /// Inbox green (#027B3A)
    static let inboxGreen = Color(red: 0x02/255.0, green: 0x7B/255.0, blue: 0x3A/255.0)
    /// Accent orange (#FF8D00)
    static let accentOrange = Color(red: 0xFF/255.0, green: 0x8D/255.0, blue: 0x00/255.0)
}
