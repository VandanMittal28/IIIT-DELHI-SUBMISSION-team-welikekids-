import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Single source of truth for the Luma-style visual language described in DESIGN_NOTES.md.
// No screen should hard-code a colour, font size, radius, shadow or margin: everything comes
// from here so the whole app moves together when a token changes.

// MARK: - Palette

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum SQColor {
    // Brand. Carried over from the original app so Sidequest keeps its own identity.
    static let ink = Color(hex: 0x17211A)
    static let lime = Color(hex: 0xE8FF63)

    // Light values, with a dark-mode counterpart supplied for every one of them.
    static let background = adaptive(light: 0xF2F2F6, dark: 0x0E0F10)
    static let plainBackground = adaptive(light: 0xFFFFFF, dark: 0x0E0F10)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let surfaceAlt = adaptive(light: 0xEFEFF2, dark: 0x2A2A2D)

    static let textPrimary = adaptive(light: 0x0B0B0C, dark: 0xF5F5F7)
    static let textSecondary = adaptive(light: 0x8A8A8E, dark: 0x9A9A9F)
    static let textTertiary = adaptive(light: 0xB0B0B5, dark: 0x76767B)
    static let chevron = adaptive(light: 0xC4C4C8, dark: 0x5E5E63)

    static let separator = adaptive(light: 0xE5E5EA, dark: 0x303033)
    static let hairline = adaptive(light: 0xE5E5EA, dark: 0x3A3A3D)

    /// Brand accent for text and glyphs. Raw lime is near-invisible on white, so light mode
    /// uses a deepened olive of the same hue and dark mode uses the lime itself.
    static let accent = adaptive(light: 0x6F8415, dark: 0xE8FF63)

    /// Primary button fill and its label. Ink-on-lime inverts in dark mode, where an ink fill
    /// would disappear into the near-black background.
    static let primaryFill = adaptive(light: 0x17211A, dark: 0xE8FF63)
    static let onPrimary = adaptive(light: 0xE8FF63, dark: 0x17211A)

    /// Fixed near-black for labels on a white fill inside a cover-tinted page, where the
    /// adaptive `textPrimary` would flip to white in dark mode and vanish.
    static let onLight = Color(hex: 0x0B0B0C)

    static let destructive = Color(hex: 0xFF3B30)
    static let destructiveWash = adaptive(light: 0xFFE8EA, dark: 0x3A1D1F)
    static let positive = Color(hex: 0x34C759)
    static let warning = Color(hex: 0xFF9500)

    // Categorical hues for settings tiles and category chips (screenshots 01 and 03).
    static let hueRed = Color(hex: 0xFF3B30)
    static let hueOrange = Color(hex: 0xFF8A33)
    static let hueYellow = Color(hex: 0xFFC800)
    static let hueGreen = Color(hex: 0x34C759)
    static let hueBlue = Color(hex: 0x1E8CFF)
    static let hueIndigo = Color(hex: 0x5E5CE6)
    static let hueViolet = Color(hex: 0x8B5CF6)
    static let huePink = Color(hex: 0xFF2D78)
    static let hueBrown = Color(hex: 0xA2785A)

    /// Rotates a stable colour out of the categorical palette for an arbitrary string, so the
    /// same category always gets the same hue without the backend having to supply one.
    static func categorical(for key: String) -> Color {
        let palette = [hueViolet, hueBlue, hueOrange, hueYellow, hueBrown, huePink, hueGreen, hueIndigo, hueRed]
        var hash: UInt64 = 5381
        for byte in key.lowercased().utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return palette[Int(hash % UInt64(palette.count))]
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #else
        return Color(hex: light)
        #endif
    }
}

// MARK: - Typography

enum SQFont {
    /// Screen titles and the wordmark — "Discover" in screenshot 03.
    static let screenTitle = Font.system(size: 30, weight: .bold)
    /// The large event title on the detail screen (screenshot 04).
    static let display = Font.system(size: 34, weight: .bold)
    /// "Picked for You", "Browse by Category", "Cities" (screenshots 02, 03).
    static let sectionTitle = Font.system(size: 26, weight: .bold)
    /// The grey continuation of a section title — "Popular Events", "Nearby".
    static let sectionSubtitle = Font.system(size: 26, weight: .regular)
    /// Centered nav-bar and sheet titles (screenshots 01, 07).
    static let navTitle = Font.system(size: 22, weight: .bold)
    /// Date group headers — "17 October" (screenshot 02).
    static let groupTitle = Font.system(size: 22, weight: .bold)
    /// The grey half of a date header — "/ Saturday".
    static let groupSubtitle = Font.system(size: 22, weight: .regular)
    /// Event row titles (screenshots 02, 03).
    static let rowTitle = Font.system(size: 20, weight: .semibold)
    /// Settings row labels, person rows, button labels (screenshots 01, 07).
    static let rowLabel = Font.system(size: 20, weight: .regular)
    /// Section labels on the tinted detail page — "Location", "Host", "About Event".
    static let sectionLabel = Font.system(size: 20, weight: .regular)
    /// Event description copy, set deliberately large and heavy (screenshot 05).
    static let prose = Font.system(size: 24, weight: .semibold)
    /// The large date line under an event title, and host names (screenshots 04, 05).
    static let lede = Font.system(size: 22, weight: .regular)
    /// Venue / location name on the tinted detail page (screenshot 04).
    static let subtitleLarge = Font.system(size: 24, weight: .regular)
    /// Times, venues, "active a while ago".
    static let body = Font.system(size: 17, weight: .regular)
    static let bodyEmphasis = Font.system(size: 17, weight: .semibold)
    /// Smaller supporting copy where 17 pt would wrap badly.
    static let meta = Font.system(size: 15, weight: .regular)
    static let metaEmphasis = Font.system(size: 15, weight: .semibold)
    /// "Sold Out" and status pills.
    static let badge = Font.system(size: 13, weight: .semibold)
    /// Tab bar labels. Smaller than Luma's because Sidequest has five tabs, not three.
    static let tabLabel = Font.system(size: 11, weight: .medium)
    /// Monospaced pass tokens.
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    /// The "SQ" brand monogram.
    static func monogram(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
}

// MARK: - Metrics

enum SQSpace {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let xxxl: CGFloat = 36

