import SwiftUI

// Reusable pieces of the Luma-style language documented in DESIGN_NOTES.md. Screens compose
// these rather than laying out their own stacks, so spacing and type stay identical across
// the app. Everything here reads `\.sqTint` from the environment: when a screen is
// cover-tinted (the event detail, screenshots 04 and 05) the same component renders in the
// light-on-dark palette with no extra work at the call site.

// MARK: - Palette resolution

/// Resolves "which set of foreground colours am I drawing on" for a component, so each one
/// doesn't have to branch on the tint by hand.
struct SQPalette {
    let tint: SQTint?

    var isTinted: Bool { tint != nil }
    var textPrimary: Color { tint?.textPrimary ?? SQColor.textPrimary }
    var textSecondary: Color { tint?.textSecondary ?? SQColor.textSecondary }
    var textTertiary: Color { tint?.textTertiary ?? SQColor.textTertiary }
    var hairline: Color { tint?.hairline ?? SQColor.hairline }
    var chevron: Color { tint?.textTertiary ?? SQColor.chevron }
    /// Fill for a grouped card or a circular chrome button.
    var surface: Color { tint?.controlFill ?? SQColor.surface }
    /// Fill for a recessed well — icon tiles, empty-state tiles, time badges.
    var well: Color { tint?.controlFill ?? SQColor.surfaceAlt }
}

private struct SQPaletteReader<Content: View>: View {
    @Environment(\.sqTint) private var tint
    @ViewBuilder var content: (SQPalette) -> Content
    var body: some View { content(SQPalette(tint: tint)) }
}

// MARK: - Avatar

/// Circular identity mark. Luma uses a generated purple blob; Sidequest uses a lime-on-ink
/// monogram so the app keeps its own branding at the same sizes.
struct SQAvatar: View {
    let seed: String
    var size: CGFloat = SQSize.avatarRow
    var imageURL: URL?

    private var initials: String {
        let words = seed
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "SQ" : letters.uppercased()
    }

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    monogram
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var monogram: some View {
        ZStack {
            SQColor.ink
            Text(initials)
                .font(SQFont.monogram(size * 0.40))
                .foregroundStyle(SQColor.lime)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, 2)
        }
    }
}

/// Overlapping row of avatars with a "+N" overflow bubble — screenshot 05's attendee stack.
struct SQAvatarStack: View {
    let seeds: [String]
    var overflow: Int = 0
    var size: CGFloat = SQSize.avatarRow

