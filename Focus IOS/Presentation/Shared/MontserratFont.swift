import SwiftUI

// MARK: - Montserrat Font Utility

extension Font {

    /// Montserrat font matching a system Dynamic Type text style.
    /// Usage: `.font(.montserrat(.title2))` or `.font(.montserrat(.body, weight: .semibold))`
    static func montserrat(_ style: TextStyle, weight: MontserratWeight = .regular) -> Font {
        .custom(weight.fontName, size: style.montserratSize, relativeTo: style)
    }

    /// Montserrat font with explicit point size and weight.
    /// Usage: `.font(.montserrat(size: 16, weight: .semibold))`
    static func montserrat(size: CGFloat, weight: MontserratWeight = .regular) -> Font {
        .custom(weight.fontName, size: size)
    }

    /// Montserrat font with explicit size, relative to a text style for Dynamic Type scaling.
    static func montserrat(size: CGFloat, weight: MontserratWeight = .regular, relativeTo style: TextStyle) -> Font {
        .custom(weight.fontName, size: size, relativeTo: style)
    }
}

// MARK: - Montserrat Weight

enum MontserratWeight {
    case thin, extraLight, light, regular, medium, semibold, bold, extraBold, black

    var fontName: String {
        switch self {
        case .thin:       "Montserrat-Thin"
        case .extraLight: "Montserrat-ExtraLight"
        case .light:      "Montserrat-Light"
        case .regular:    "Montserrat-Regular"
        case .medium:     "Montserrat-Medium"
        case .semibold:   "Montserrat-SemiBold"
        case .bold:       "Montserrat-Bold"
        case .extraBold:  "Montserrat-ExtraBold"
        case .black:      "Montserrat-Black"
        }
    }
}

// MARK: - TextStyle Size Mapping

private extension Font.TextStyle {
    /// Default point sizes matching Apple's Dynamic Type base sizes (Large content size).
    var montserratSize: CGFloat {
        switch self {
        case .largeTitle:  34
        case .title:       28
        case .title2:      22
        case .title3:      20
        case .headline:    17
        case .body:        17
        case .callout:     16
        case .subheadline: 15
        case .footnote:    13
        case .caption:     12
        case .caption2:    11
        @unknown default:  17
        }
    }
}
