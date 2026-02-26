import SwiftUI

extension Color {
    /// App-wide red accent color (#F81E1D)
    static let appRed = Color(red: 0xF8/255, green: 0x1E/255, blue: 0x1D/255)
    /// Priority orange (#FF6F1E)
    static let priorityOrange = Color(red: 0xFF/255, green: 0x6F/255, blue: 0x1E/255)
    /// Priority yellow (#FFD60A)
    static let priorityYellow = Color(red: 0xFF/255, green: 0xD6/255, blue: 0x0A/255)
    /// Priority blue for Low (#4A90D9)
    static let priorityBlue = Color(red: 0x4A/255, green: 0x90/255, blue: 0xD9/255)
    /// Purple for completed checkmarks (#0033FF)
    static let completedPurple = Color(red: 0x00/255.0, green: 0x33/255.0, blue: 0xFF/255.0)
    /// Dark gray for FAB and filter pill backgrounds
    static let darkGray = Color(red: 40/255, green: 45/255, blue: 46/255)
    /// Blue gradient colors for commit pills
    static let commitGradientDark = Color(red: 0.0, green: 0.2, blue: 1.0)
    static let commitGradientLight = Color(red: 0.15, green: 0.35, blue: 1.0)
    /// Near-white background (adapts to dark mode)
    static let lightBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.systemBackground
            : UIColor(red: 0xFC/255.0, green: 0xFC/255.0, blue: 0xFC/255.0, alpha: 1)
    })
    /// Gray background for section-container contrast
    static let sectionedBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.systemBackground
            : UIColor(red: 0xEC/255.0, green: 0xEC/255.0, blue: 0xEE/255.0, alpha: 1)
    })
}
