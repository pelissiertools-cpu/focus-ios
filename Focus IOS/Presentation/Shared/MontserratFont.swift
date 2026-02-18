import SwiftUI

// MARK: - App Font Utility

extension Font {

    /// System font matching a Dynamic Type text style with weight mapping.
    /// Usage: `.font(.montserrat(.title2))` or `.font(.montserrat(.body, weight: .semibold))`
    static func montserrat(_ style: TextStyle, weight: MontserratWeight = .regular) -> Font {
        .system(style, weight: weight.systemWeight)
    }

    /// System font with explicit point size and weight.
    /// Usage: `.font(.montserrat(size: 16, weight: .semibold))`
    static func montserrat(size: CGFloat, weight: MontserratWeight = .regular) -> Font {
        .system(size: size, weight: weight.systemWeight)
    }

    /// System font with explicit size, relative to a text style for Dynamic Type scaling.
    static func montserrat(size: CGFloat, weight: MontserratWeight = .regular, relativeTo style: TextStyle) -> Font {
        .system(size: size, weight: weight.systemWeight)
    }

    /// Montserrat custom font — used for section headers and date navigator.
    static func montserratHeader(size: CGFloat, weight: MontserratWeight = .regular) -> Font {
        .custom(weight.fontName, size: size)
    }

    /// Montserrat custom font matching a Dynamic Type text style — used for date navigator.
    static func montserratHeader(_ style: TextStyle, weight: MontserratWeight = .regular) -> Font {
        .custom(weight.fontName, size: style.defaultSize, relativeTo: style)
    }
}

// MARK: - Weight Mapping

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

extension Font.TextStyle {
    var defaultSize: CGFloat {
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

// MARK: - System Weight Mapping

extension MontserratWeight {
    var systemWeight: Font.Weight {
        switch self {
        case .thin:       .thin
        case .extraLight: .ultraLight
        case .light:      .light
        case .regular:    .regular
        case .medium:     .medium
        case .semibold:   .semibold
        case .bold:       .bold
        case .extraBold:  .heavy
        case .black:      .black
        }
    }
}
