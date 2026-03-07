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
            ? UIColor.systemBackground
            : UIColor(red: 0xF1/255.0, green: 0xF1/255.0, blue: 0xF1/255.0, alpha: 1)
    })
    /// Pill background for section headers — visible in light, subtle in dark
    static let pillBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.1)
            : UIColor.white.withAlphaComponent(0.6)
    })
    /// Subtle glass tint — reduces white glare in light mode, invisible in dark
    static let glassTint = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.5, alpha: 0.01)
            : UIColor(white: 0.5, alpha: 0.12)
    })
}