    var body: some View {
        SQPaletteReader { palette in
            HStack(spacing: -size * 0.32) {
                ForEach(Array(seeds.enumerated()), id: \.offset) { _, seed in
                    SQAvatar(seed: seed, size: size)
                        .overlay(Circle().stroke(palette.isTinted ? Color.white.opacity(0.25) : SQColor.surface, lineWidth: 2))
                }
                if overflow > 0 {
                    ZStack {
                        Circle().fill(palette.well)
                        Text("+\(overflow)")
                            .font(SQFont.metaEmphasis)
                            .foregroundStyle(palette.textPrimary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(palette.isTinted ? Color.white.opacity(0.25) : SQColor.surface, lineWidth: 2))
                }
            }
        }
    }
}

// MARK: - Circular chrome

/// A floating circular glyph button — the back / share / locate buttons in screenshots
/// 01, 04, 06 and the sheet's close button in 07.
struct SQCircleButton: View {
    let systemImage: String
    var size: CGFloat = SQSize.floatingCircle
    var floating = true
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        SQPaletteReader { palette in
            Button(role: role, action: action) {
                ZStack {
                    Circle().fill(palette.surface)
                    Image(systemName: systemImage)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(role == .destructive ? SQColor.destructive : palette.textPrimary)
                }
                .frame(width: size, height: size)
                .sqShadow(floating && !palette.isTinted ? SQShadow.floating : SQShadow(color: .clear, radius: 0, y: 0))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Two or more glyph buttons sharing one capsule, as Luma groups them in the top-right of
/// screenshots 02, 03 and 05 rather than using separate circles.
struct SQActionCapsule<Content: View>: View {
    var height: CGFloat = SQSize.floatingCircle
    @ViewBuilder var content: Content

    var body: some View {
        SQPaletteReader { palette in
            HStack(spacing: SQSpace.xl) {
                content
            }
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, SQSpace.xl)
            .frame(height: height)
            .background(palette.surface, in: Capsule())
            .sqShadow(palette.isTinted ? SQShadow(color: .clear, radius: 0, y: 0) : SQShadow.floating)
        }
    }
}

/// A glyph inside an `SQActionCapsule`, optionally carrying the red dot Luma puts on the bell.
struct SQCapsuleGlyph: View {
    let systemImage: String
    var showsBadge = false
    var accessibilityTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .overlay(alignment: .topTrailing) {
                    if showsBadge {
                        Circle()
                            .fill(SQColor.destructive)
                            .frame(width: 9, height: 9)
                            .offset(x: 3, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
    }
}

// MARK: - Headers

/// The big left-aligned screen header: avatar, title, trailing chrome (screenshots 02, 03).
struct SQScreenHeader<Trailing: View>: View {
    let title: String
    var avatarSeed: String? = "Sidequest"
    var showsSparkle = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        SQPaletteReader { palette in
            HStack(spacing: SQSpace.md) {
                if let avatarSeed {
                    SQAvatar(seed: avatarSeed, size: SQSize.avatarRow)
                }
                HStack(spacing: 2) {
                    Text(title)
                        .font(SQFont.screenTitle)
                        .foregroundStyle(palette.textPrimary)
                    if showsSparkle {
                        Image(systemName: "sparkle")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(SQColor.accent)
                            .offset(y: -8)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: SQSpace.sm)
                trailing
            }
            .padding(.horizontal, SQSpace.margin)
        }
    }
}

/// A centered nav-bar title flanked by circular buttons — screenshot 01's "Settings".
struct SQNavBar<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        SQPaletteReader { palette in
            ZStack {
                Text(title)
                    .font(SQFont.navTitle)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 72)
                HStack {
                    leading
                    Spacer()
                    trailing
                }
            }
            .padding(.horizontal, SQSpace.margin)
        }
    }
}

/// Section title, optionally with a chevron hugging the text and a grey second line —
/// "Picked for You" over "Nearby", "New Delhi" over "Popular Events".
struct SQSectionHeader: View {
    let title: String
    var subtitle: String?
    var subtitleGlyph: String?
    var showsChevron = false
    var action: (() -> Void)?

