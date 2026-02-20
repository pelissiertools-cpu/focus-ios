import SwiftUI

extension Color {
    /// App-wide red accent color (#F81E1D)
    static let appRed = Color(red: 0xF8/255, green: 0x1E/255, blue: 0x1D/255)
    /// Purple for completed checkmarks (#6110F8)
    static let completedPurple = Color(red: 0x61/255.0, green: 0x10/255.0, blue: 0xF8/255.0)
    /// Dark gray for FAB and filter pill backgrounds
    static let darkGray = Color(red: 40/255, green: 45/255, blue: 46/255)
    /// Blue gradient colors for commit pills
    static let commitGradientDark = Color(red: 0.0, green: 0.2, blue: 1.0)
    static let commitGradientLight = Color(red: 0.15, green: 0.35, blue: 1.0)
    /// Near-white background
    static let lightBackground = Color(red: 0xFC/255.0, green: 0xFC/255.0, blue: 0xFC/255.0)
}
