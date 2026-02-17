import SwiftUI

// MARK: - Outfit Font Utility

extension Font {

    /// Outfit font matching a system Dynamic Type text style.
    /// Usage: `.font(.outfit(.title2))` or `.font(.outfit(.body, weight: .semibold))`
    static func outfit(_ style: TextStyle, weight: OutfitWeight = .regular) -> Font {
        .custom(weight.fontName, size: style.outfitSize, relativeTo: style)
    }

    /// Outfit font with explicit point size and weight.
    /// Usage: `.font(.outfit(size: 16, weight: .semibold))`
    static func outfit(size: CGFloat, weight: OutfitWeight = .regular) -> Font {
        .custom(weight.fontName, size: size)
    }

    /// Outfit font with explicit size, relative to a text style for Dynamic Type scaling.
    static func outfit(size: CGFloat, weight: OutfitWeight = .regular, relativeTo style: TextStyle) -> Font {
        .custom(weight.fontName, size: size, relativeTo: style)
    }
}

// MARK: - Outfit Weight

enum OutfitWeight {
    case thin, extraLight, light, regular, medium, semibold, bold, extraBold, black

    var fontName: String {
        switch self {
        case .thin:       "Outfit-Thin"
        case .extraLight: "Outfit-ExtraLight"
        case .light:      "Outfit-Light"
        case .regular:    "Outfit-Regular"
        case .medium:     "Outfit-Medium"
        case .semibold:   "Outfit-SemiBold"
        case .bold:       "Outfit-Bold"
        case .extraBold:  "Outfit-ExtraBold"
        case .black:      "Outfit-Black"
        }
    }
}

// MARK: - TextStyle Size Mapping

private extension Font.TextStyle {
    /// Default point sizes matching Apple's Dynamic Type base sizes (Large content size).
    var outfitSize: CGFloat {
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
