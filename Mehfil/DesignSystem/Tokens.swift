import SwiftUI
import UIKit

// Source of truth: tokens.css (light on :root, dark on [data-theme="dark"]). The reasoning lives in NOTES.md.
// Palette primitives are the only hues in the app; everything else is an alias or an alpha of one.
//
// The system in brief:
//   · ground and surface are both white; structure comes from hairlines and 14px clipping, not a tinted ground
//   · rani is the single accent, spent only on filled CTAs, the FAB, the selected tab, save/assign, the hero
//     progress bar, event 1 and chart bars — links, nav and date selection are ink
//   · one shadow tier, reserved for things that float; resting cards are flat with a hairline
//   · buttons and inputs are 8px, cards and photos 14px, sheets 20px, chips/avatars/orbs pill

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
    /// A colour that resolves per trait collection so light/dark follow the app's appearance setting.
    static func adaptive(_ light: Color, _ dark: Color) -> Color {
        Color(uiColor: UIColor { tc in tc.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

/// The palette. Nothing outside this enum invents a colour.
enum Palette {
    /// Rani pink — the accent. White text on it is 4.84:1, so filled buttons pass AA.
    static let rani = Color(hex: 0xd6246e)
    static let raniPress = Color(hex: 0xb81f5f)
    static let raniPale = Color(hex: 0xf6cfdf)
    static let error = Color(hex: 0xc13515)
    static let errorHover = Color(hex: 0xb32505)
    static let plum = Color(hex: 0x5b2c83)
    static let forest = Color(hex: 0x2e6b4f)
    static let ink = Color(hex: 0x222222)
    static let body = Color(hex: 0x3f3f3f)
    static let muted = Color(hex: 0x6a6a6a)
    static let mutedSoft = Color(hex: 0x929292)
    static let hairline = Color(hex: 0xdddddd)
    static let hairlineSoft = Color(hex: 0xebebeb)
    static let borderStrong = Color(hex: 0xc1c1c1)
    static let canvas = Color.white
    static let surfaceSoft = Color(hex: 0xf7f7f7)
    static let surfaceStrong = Color(hex: 0xf2f2f2)
    static let onPrimary = Color.white
    static let onDark = Color.white
    static let azure = Color(hex: 0x428bff)

    // DERIVED dark values: any hue below 4.5:1 on ink, mixed toward canvas until it passes.
    static let darkSurface = Color(hex: 0x2f2f2f)      // canvas 6% over ink
    static let darkAccent = Color(hex: 0xe573a2)       // rani + 36% canvas (5.5:1 on ink, 4.7:1 on dark surface)
    static let darkAccentPress = Color(hex: 0xd26b95)  // darkAccent 10% toward ink (ink text 4.8:1)
    static let darkDanger = Color(hex: 0xd4725b)       // error + 30% canvas (4.8:1)
    static let darkWarn = Color(hex: 0xa68dbc)         // plum + 46% canvas (4.6:1)
    static let darkForest = Color(hex: 0x79a08e)       // forest + 36% canvas
}

/// Semantic aliases. Each resolves light/dark exactly as tokens.css does.
enum MColor {
    static let ground = Color.adaptive(Palette.canvas, Palette.ink)
    static let surface = Color.adaptive(Palette.canvas, Palette.darkSurface)
    /// Disabled fields and filter bands.
    static let fillSoft = Color.adaptive(Palette.surfaceSoft, Color.white.opacity(0.06))
    /// Circular icon buttons and the keypad.
    static let fillStrong = Color.adaptive(Palette.surfaceStrong, Color.white.opacity(0.10))
    static let surfacePressed = Color.adaptive(Palette.surfaceSoft, Color.white.opacity(0.06))
    static let surfaceSelected = Color.adaptive(Palette.rani.opacity(0.08), Palette.rani.opacity(0.16))
    static let text = Color.adaptive(Palette.ink, Palette.onDark)
    static let textSecondary = Color.adaptive(Palette.body, Palette.hairline)
    static let textMute = Color.adaptive(Palette.muted, Palette.mutedSoft)
    /// Text on an accent or danger fill. Ink in dark mode: the lifted accent is too light for white (2.9:1).
    static let textOnPrimary = Color.adaptive(Palette.onPrimary, Palette.ink)
    static let line = Color.adaptive(Palette.hairline, Color.white.opacity(0.14))
    static let lineSoft = Color.adaptive(Palette.hairlineSoft, Color.white.opacity(0.08))
    static let lineInput = Color.adaptive(Palette.hairline, Color.white.opacity(0.28))
    /// The single accent: filled CTAs, the FAB, the selected tab, save/assign, the hero bar, event 1, chart bars.
    static let accent = Color.adaptive(Palette.rani, Palette.darkAccent)
    static let accentPress = Color.adaptive(Palette.raniPress, Palette.darkAccentPress)
    /// Deliberately NOT the accent: inline links are ink with an underline, so the accent stays rare.
    static let accentText = Color.adaptive(Palette.ink, Palette.onDark)
    static let accentTint = Color.adaptive(Palette.rani.opacity(0.08), Palette.rani.opacity(0.16))
    /// Pale rani, used for chart series.
    static let accentPale = Color.adaptive(Palette.raniPale, Palette.rani.opacity(0.42))
    static let accentSoftBg = Color.adaptive(Palette.surfaceStrong, Color.white.opacity(0.10))
    static let accentSoftText = Color.adaptive(Palette.ink, Palette.onDark)
    static let danger = Color.adaptive(Palette.error, Palette.darkDanger)
    static let dangerTint = Color.adaptive(Palette.error.opacity(0.08), Palette.error.opacity(0.18))
    /// Plum: partial payments and "due this week" — the one hue that separates from both the accent and the
    /// danger red at chip size. See NOTES.md.
    static let warn = Color.adaptive(Palette.plum, Palette.darkWarn)
    static let warnTint = Color.adaptive(Palette.plum.opacity(0.08), Palette.plum.opacity(0.30))
    /// Paid: an ink fill, the same treatment as a selected date. Settled money is not decoration.
    static let settledBg = Color.adaptive(Palette.ink, Palette.canvas)
    static let settledText = Color.adaptive(Palette.onDark, Palette.ink)
    static let disabledBg = Color.adaptive(Palette.raniPale, Color.white.opacity(0.10))
    static let disabledText = Color.adaptive(Palette.onPrimary, Color.white.opacity(0.45))
    static let disabledOutline = Color.adaptive(Palette.borderStrong, Color.white.opacity(0.24))
    static let toastBg = Color.adaptive(Palette.ink, Palette.canvas)
    static let toastText = Color.adaptive(Palette.onDark, Palette.ink)
    static let toastSuccess = Color.adaptive(Palette.onDark, Palette.ink)
    static let toastError = Color.adaptive(Palette.rani, Palette.error)
    static let toastInfo = Color.adaptive(Palette.mutedSoft, Palette.muted)
    static let scrim = Color.black.opacity(0.5)
    static let meshBase = Color.adaptive(Palette.canvas, Palette.ink)
    static let emphasisBg = Color.adaptive(Palette.ink, Palette.canvas)
    static let emphasisText = Color.adaptive(Palette.onDark, Palette.ink)
    static let segmentSelected = Color.adaptive(Palette.canvas, Color.white.opacity(0.18))
    static let segmentTrack = Color.adaptive(Palette.surfaceStrong, Color.white.opacity(0.08))

    /// Event palette, assigned at creation and cycling 1→4. The error red is excluded: it means
    /// overdue / absent / over / loss.
    static func event(_ hue: EventHue) -> Color {
        switch hue {
        case .one: accent
        case .two: Color.adaptive(Palette.forest, Palette.darkForest)
        case .three: Palette.azure
        case .four: Color.adaptive(Palette.ink, Palette.hairline)   // ink vanishes on an ink ground
        }
    }
}

enum Space {
    static let xxs: CGFloat = 2, xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12, lg: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32, huge: CGFloat = 64
}

/// rounded.xs 4 · rounded.sm 8 (buttons, inputs — no longer pills) · rounded.md 14 (cards, photos)
/// · rounded.lg 20 (sheets) · rounded.full (chips, avatars, orbs, the FAB).
enum Radius {
    static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 14, lg: CGFloat = 14, xl: CGFloat = 20, pill: CGFloat = 9999
}

enum Dim {
    static let touch: CGFloat = 44, row: CGFloat = 56, button: CGFloat = 56, buttonCompact: CGFloat = 48, input: CGFloat = 56, amountInput: CGFloat = 72
    static let icon: CGFloat = 24, iconButton: CGFloat = 20, iconSm: CGFloat = 16, iconStroke: CGFloat = 1.75, avatar: CGFloat = 40, avatarSm: CGFloat = 32
    static let calendarCell: CGFloat = 48, calendarNumeral: CGFloat = 32, dot: CGFloat = 8, timelineHour: CGFloat = 32, timelineGutter: CGFloat = 48
    static let bar: CGFloat = 8, edge: CGFloat = 4, keypadKey: CGFloat = 56, chart: CGFloat = 120, gutter: CGFloat = 16
}

// MARK: - Elevation
//
// There is ONE shadow: depth comes from photography and rounded clipping, so there is no
// progressive tier: `elevation(2)` is the same shadow as `elevation(1)`. It is reserved for things that float —
// the FAB, sheets, toasts, the selected segment, the search pill — and resting cards do not use it.

struct ShadowLevel: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var level: Int
    func body(content: Content) -> some View {
        let dark = scheme == .dark
        return content
            .shadow(color: dark ? .black.opacity(0.40) : .black.opacity(0.10), radius: 4, y: 4)
            .shadow(color: dark ? .black.opacity(0.24) : .black.opacity(0.04), radius: 3, y: 2)
    }
}

extension View {
    func elevation(_ level: Int = 1) -> some View { modifier(ShadowLevel(level: level)) }

    /// Card: white surface, 1px hairline, 14px clipping — flat at rest.
    func card(padding: CGFloat = Space.lg, fill: Color = MColor.surface, radius: CGFloat = Radius.md) -> some View {
        self
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(MColor.line, lineWidth: 1))
    }
}
