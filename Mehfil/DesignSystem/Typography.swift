import SwiftUI

// Type roles from tokens.css — Airbnb skin. Inter (design.md's sanctioned Cereal substitute) at 400–700.
// Light (300) is gone: Airbnb's lightest documented weight is 400, and the scale leans on 600/700 for headings.

enum TypeRole {
    case displayHero, displayLg, displayMd, headingLg, headingMd, headingSm
    case bodyLg, bodyMd, bodyMdStrong, bodyTabular, bodyTabularStrong
    case buttonMd, buttonSm, caption, micro, microCap

    var size: CGFloat {
        switch self {
        case .displayHero: 40          // DERIVED from rating-display 64 — see NOTES.md
        case .displayLg: 28            // display-xl
        case .displayMd: 22            // display-lg — screen titles
        case .headingLg: 21            // display-md
        case .headingMd: 20            // display-sm — sheet titles
        case .headingSm, .bodyLg, .bodyMdStrong, .buttonMd: 16
        case .bodyMd, .bodyTabular, .bodyTabularStrong, .buttonSm: 14
        case .caption: 13              // caption-sm — the load-bearing floor
        case .micro: 12                // micro-label
        case .microCap: 11             // badge — tab labels, eyebrows only
        }
    }
    var weight: Font.Weight {
        switch self {
        case .displayHero, .displayLg, .headingLg, .micro: .bold          // 700
        case .headingMd, .headingSm, .bodyMdStrong, .microCap: .semibold  // 600
        case .displayMd, .bodyTabularStrong, .buttonMd, .buttonSm: .medium // 500
        case .bodyLg, .bodyMd, .bodyTabular, .caption: .regular            // 400
        }
    }
    var lineHeight: CGFloat {
        switch self {
        case .displayHero: 1.1
        case .displayLg: 1.25
        case .displayMd: 1.18
        case .headingLg: 1.43
        case .headingMd: 1.2
        case .headingSm, .bodyMdStrong: 1.25
        case .bodyLg: 1.5
        case .bodyMd, .bodyTabular: 1.43
        case .bodyTabularStrong, .buttonSm: 1.29
        case .buttonMd: 1.25
        case .caption: 1.23
        case .micro: 1.33
        case .microCap: 1.18
        }
    }
    var tracking: CGFloat {
        switch self {
        case .displayHero: -0.63       // -1px ÷ 64 × 40
        case .displayMd: -0.44
        case .headingMd: -0.18
        default: 0                     // Airbnb sets no tracking on the rest of the scale
        }
    }
    /// tnum on every money / numeric cell (DERIVED: money columns must align).
    var tabular: Bool {
        switch self {
        case .displayHero, .bodyTabular, .bodyTabularStrong: true
        default: false
        }
    }
    var textStyle: Font.TextStyle {
        switch self {
        case .displayHero: .largeTitle
        case .displayLg: .title
        case .displayMd, .headingLg: .title2
        case .headingMd: .title3
        case .headingSm, .bodyMdStrong: .headline
        case .bodyLg, .buttonMd: .callout
        case .bodyMd: .body
        case .bodyTabular, .bodyTabularStrong, .buttonSm: .subheadline
        case .caption: .footnote
        case .micro: .caption
        case .microCap: .caption2
        }
    }
    private var fontName: String {
        switch weight {
        case .bold: "Inter-Bold"
        case .semibold: "Inter-SemiBold"
        case .medium: "Inter-Medium"
        default: "Inter-Regular"
        }
    }
    var font: Font {
        let f = Font.custom(fontName, size: size, relativeTo: textStyle)
        return tabular ? f.monospacedDigit() : f
    }
}

struct TypeModifier: ViewModifier {
    let role: TypeRole
    func body(content: Content) -> some View {
        content
            .font(role.font)
            .tracking(role.tracking)
            .lineSpacing(max(0, role.size * role.lineHeight - role.size * 1.21)) // Inter's natural line box ≈ 1.21em
    }
}

extension View {
    func type(_ role: TypeRole) -> some View { modifier(TypeModifier(role: role)) }
}

extension Text {
    @MainActor
    func role(_ role: TypeRole, _ color: Color = MColor.text) -> some View {
        self.type(role).foregroundStyle(color)
    }
}

/// Money in the design's `body-tabular-strong` role, always Indian grouping.
struct Money: View {
    var amount: Int
    var role: TypeRole = .bodyTabularStrong
    var color: Color = MColor.text
    init(_ amount: Int, _ role: TypeRole = .bodyTabularStrong, color: Color = MColor.text) { self.amount = amount; self.role = role; self.color = color }
    var body: some View { Text(Fmt.inr(amount)).role(role, color).monospacedDigit() }
}
