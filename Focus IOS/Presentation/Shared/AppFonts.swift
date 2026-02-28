import SwiftUI

// MARK: - App Font Utility

extension Font {

    /// SF System font matching a Dynamic Type text style with weight mapping.
    /// Usage: `.font(.sf(.title2))` or `.font(.sf(.body, weight: .semibold))`
    static func sf(_ style: TextStyle, weight: SFWeight = .regular) -> Font {
        .system(style, weight: weight.systemWeight)
    }

    /// SF System font with explicit point size and weight.
    /// Usage: `.font(.sf(size: 16, weight: .semibold))`
    static func sf(size: CGFloat, weight: SFWeight = .regular) -> Font {
        .system(size: size, weight: weight.systemWeight)
    }

    /// SF System font with explicit size, relative to a text style for Dynamic Type scaling.
    static func sf(size: CGFloat, weight: SFWeight = .regular, relativeTo style: TextStyle) -> Font {
        .system(size: size, weight: weight.systemWeight)
    }

    /// Montserrat custom font — used for date navigator.
    static func montserratHeader(size: CGFloat, weight: MontserratWeight = .regular) -> Font {
        .custom(weight.fontName, size: size)
    }

    /// Montserrat custom font matching a Dynamic Type text style — used for date navigator.
    static func montserratHeader(_ style: TextStyle, weight: MontserratWeight = .regular) -> Font {
        .custom(weight.fontName, size: style.defaultSize, relativeTo: style)
    }

    /// GolosText custom font — used for focus/extra section headers and task titles.
    static func golosText(size: CGFloat, weight: GolosTextWeight = .semiBold) -> Font {
        .custom(weight.fontName, size: size)
    }

    /// GolosText custom font matching a Dynamic Type text style.
    static func golosText(_ style: TextStyle, weight: GolosTextWeight = .semiBold) -> Font {
        .custom(weight.fontName, size: style.defaultSize, relativeTo: style)
    }

    /// Inter custom font with explicit point size.
    /// Usage: `.font(.inter(size: 16, weight: .medium))`
    static func inter(size: CGFloat, weight: InterWeight = .regular) -> Font {
        .custom(weight.fontName, size: size)
    }

    /// Inter custom font matching a Dynamic Type text style.
    /// Usage: `.font(.inter(.body, weight: .semiBold))`
    static func inter(_ style: TextStyle, weight: InterWeight = .regular) -> Font {
        .custom(weight.fontName, size: style.defaultSize, relativeTo: style)
    }
}

// MARK: - SF Weight Mapping

enum SFWeight {
    case thin, extraLight, light, regular, medium, semibold, bold, extraBold, black

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

// MARK: - Montserrat Weight Mapping (custom font for date navigator)

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

// MARK: - GolosText Weight Mapping

// MARK: - Inter Weight Mapping

enum InterWeight {
    case thin, extraLight, light, regular, medium, semiBold, bold, extraBold

    var fontName: String {
        switch self {
        case .thin:       "Inter18pt-Thin"
        case .extraLight: "Inter18pt-ExtraLight"
        case .light:      "Inter18pt-Light"
        case .regular:    "Inter18pt-Regular"
        case .medium:     "Inter18pt-Medium"
        case .semiBold:   "Inter18pt-SemiBold"
        case .bold:       "Inter18pt-Bold"
        case .extraBold:  "Inter18pt-ExtraBold"
        }
    }
}

// MARK: - GolosText Weight Mapping

enum GolosTextWeight {
    case regular, medium, semiBold, bold, extraBold, black

    var fontName: String {
        switch self {
        case .regular:   "GolosText-Regular"
        case .medium:    "GolosText-Medium"
        case .semiBold:  "GolosText-SemiBold"
        case .bold:      "GolosText-Bold"
        case .extraBold: "GolosText-ExtraBold"
        case .black:     "GolosText-Black"
        }
    }
}