    /// Page gutter. Every header, card and row aligns to this (DESIGN_NOTES "Spacing").
    static let margin: CGFloat = 20
    /// Horizontal padding inside a grouped card.
    static let cardInset: CGFloat = 16
    /// Gap between a section header and the card beneath it.
    static let headerToCard: CGFloat = 12
    /// Gap between a card and the next section header.
    static let cardToHeader: CGFloat = 28
    /// Gap between rows inside a date group.
    static let rowGap: CGFloat = 20
    /// Gap between date groups.
    static let groupGap: CGFloat = 28
    /// Bottom inset so content clears the floating tab bar rather than being clipped by it.
    static let tabBarClearance: CGFloat = 92
}

enum SQRadius {
    static let badge: CGFloat = 8
    static let tile: CGFloat = 8
    static let thumb: CGFloat = 12
    static let chip: CGFloat = 14
    static let control: CGFloat = 14
    static let map: CGFloat = 16
    static let cover: CGFloat = 20
    static let card: CGFloat = 22
    static let sheet: CGFloat = 22
}

enum SQSize {
    static let eventThumb: CGFloat = 88
    static let avatarSmall: CGFloat = 20
    static let avatarRow: CGFloat = 44
    static let avatarLarge: CGFloat = 56
    static let iconTile: CGFloat = 32
    static let sheetCircle: CGFloat = 44
    static let floatingCircle: CGFloat = 48
    static let listRow: CGFloat = 56
    static let tabBar: CGFloat = 64
    static let tallAction: CGFloat = 88
}

// MARK: - Shadows

struct SQShadow {
    let color: Color
    let radius: CGFloat
    let y: CGFloat

    /// Grouped cards and chips.
    static let card = SQShadow(color: .black.opacity(0.06), radius: 18, y: 6)
    /// Chrome that floats over content: the tab bar, circular buttons, header capsules.
    static let floating = SQShadow(color: .black.opacity(0.10), radius: 24, y: 8)
}

extension View {
    func sqShadow(_ shadow: SQShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }
}

// MARK: - Cover tint

/// Palette for the cover-tinted event detail page (screenshots 04 and 05). Luma derives the
/// whole page colour from the event's cover art; `SQCoverTint` does the same, falling back to
/// the brand ink when there is no cover or sampling fails.
///
/// Components are stored as plain sRGB doubles rather than a `Color` so the gradient maths is
/// ordinary arithmetic — no `UIColor` round-trip, and the whole type is testable.
struct SQTint: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = max(0, min(1, red))
        self.green = max(0, min(1, green))
        self.blue = max(0, min(1, blue))
    }

    /// Sampled cover colours are often too light or too washed out to carry white text, so the
    /// tint is pushed into a consistent "deep, slightly desaturated" band before use — which is
    /// what gives every Luma detail page the same weight regardless of the artwork.
    static func fromCoverSample(red: Double, green: Double, blue: Double) -> SQTint {
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        // Pull toward the target luminance rather than clamping, so hue survives.
        let target = 0.22
        let scale = luminance > 0.001 ? min(1.6, target / luminance) : 1
        let mix = 0.25 // desaturate slightly toward the mean
        let mean = (red + green + blue) / 3
        return SQTint(
            red: (red * scale) * (1 - mix) + mean * scale * mix,
            green: (green * scale) * (1 - mix) + mean * scale * mix,
            blue: (blue * scale) * (1 - mix) + mean * scale * mix
        )
    }

    /// Brand ink, used until a cover has been sampled and whenever sampling is impossible.
    static let fallback = SQTint(red: 0x17 / 255, green: 0x21 / 255, blue: 0x1A / 255)

    var base: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    private func shifted(toward target: Double, amount: Double) -> Color {
        Color(
            .sRGB,
            red: red + (target - red) * amount,
            green: green + (target - green) * amount,
            blue: blue + (target - blue) * amount,
            opacity: 1
        )
    }

    /// The page gradient: slightly lighter at the top, settling darker at the bottom.
    var gradient: LinearGradient {
        LinearGradient(
            colors: [shifted(toward: 1, amount: 0.10), base, shifted(toward: 0, amount: 0.08)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var textPrimary: Color { .white }
    var textSecondary: Color { .white.opacity(0.60) }
    var textTertiary: Color { .white.opacity(0.45) }
    var hairline: Color { .white.opacity(0.15) }
    /// Fill for translucent controls — the Contact / More buttons and floating circles.
    var controlFill: Color { .white.opacity(0.14) }
    var controlFillStrong: Color { .white.opacity(0.22) }
    /// The primary CTA stays white: contrast against an arbitrary cover colour can't be
    /// guaranteed for the lime brand accent.
    var primaryFill: Color { .white }
    var primaryLabel: Color { Color(hex: 0x0B0B0C) }
}

// MARK: - Environment

private struct SQTintKey: EnvironmentKey {
    static let defaultValue: SQTint? = nil
}

extension EnvironmentValues {
    /// Non-nil inside a cover-tinted page; screens read it to decide between the light palette
    /// and the tinted one.
    var sqTint: SQTint? {
        get { self[SQTintKey.self] }
        set { self[SQTintKey.self] = newValue }
    }
}