    var body: some View {
        SQPaletteReader { palette in
            VStack(alignment: .leading, spacing: 0) {
                headerLine(palette)
                if let subtitle {
                    HStack(spacing: SQSpace.sm) {
                        Text(subtitle)
                            .font(SQFont.sectionSubtitle)
                            .foregroundStyle(palette.textTertiary)
                        if let subtitleGlyph {
                            Image(systemName: subtitleGlyph)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SQSpace.margin)
        }
    }

    @ViewBuilder private func headerLine(_ palette: SQPalette) -> some View {
        let line = HStack(spacing: SQSpace.sm) {
            Text(title)
                .font(SQFont.sectionTitle)
                .foregroundStyle(palette.textPrimary)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)

        if let action {
            Button(action: action) { line }.buttonStyle(.plain)
        } else {
            line
        }
    }
}

/// Small grey header that sits above a grouped card — "Preferences" in screenshot 01.
struct SQGroupHeader: View {
    let title: String

    var body: some View {
        SQPaletteReader { palette in
            Text(title)
                .font(SQFont.rowLabel)
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SQSpace.margin + SQSpace.cardInset)
        }
    }
}

/// `17 October` in bold followed by ` / Saturday` in grey — screenshot 02's two-tone date rule.
struct SQDateHeader: View {
    let date: Date

    private var dayMonth: String {
        date.formatted(.dateTime.day().month(.wide))
    }

    private var weekday: String {
        date.formatted(.dateTime.weekday(.wide))
    }

    var body: some View {
        SQPaletteReader { palette in
            HStack(spacing: SQSpace.sm) {
                Text(dayMonth)
                    .font(SQFont.groupTitle)
                    .foregroundStyle(palette.textPrimary)
                Text("/ \(weekday)")
                    .font(SQFont.groupSubtitle)
                    .foregroundStyle(palette.textTertiary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SQSpace.margin)
        }
    }
}

/// A label with a hairline under it, used for every section on the tinted detail page
/// ("Location", "Host", "About Event"). Optionally carries a trailing action on the same line.
struct SQSectionLabel: View {
    let title: String
    var trailingTitle: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        SQPaletteReader { palette in
            VStack(spacing: SQSpace.sm) {
                HStack {
                    Text(title)
                        .font(SQFont.sectionLabel)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    if let trailingTitle {
                        if let trailingAction {
                            Button(trailingTitle, action: trailingAction)
                                .buttonStyle(.plain)
                                .font(SQFont.sectionLabel)
                                .foregroundStyle(palette.textTertiary)
                        } else {
                            Text(trailingTitle)
                                .font(SQFont.sectionLabel)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - Containers

/// A grouped white card — the building block of screenshot 01 and of every sheet.
struct SQCard<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        SQPaletteReader { palette in
            VStack(spacing: 0) { content }
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: SQRadius.card, style: .continuous))
                .sqShadow(palette.isTinted ? SQShadow(color: .clear, radius: 0, y: 0) : SQShadow.card)
        }
    }
}

/// The inset hairline between rows inside a card. `leading` matches the x-origin of the row's
/// label so the divider starts under the text, not under the icon.
struct SQInsetDivider: View {
    var leading: CGFloat = SQSize.iconTile + SQSpace.cardInset + 14

    var body: some View {
        SQPaletteReader { palette in
            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)
                .padding(.leading, leading)
        }
    }
}

// MARK: - List rows

/// The 32 pt coloured rounded square that leads a settings row (screenshot 01).
struct SQIconTile: View {
    let systemImage: String
    var color: Color = SQColor.hueBlue
    var size: CGFloat = SQSize.iconTile

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SQRadius.tile, style: .continuous).fill(color)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

enum SQRowAccessory {
    case chevron
    case external
    case none
}

/// A settings-style row: optional coloured icon tile, label, optional value, accessory.
struct SQListRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var iconColor: Color = SQColor.hueBlue
    var accessory: SQRowAccessory = .chevron
    var destructive = false
    var action: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        SQPaletteReader { palette in
            let content = HStack(spacing: 14) {
                if let systemImage {
                    SQIconTile(systemImage: systemImage, color: destructive ? SQColor.destructive : iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SQFont.rowLabel)
                        .foregroundStyle(destructive ? SQColor.destructive : palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(SQFont.body)
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: SQSpace.sm)
                trailing
                accessoryView(palette)
            }
            .padding(.horizontal, SQSpace.cardInset)
            .frame(minHeight: SQSize.listRow)
            .contentShape(Rectangle())

            if let action {
                Button(action: action) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    @ViewBuilder private func accessoryView(_ palette: SQPalette) -> some View {
        switch accessory {
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.chevron)
        case .external:
            Image(systemName: "arrow.up.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.chevron)
        case .none:
            EmptyView()
        }
    }
}

extension SQListRow where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        iconColor: Color = SQColor.hueBlue,
        accessory: SQRowAccessory = .chevron,
        destructive: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            iconColor: iconColor,
            accessory: accessory,
            destructive: destructive,
            action: action,
            trailing: { EmptyView() }
        )
    }
}

/// The profile row at the top of screenshot 01: large avatar, name, secondary line, chevron.
struct SQProfileRow: View {
    let name: String
    var subtitle: String
    var seed: String
    var action: (() -> Void)?

    var body: some View {
        SQPaletteReader { palette in
            let content = HStack(spacing: 14) {
                SQAvatar(seed: seed, size: SQSize.avatarLarge)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(SQFont.navTitle)
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(SQFont.body)
                        .foregroundStyle(palette.textSecondary)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: SQSpace.sm)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.chevron)
                }
            }
            .padding(.horizontal, SQSpace.cardInset)
            .frame(minHeight: 80)
            .contentShape(Rectangle())

            if let action {
                Button(action: action) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }
}

// MARK: - Event row

/// Small capsule tag — "Sold Out" in screenshot 03, and registration status in My Journey.
struct SQBadge: View {
    let text: String
    var foreground: Color = SQColor.destructive
    var background: Color = SQColor.destructiveWash

    var body: some View {
        Text(text)
            .font(SQFont.badge)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, SQSpace.sm)
            .padding(.vertical, SQSpace.xs)
            .background(background, in: RoundedRectangle(cornerRadius: SQRadius.badge, style: .continuous))
    }
}

/// Square cover thumbnail with a branded placeholder for events that have no artwork.
/// A remote image that cannot change its own layout size.
///
/// `scaledToFill()` lets an image report a size larger than the frame it was
/// handed, and `.clipped()` only clips the drawing — the oversized width is
/// still what the parent lays out against. In a `ScrollView` that shows up as
/// a page that visibly widens, or "bulges", the moment a cover or photo
/// finishes loading, which is exactly what a tall or very wide poster does.
///
/// Drawing the image in an `overlay` keeps it out of layout entirely: the
/// clear shape underneath fixes the size from the caller's frame, and the
/// image is clipped to it. Callers must give this a size, the same as they
/// would any image.
struct SQRemoteImage<Placeholder: View>: View {
    var url: URL?
    var radius: CGFloat = SQRadius.thumb
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        Color.clear
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else if phase.error != nil {
                            placeholder()
                        } else {
                            placeholder().overlay(ProgressView().controlSize(.small))
                        }
                    }
                } else {
                    placeholder()
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct SQThumbnail: View {
    var url: URL?
    var seed: String
    var size: CGFloat = SQSize.eventThumb
    var radius: CGFloat = SQRadius.thumb

    var body: some View {
        SQPaletteReader { palette in
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else if phase.error != nil {
                            placeholder(palette)
                        } else {
                            placeholder(palette).overlay(ProgressView().controlSize(.small))
                        }
                    }
                } else {
                    placeholder(palette)
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    private func placeholder(_ palette: SQPalette) -> some View {
        ZStack {
            palette.well
            Text(String(seed.prefix(1)).uppercased())
                .font(SQFont.monogram(size * 0.34))
                .foregroundStyle(palette.textTertiary)
        }
    }
}

/// One line of the meta row under an event title: glyph + text.
struct SQMetaItem: View {
    let systemImage: String
    let text: String

    var body: some View {
        SQPaletteReader { palette in
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                Text(text)
                    .font(SQFont.body)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

/// The core feed row from screenshots 02 and 03: thumbnail, host line, title, meta line.
/// Flat on the background — no card, no border, no shadow.
struct SQEventRow: View {
    let title: String
    var hostName: String?
    var imageURL: URL?
    var seed: String
    var timeText: String?
    var venueText: String?
    var badgeText: String?
    var badgeForeground: Color = SQColor.destructive
    var badgeBackground: Color = SQColor.destructiveWash

    var body: some View {
        SQPaletteReader { palette in
            HStack(alignment: .top, spacing: SQSpace.lg) {
                SQThumbnail(url: imageURL, seed: seed)
                VStack(alignment: .leading, spacing: SQSpace.xs) {
                    if hostName != nil || badgeText != nil {
                        HStack(spacing: SQSpace.sm) {
                            if let hostName {
                                SQAvatar(seed: hostName, size: SQSize.avatarSmall)
                                Text(hostName)
                                    .font(SQFont.body)
                                    .foregroundStyle(palette.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: SQSpace.xs)
                            if let badgeText {
                                SQBadge(text: badgeText, foreground: badgeForeground, background: badgeBackground)
                            }
                        }
                    }
                    Text(title)
                        .font(SQFont.rowTitle)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if timeText != nil || venueText != nil {
                        HStack(spacing: SQSpace.lg) {
                            if let timeText {
                                SQMetaItem(systemImage: "clock", text: timeText)
                            }
                            if let venueText {
                                SQMetaItem(systemImage: "mappin.circle", text: venueText)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Buttons

/// Full-width primary action. Luma's is black-on-white; Sidequest's is ink with a lime label
/// so the app keeps its own accent (see PLAN.md decision 4).
struct SQPrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        SQPaletteReader { palette in
            Button(action: action) {
                HStack(spacing: SQSpace.sm) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(palette.isTinted ? SQColor.onLight : SQColor.onPrimary)
                    } else if let systemImage {
                        Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
                    }
                    Text(title).font(SQFont.bodyEmphasis)
                }
                .foregroundStyle(palette.isTinted ? SQColor.onLight : SQColor.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: SQSize.listRow)
                .background(
                    (palette.isTinted ? Color.white : SQColor.primaryFill).opacity(isEnabled ? 1 : 0.4),
                    in: RoundedRectangle(cornerRadius: SQRadius.control, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled || isLoading)
        }
    }
}

/// Secondary action: outlined in light contexts, translucent fill when tinted.
struct SQSecondaryButton: View {
    let title: String
    var systemImage: String?
    var isSelected = false
    var destructive = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        SQPaletteReader { palette in
            Button(action: action) {
                HStack(spacing: SQSpace.sm) {
                    if let systemImage {
                        Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                    }
                    Text(title).font(SQFont.bodyEmphasis)
                }
                .foregroundStyle(foreground(palette))
                .frame(maxWidth: .infinity)
                .frame(height: SQSize.listRow)
                .background(fill(palette), in: RoundedRectangle(cornerRadius: SQRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SQRadius.control, style: .continuous)
                        .stroke(palette.isTinted ? Color.clear : SQColor.separator, lineWidth: 1)
                )
                .opacity(isEnabled ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
    }

    private func foreground(_ palette: SQPalette) -> Color {
        if destructive { return SQColor.destructive }
        if isSelected && !palette.isTinted { return SQColor.ink }
        return palette.textPrimary
    }

    private func fill(_ palette: SQPalette) -> Color {
        if palette.isTinted { return isSelected ? Color.white.opacity(0.26) : Color.white.opacity(0.14) }
        return isSelected ? SQColor.lime.opacity(0.35) : SQColor.surface
    }
}

/// The tall icon-above-label button from the event detail action row (screenshot 04).
struct SQTallAction: View {
    let title: String
    let systemImage: String
    var prominent = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        SQPaletteReader { palette in
            Button(action: action) {
                VStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                    Text(title)
                        .font(SQFont.bodyEmphasis)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(foreground(palette))
                .frame(maxWidth: .infinity)
                .frame(height: SQSize.tallAction)
                .background(fill(palette), in: RoundedRectangle(cornerRadius: SQRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SQRadius.control, style: .continuous)
                        .stroke(palette.isTinted || prominent ? Color.clear : SQColor.separator, lineWidth: 1)
                )
                .opacity(isEnabled ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
    }

    private func foreground(_ palette: SQPalette) -> Color {
        guard prominent else { return palette.textPrimary }
        return palette.isTinted ? SQColor.onLight : SQColor.onPrimary
    }

    private func fill(_ palette: SQPalette) -> Color {
        guard prominent else { return palette.isTinted ? Color.white.opacity(0.14) : SQColor.surface }
        return palette.isTinted ? Color.white : SQColor.primaryFill
    }
}

/// Category chip from screenshot 03: white, hairline border, coloured glyph, 20 pt label.
struct SQChip: View {
    let title: String
    var systemImage: String?
    var color: Color = SQColor.hueBlue
    var isSelected = false
    let action: () -> Void

    var body: some View {
        SQPaletteReader { palette in
            Button(action: action) {
                HStack(spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(isSelected ? palette.textPrimary : color)
                    }
                    Text(title)
                        .font(SQFont.rowLabel)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, SQSpace.cardInset)
                .frame(height: SQSize.listRow)
                .background(
                    isSelected ? SQColor.lime.opacity(0.35) : palette.surface,
                    in: RoundedRectangle(cornerRadius: SQRadius.chip, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SQRadius.chip, style: .continuous)
                        .stroke(isSelected ? SQColor.textPrimary.opacity(0.3) : SQColor.separator, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Empty state

/// Luma's empty state (screenshot 02) is a *left-aligned* tile beside grey copy, which
/// `ContentUnavailableView` cannot express — so every empty state in the app uses this.
struct SQEmptyState: View {
    let message: String
    var systemImage: String = "ticket"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        SQPaletteReader { palette in
            VStack(alignment: .leading, spacing: SQSpace.lg) {
                HStack(alignment: .top, spacing: SQSpace.xl) {
                    ZStack {
                        RoundedRectangle(cornerRadius: SQRadius.cover, style: .continuous)
                            .fill(palette.well)
                        Image(systemName: systemImage)
                            .font(.system(size: 32, weight: .regular))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .frame(width: 80, height: 80)
                    Text(message)
                        .font(SQFont.rowLabel)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                if let actionTitle, let action {
                    SQSecondaryButton(title: actionTitle, action: action)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Sheets

/// Sheet chrome from screenshot 07: grabber, circular close button, centered bold title,
/// optional trailing circular button.
struct SQSheetHeader<Trailing: View>: View {
    let title: String
    var onClose: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(SQColor.textTertiary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, SQSpace.sm)
            SQNavBar(title: title) {
                SQCircleButton(systemImage: "xmark", size: SQSize.sheetCircle, floating: false, action: onClose)
            } trailing: {
                trailing
            }
            .padding(.top, SQSpace.lg)
            .padding(.bottom, SQSpace.lg)
        }
    }
}

extension SQSheetHeader where Trailing == EmptyView {
    init(title: String, onClose: @escaping () -> Void) {
        self.init(title: title, onClose: onClose, trailing: { EmptyView() })
    }
}

/// Standard sheet body: header, then scrolling content on the grouped background.
struct SQSheet<Content: View>: View {
    let title: String
    var onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            SQSheetHeader(title: title, onClose: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: SQSpace.xl) {
                    content
                }
                .padding(.horizontal, SQSpace.margin)
                .padding(.bottom, SQSpace.xxxl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(SQColor.background.ignoresSafeArea())
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Screen scaffold

/// Wraps a screen in the right background and reserves room for the floating tab bar, so no
/// screen has to remember the bottom inset.
struct SQScreen<Content: View>: View {
    var background: Color = SQColor.plainBackground
    var reservesTabBar = true
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SQSpace.xxl) {
                content
            }
            .padding(.top, SQSpace.md)
            .padding(.bottom, reservesTabBar ? SQSpace.tabBarClearance : SQSpace.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(background.ignoresSafeArea())
    }
}

// MARK: - Tab bar

/// Lets a pushed screen hide the floating tab bar — the chat room needs the space for its
/// composer, which the bar would otherwise sit on top of.
struct SQTabBarHiddenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    func sqHidesTabBar(_ hidden: Bool = true) -> some View {
        preference(key: SQTabBarHiddenKey.self, value: hidden)
    }
}

struct SQTabItem: Identifiable {
    let id: Int
    let title: String
    let systemImage: String
    let selectedSystemImage: String
}

/// The floating capsule tab bar seen in every full-screen screenshot. Content scrolls
/// underneath it; screens reserve `SQSpace.tabBarClearance` at the bottom.
struct SQTabBar: View {
    let items: [SQTabItem]
    @Binding var selection: Int

    var body: some View {
        SQPaletteReader { palette in
            HStack(spacing: 0) {
                ForEach(items) { item in
                    Button {
                        selection = item.id
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: selection == item.id ? item.selectedSystemImage : item.systemImage)
                                .font(.system(size: 19, weight: selection == item.id ? .semibold : .regular))
                            Text(item.title)
                                .font(SQFont.tabLabel)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(selection == item.id ? palette.textPrimary : palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background {
                            if selection == item.id {
                                Capsule().fill(selectedFill(palette))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selection == item.id ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: SQSize.tabBar)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(palette.isTinted ? Color.white.opacity(0.06) : SQColor.surfaceAlt.opacity(0.55)))
                    .overlay(Capsule().stroke(palette.isTinted ? Color.white.opacity(0.12) : Color.clear, lineWidth: 1))
            }
            .clipShape(Capsule())
            .sqShadow(SQShadow.floating)
            .padding(.horizontal, SQSpace.lg)
            .animation(.snappy(duration: 0.22), value: selection)
        }
    }

    private func selectedFill(_ palette: SQPalette) -> Color {
        palette.isTinted ? Color.white.opacity(0.18) : SQColor.separator.opacity(0.9)
    }
}

// MARK: - Form field

/// Text entry styled to sit inside a grouped card rather than using `.roundedBorder`.
struct SQField: View {
    let placeholder: String
    @Binding var text: String
    var systemImage: String?
    var isSecure = false
    var axisVertical = false
    var lineLimit: ClosedRange<Int>?

    var body: some View {
        SQPaletteReader { palette in
            HStack(spacing: SQSpace.md) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                        .frame(width: 22)
                }
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else if axisVertical {
                        TextField(placeholder, text: $text, axis: .vertical)
                            .lineLimit(lineLimit ?? 3...8)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(SQFont.body)
                .foregroundStyle(palette.textPrimary)
                .textFieldStyle(.plain)
            }
            .padding(.horizontal, SQSpace.cardInset)
            .padding(.vertical, 14)
            .frame(minHeight: SQSize.listRow)
            .background(palette.well, in: RoundedRectangle(cornerRadius: SQRadius.control, style: .continuous))
        }
    }
}

// MARK: - Inline feedback

/// Consistent inline success / error / warning line.
struct SQNotice: View {
    enum Kind { case success, error, warning, info }
    let text: String
    var kind: Kind = .info

    private var color: Color {
        switch kind {
        case .success: SQColor.positive
        case .error: SQColor.destructive
        case .warning: SQColor.warning
        case .info: SQColor.textSecondary
        }
    }

    private var glyph: String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SQSpace.sm) {
            Image(systemName: glyph).font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(SQFont.meta)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
