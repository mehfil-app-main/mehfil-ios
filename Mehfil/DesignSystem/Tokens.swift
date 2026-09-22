import SwiftUI
import UIKit

// Source of truth: tokens.css — Airbnb skin (light on :root, dark on [data-theme="dark"]).
// Palette primitives are documented hues from DESIGN-airbnb.md; everything else is an alias or an alpha of one.
//
// What changed from the previous (Stripe) skin, per NOTES.md:
//   · ground and surface are both white; structure comes from hairlines and 14px clipping, not a tinted ground
//   · Rausch is the single voltage and is spent only on filled CTAs, the FAB, the selected tab, save/assign,
//     the hero progress bar and event 1 — links, nav, date selection and data-viz are ink
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

/// Documented hues. Nothing outside this enum invents a colour.
enum Palette {
    static let rausch = Color(hex: 0xff385c)
    static let rauschActive = Color(hex: 0xe00b41)
    static let rauschDisabled = Color(hex: 0xffd1da)
    static let error = Color(hex: 0xc13515)
    static let errorHover = Color(hex: 0xb32505)
    static let luxe = Color(hex: 0x460479)
    static let plus = Color(hex: 0x92174d)
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
    static let legalLink = Color(hex: 0x428bff)

    // DERIVED dark values: any documented hue below 4.5:1 on ink, mixed toward canvas until it passes.
    static let darkSurface = Color(hex: 0x2f2f2f)      // canvas 6% over ink
    static let darkDanger = Color(hex: 0xd4725b)       // error + 30% canvas (4.8:1)
    static let darkWarn = Color(hex: 0xa282bc)         // luxe + 50% canvas (4.9:1)
    static let darkEvent2 = Color(hex: 0xbe7494)       // plus + 40% canvas
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
    static let surfaceSelected = Color.adaptive(Palette.rausch.opacity(0.08), Palette.rausch.opacity(0.16))
    static let text = Color.adaptive(Palette.ink, Palette.onDark)
    static let textSecondary = Color.adaptive(Palette.body, Palette.hairline)
    static let textMute = Color.adaptive(Palette.muted, Palette.mutedSoft)
    static let textOnPrimary = Palette.onPrimary
    static let line = Color.adaptive(Palette.hairline, Color.white.opacity(0.14))
    static let lineSoft = Color.adaptive(Palette.hairlineSoft, Color.white.opacity(0.08))
    static let lineInput = Color.adaptive(Palette.hairline, Color.white.opacity(0.28))
    /// The single brand voltage: filled CTAs, the FAB, the selected tab, save/assign, the hero bar, event 1.
    static let accent = Palette.rausch
    static let accentPress = Palette.rauschActive
    /// Deliberately NOT Rausch — Airbnb's inline links are ink with an underline.
    static let accentText = Color.adaptive(Palette.ink, Palette.onDark)
    static let accentTint = Color.adaptive(Palette.rausch.opacity(0.08), Palette.rausch.opacity(0.16))
    /// The documented pale Rausch, used for chart series.
    static let accentPale = Color.adaptive(Palette.rauschDisabled, Palette.rausch.opacity(0.42))
    static let accentSoftBg = Color.adaptive(Palette.surfaceStrong, Color.white.opacity(0.10))
    static let accentSoftText = Color.adaptive(Palette.ink, Palette.onDark)
    static let danger = Color.adaptive(Palette.error, Palette.darkDanger)
    static let dangerTint = Color.adaptive(Palette.error.opacity(0.08), Palette.error.opacity(0.18))
    /// Luxe purple: partial payments and "due this week". A flagged derivation — see NOTES.md.
    static let warn = Color.adaptive(Palette.luxe, Palette.darkWarn)
    static let warnTint = Color.adaptive(Palette.luxe.opacity(0.08), Palette.luxe.opacity(0.30))
    /// Paid: an ink fill, the date-picker-day-selected treatment. Settled money is not decoration.
    static let settledBg = Color.adaptive(Palette.ink, Palette.canvas)
    static let settledText = Color.adaptive(Palette.onDark, Palette.ink)
    static let disabledBg = Color.adaptive(Palette.rauschDisabled, Color.white.opacity(0.10))
    static let disabledText = Color.adaptive(Palette.onPrimary, Color.white.opacity(0.45))
    static let disabledOutline = Color.adaptive(Palette.borderStrong, Color.white.opacity(0.24))
    static let toastBg = Color.adaptive(Palette.ink, Palette.canvas)
    static let toastText = Color.adaptive(Palette.onDark, Palette.ink)
    static let toastSuccess = Color.adaptive(Palette.onDark, Palette.ink)
    static let toastError = Color.adaptive(Palette.rausch, Palette.error)
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
        case .one: Palette.rausch
        case .two: Color.adaptive(Palette.plus, Palette.darkEvent2)
        case .three: Palette.legalLink
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
// design.md documents ONE shadow and says depth comes from photography and rounded clipping, so there is no
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

    /// design.md card: white surface, 1px hairline, 14px clipping — flat at rest.
    func card(padding: CGFloat = Space.lg, fill: Color = MColor.surface, radius: CGFloat = Radius.md) -> some View {
        self
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(MColor.line, lineWidth: 1))
    }
}
