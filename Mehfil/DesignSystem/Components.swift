import SwiftUI

// MARK: - 01 Button (primary, secondary, tertiary, destructive · default, pressed, disabled, loading)

enum MButtonStyle { case primary, secondary, tertiary, destructive }
enum MButtonSize { case regular, compact }

struct MButton: View {
    var title: String
    var icon: String? = nil
    var style: MButtonStyle = .primary
    var size: MButtonSize = .regular
    var loading = false
    var fullWidth = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if loading { ProgressView().controlSize(.small).tint(labelColor) }
                else if let icon { Image(systemName: icon).font(.system(size: 16, weight: .regular)).frame(width: Dim.iconButton, height: Dim.iconButton) }
                Text(title).type(.buttonMd)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(MButtonStyleImpl(style: style, size: size))
        .disabled(loading)
    }
    private var labelColor: Color { style == .primary ? MColor.textOnPrimary : MColor.accentText }
}

private struct MButtonStyleImpl: ButtonStyle {
    var style: MButtonStyle
    var size: MButtonSize
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let h: CGFloat = size == .regular ? Dim.button : Dim.buttonCompact
        // Never below design.md's 8 × 16 padding; regular buttons use sm × xl.
        let hp: CGFloat = size == .regular ? Space.xl : Space.lg
        configuration.label
            .foregroundStyle(foreground(pressed))
            .padding(.horizontal, hp)
            .frame(minHeight: h)
            .background(background(pressed), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(border, lineWidth: 1))
            .opacity(enabled ? 1 : (style == .primary ? 1 : 0.55))
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
    private func foreground(_ pressed: Bool) -> Color {
        if !enabled { return style == .primary ? MColor.disabledText : MColor.disabledText }
        switch style {
        case .primary: return MColor.textOnPrimary
        case .secondary, .tertiary: return MColor.accentText
        case .destructive: return MColor.danger
        }
    }
    private func background(_ pressed: Bool) -> Color {
        if !enabled && style == .primary { return MColor.disabledBg }
        switch style {
        case .primary: return pressed ? MColor.accentPress : MColor.accent
        case .secondary: return pressed ? MColor.accentTint : .clear
        case .tertiary: return pressed ? MColor.accentTint : .clear
        case .destructive: return pressed ? MColor.dangerTint : .clear
        }
    }
    private var border: Color {
        switch style {
        case .secondary: enabled ? MColor.accentText : MColor.disabledText
        case .destructive: MColor.danger
        default: .clear
        }
    }
}

/// Small icon-only 44pt target (row trailing actions, nav actions inside content).
struct IconButton: View {
    var symbol: String
    var color: Color = MColor.accentText
    var size: CGFloat = Dim.icon
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size == Dim.icon ? 18 : 14, weight: .regular))
                .foregroundStyle(color)
                .frame(width: Dim.touch, height: Dim.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 02 Status chip (icon + word, always both)

enum ChipKind {
    case paid, partial, overdue, confirmed, pending, cancelled, conflict, arrived, absent, loss

    var label: String {
        switch self {
        case .paid: "Paid"; case .partial: "Partial"; case .overdue: "Overdue"; case .confirmed: "Confirmed"
        case .pending: "Pending"; case .cancelled: "Cancelled"; case .conflict: "Crew conflict"; case .arrived: "Arrived"
        case .absent: "Absent"; case .loss: "Running at a loss"
        }
    }
    var symbol: String {
        switch self {
        case .paid: "checkmark.circle"; case .partial: "clock"; case .overdue: "exclamationmark.circle"; case .confirmed: "checkmark"
        case .pending: "clock"; case .cancelled: "xmark"; case .conflict: "exclamationmark.triangle"; case .arrived: "checkmark.circle"
        case .absent: "xmark.circle"; case .loss: "exclamationmark.circle"
        }
    }
    static func from(_ p: PaymentState) -> ChipKind {
        switch p { case .paid: .paid; case .partial: .partial; case .overdue: .overdue; case .pending: .pending }
    }
    static func from(_ m: MilestoneStatus) -> ChipKind {
        switch m { case .paid: .paid; case .pending: .pending; case .overdue: .overdue }
    }
}

struct StatusChip: View {
    var kind: ChipKind
    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: kind.symbol).font(.system(size: 11, weight: .regular)).frame(width: Dim.iconSm, height: Dim.iconSm)
            Text(kind.label).type(.caption)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(bg, in: Capsule())
        .overlay(Capsule().strokeBorder(border, lineWidth: 1))
    }
    private var fg: Color {
        switch kind {
        case .paid: MColor.accentSoftText
        case .partial: MColor.warn
        case .overdue, .conflict, .absent, .loss: MColor.danger
        case .confirmed, .arrived: MColor.text
        case .pending, .cancelled: MColor.textMute
        }
    }
    private var bg: Color {
        switch kind {
        case .paid: MColor.accentSoftBg          // pill-tag-soft: settled money is not decoration
        case .partial: MColor.warnTint
        case .overdue, .conflict, .absent, .loss: MColor.dangerTint
        case .confirmed, .arrived, .pending, .cancelled: MColor.surface
        }
    }
    private var border: Color {
        switch kind {
        case .confirmed, .arrived, .pending, .cancelled: MColor.line
        default: .clear
        }
    }
}

// MARK: - 07 Avatar / avatar stack

struct Avatar: View {
    /// Kept for call-site compatibility with stored records; the photo is no longer used.
    var index: Int?
    var name: String
    var size: CGFloat = Dim.avatar
    var muted = false
    var body: some View {
        ZStack {
            Initials.color(for: name)
            Text(Initials.of(name))
                .font(.custom("Inter-SemiBold", size: size * 0.38))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .opacity(muted ? 0.5 : 1)
    }
}

/// Initials and a stable colour for a person, so the same name always looks the same on every device
/// and on both platforms. Deliberately not random: a client's tile must not change between launches.
enum Initials {
    /// "Vikram Kapoor" → "VK" · "Ajay" → "A" · "" → "?"
    static func of(_ name: String) -> String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
        guard let first = words.first?.first else { return "?" }
        if words.count > 1, let last = words.last?.first { return "\(first)\(last)".uppercased() }
        return String(first).uppercased()
    }

    /// Eight hues that all carry white text at 4.5:1 or better, on brand with the Airbnb skin.
    private static let hues: [Color] = [
        Color(.sRGB, red: 0.75, green: 0.22, blue: 0.36, opacity: 1),   // rausch, deepened for contrast
        Color(.sRGB, red: 0.57, green: 0.09, blue: 0.30, opacity: 1),   // plus
        Color(.sRGB, red: 0.27, green: 0.02, blue: 0.47, opacity: 1),   // luxe
        Color(.sRGB, red: 0.13, green: 0.35, blue: 0.62, opacity: 1),   // legal-link, deepened
        Color(.sRGB, red: 0.11, green: 0.40, blue: 0.36, opacity: 1),   // teal
        Color(.sRGB, red: 0.45, green: 0.30, blue: 0.13, opacity: 1),   // amber, deepened
        Color(.sRGB, red: 0.30, green: 0.35, blue: 0.42, opacity: 1),   // slate
        Color(.sRGB, red: 0.13, green: 0.13, blue: 0.13, opacity: 1),   // ink
    ]

    static func color(for name: String) -> Color {
        guard !name.isEmpty else { return hues[7] }
        // FNV-1a over the scalars: stable across launches, platforms and Swift versions.
        var hash: UInt32 = 2166136261
        for byte in name.lowercased().utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return hues[Int(hash % UInt32(hues.count))]
    }
}

struct AvatarStack: View {
    var members: [CrewMember]
    var confirmed: Set<String> = []
    var body: some View {
        HStack(spacing: -Space.sm) {
            ForEach(Array(members.prefix(4))) { m in
                Avatar(index: m.avatar, name: m.name, size: Dim.avatarSm, muted: !confirmed.isEmpty && !confirmed.contains(m.id))
                    .overlay(Circle().strokeBorder(MColor.surface, lineWidth: 2))
            }
            if members.count > 4 {
                Text("+\(members.count - 4)").type(.caption).foregroundStyle(MColor.text)
                    .frame(width: Dim.avatarSm, height: Dim.avatarSm)
                    .background(MColor.line, in: Circle())
                    .overlay(Circle().strokeBorder(MColor.surface, lineWidth: 2))
            }
        }
    }
}

// MARK: - 08 Commitment bar (committed · remaining · overflow)

struct CommitmentBar: View {
    var committed: Int
    var total: Int
    var height: CGFloat = Dim.bar
    var body: some View {
        GeometryReader { g in
            let over = committed > total
            let denom = CGFloat(max(committed, total, 1))
            let cw = g.size.width * CGFloat(min(committed, total)) / denom
            let ow = over ? g.size.width * CGFloat(committed - total) / denom : 0
            HStack(spacing: 0) {
                Rectangle().fill(MColor.accent).frame(width: cw)
                if over { Rectangle().fill(MColor.danger).frame(width: ow) }
                Rectangle().fill(MColor.line)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
        }
        .frame(height: height)
    }
}

/// Plain progress (C2 collection, A4 target, D2 assignment).
struct ProgressBar: View {
    var fraction: Double
    var tint: Color = MColor.accent
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(MColor.line)
                Capsule().fill(tint).frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }
        .frame(height: Dim.bar)
    }
}

// MARK: - 09 Input field (label above, field, helper / error line)

struct InputField: View {
    var label: String
    @Binding var text: String
    var placeholder = ""
    var helper: String? = nil
    var error: String? = nil
    var keyboard: UIKeyboardType = .default
    var trailing: String? = nil
    /// Marks the field as an SMS one-time code so iOS offers the code from Messages above the keyboard.
    var oneTimeCode = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(label).type(.caption).foregroundStyle(MColor.textMute)
            HStack(spacing: Space.sm) {
                TextField(placeholder, text: $text)
                    .type(.bodyMd).foregroundStyle(MColor.text)
                    .keyboardType(keyboard)
                    .textContentType(oneTimeCode ? .oneTimeCode : nil)
                    .focused($focused)
                    .tint(MColor.text)
                if let trailing { Image(systemName: trailing).font(.system(size: 16)).foregroundStyle(MColor.textMute) }
            }
            .padding(.horizontal, Space.md)
            .frame(height: Dim.input)
            .background(MColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(error != nil ? MColor.danger : (focused ? MColor.text : MColor.lineInput), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            if let error { Text(error).type(.caption).foregroundStyle(MColor.danger) }
            else if let helper { Text(helper).type(.caption).foregroundStyle(MColor.textMute) }
        }
    }
}

/// Field-shaped row that opens a picker or a date sheet (B3 event type, dates, E3 source / budget).
/// A phone field that accepts digits only, caps at 10, and shows why a number is rejected.
/// The binding always receives digits — formatting for display happens at the point of use.
struct PhoneField: View {
    var label: String = "Phone"
    @Binding var text: String
    var placeholder = "98100 00000"
    var helper: String? = nil
    var body: some View {
        InputField(
            label: label,
            text: Binding(get: { text }, set: { text = Fmt.phoneDigitsOnly($0) }),
            placeholder: placeholder,
            helper: helper,
            error: Fmt.phoneProblem(text),
            keyboard: .numberPad
        )
    }
}

/// A password field with a visibility toggle. SwiftUI cannot switch a SecureField to a TextField in place
/// without losing focus, so both are kept and only one is shown.
struct PasswordField: View {
    var label: String
    @Binding var text: String
    var placeholder = ""
    var helper: String? = nil
    var newPassword = false
    @State private var visible = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(label).type(.caption).foregroundStyle(MColor.textMute)
            HStack(spacing: Space.sm) {
                Group {
                    if visible {
                        TextField(placeholder, text: $text).textContentType(newPassword ? .newPassword : .password)
                    } else {
                        SecureField(placeholder, text: $text).textContentType(newPassword ? .newPassword : .password)
                    }
                }
                .type(.bodyMd).foregroundStyle(MColor.text).tint(MColor.text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focused)
                Button { visible.toggle() } label: {
                    Image(systemName: visible ? "eye.slash" : "eye")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(MColor.textMute)
                        .frame(width: Dim.touch, height: Dim.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(visible ? "Hide password" : "Show password")
            }
            .padding(.leading, Space.md)
            .frame(height: Dim.input)
            .background(MColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(focused ? MColor.text : MColor.lineInput, lineWidth: 1))
            if let helper { Text(helper).type(.caption).foregroundStyle(MColor.textMute) }
        }
    }
}

struct PickerField: View {
    var label: String
    var value: String
    var placeholder = "Select"
    var trailing = "chevron.down"
    var highlighted = false
    var action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(label).type(.caption).foregroundStyle(MColor.textMute)
            Button(action: action) {
                HStack {
                    Text(value.isEmpty ? placeholder : value).type(.bodyMd).foregroundStyle(value.isEmpty ? MColor.textMute : MColor.text)
                    Spacer()
                    Image(systemName: trailing).font(.system(size: 14)).foregroundStyle(MColor.textMute)
                }
                .padding(.horizontal, Space.md)
                .frame(height: Dim.input)
                .background(MColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(highlighted ? MColor.accent : MColor.lineInput, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 10 Amount input (currency prefix, large right-aligned figure) + numeric keypad

struct AmountInput: View {
    var amount: Int
    var focused = true
    var label: String? = "Amount received"
    var error: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let label { Text(label).type(.caption).foregroundStyle(MColor.textMute) }
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Spacer(minLength: 0)
                Text("₹").type(.displayHero).foregroundStyle(MColor.accentText)
                Text(amount == 0 ? "0" : Fmt.inr(amount, symbol: false)).type(.displayHero).foregroundStyle(MColor.text).monospacedDigit()
                    .contentTransition(.numericText())
                if focused { Rectangle().fill(MColor.accent).frame(width: 1.5, height: 32).offset(y: 4) }
            }
            .padding(.horizontal, Space.lg)
            .frame(height: Dim.amountInput)
            .background(MColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(error != nil ? MColor.danger : (focused ? MColor.text : MColor.lineInput), lineWidth: 1))
            if let error { Text(error).type(.caption).foregroundStyle(MColor.danger) }
        }
    }
}

/// Amount fields open a large numeric keypad, never the alphanumeric keyboard (spec §5). Keys are 56 = primary button.
struct NumericKeypad: View {
    @Binding var amount: Int
    private let keys: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["00", "0", "⌫"]]
    var body: some View {
        VStack(spacing: Space.sm) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: Space.sm) {
                    ForEach(row, id: \.self) { k in
                        Button { tap(k) } label: {
                            Group {
                                if k == "⌫" { Image(systemName: "delete.left").font(.system(size: 18)) }
                                else { Text(k).type(.headingMd) }
                            }
                            .foregroundStyle(MColor.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: Dim.keypadKey)
                            .background(MColor.ground, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    private func tap(_ k: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy(duration: 0.15)) {
            if k == "⌫" { amount /= 10 }
            else if let d = Int(k) {
                let next = amount * (k == "00" ? 100 : 10) + d
                if next < 100_000_000 { amount = next }
            }
        }
    }
}

// MARK: - 11 List row (leading icon or avatar · two-line stack · trailing value or chevron)

struct ListRow<Leading: View, Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var subtitleColor: Color = MColor.textMute
    var selected = false
    var strongTitle = true
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.md) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title).type(strongTitle ? .bodyMdStrong : .bodyMd).foregroundStyle(MColor.text).lineLimit(1)
                if let subtitle { Text(subtitle).type(.caption).foregroundStyle(subtitleColor).lineLimit(1).minimumScaleFactor(0.85) }
            }
            .layoutPriority(1)
            Spacer(minLength: Space.sm)
            trailing
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: Dim.row)
        .background(selected ? MColor.surfaceSelected : Color.clear)
        .contentShape(Rectangle())
    }
}

struct Chevron: View {
    var body: some View { Image(systemName: "chevron.right").font(.system(size: 14, weight: .regular)).foregroundStyle(MColor.textMute) }
}

/// Icon tile used as list-row leading (B2 sections, C5 rows, E4 rows).
struct IconTile: View {
    var symbol: String
    var color: Color = MColor.textMute
    var body: some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .light)).foregroundStyle(color)
            .frame(width: Dim.avatar, height: Dim.avatar)
    }
}

/// Grouped rows in one card with hairline dividers.
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(MColor.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(MColor.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .elevation(1)
    }
}

struct Hairline: View {
    var inset: CGFloat = Space.lg
    var body: some View { Rectangle().fill(MColor.line).frame(height: 1).padding(.leading, inset) }
}

// MARK: - 12 Conflict banner (always actionable, never dismissible)

struct ConflictBanner: View {
    var text: String
    var actionTitle = "Resolve"
    var action: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 18, weight: .light)).foregroundStyle(MColor.danger).frame(width: Dim.icon, height: Dim.icon)
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(text).type(.bodyMd).foregroundStyle(MColor.text).fixedSize(horizontal: false, vertical: true)
                MButton(title: actionTitle, style: .tertiary, size: .compact, fullWidth: false, action: action).padding(.leading, -Space.lg)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MColor.dangerTint, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

/// Inline warning under a date field (B3 / E3): sentence + the conflicting events with their colour dots.
struct InlineConflictWarning: View {
    var sentence: String
    var events: [Event]
    var linkTitle: String?
    var link: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .top, spacing: Space.md) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 18, weight: .light)).foregroundStyle(MColor.danger).frame(width: Dim.icon, height: Dim.icon)
                Text(sentence).type(.bodyMd).foregroundStyle(MColor.text).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(events) { e in
                    HStack(spacing: Space.sm) {
                        Circle().fill(MColor.event(e.hue)).frame(width: Dim.dot, height: Dim.dot)
                        Text(e.name).type(.caption).foregroundStyle(MColor.text)
                        Text("\(Fmt.timeRange(e.start, e.end)) · \(e.crewAssigned) crew").type(.caption).foregroundStyle(MColor.textMute)
                    }
                }
            }
            .padding(.leading, Dim.icon + Space.md)
            if let linkTitle, let link {
                Button(action: link) { Text(linkTitle).type(.buttonSm).foregroundStyle(MColor.accentText) }
                    .buttonStyle(.plain).padding(.leading, Dim.icon + Space.md).padding(.top, Space.xs)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MColor.dangerTint, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - 13 Stepper

struct MStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...10_000
    var step = 10
    var body: some View {
        HStack(spacing: Space.md) {
            stepButton("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - step) }
            Text("\(value)").type(.headingMd).foregroundStyle(MColor.text).monospacedDigit().frame(minWidth: 48)
                .contentTransition(.numericText())
            stepButton("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
        }
    }
    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy(duration: 0.15)) { action() } } label: {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(enabled ? MColor.accentText : MColor.disabledText)
                .frame(width: Dim.touch, height: Dim.touch)
                .overlay(Circle().strokeBorder(enabled ? MColor.accentText : MColor.disabledText, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

// MARK: - 14 Segmented control (pill track, selected segment lifted)

struct SegmentedControl<T: Hashable & Identifiable>: View {
    var items: [T]
    var label: (T) -> String
    @Binding var selection: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = item }
                } label: {
                    Text(label(item))
                        .type(selection == item ? .bodyMdStrong : .bodyMd)
                        .foregroundStyle(selection == item ? MColor.text : MColor.textMute)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background {
                            if selection == item {
                                Capsule().fill(MColor.segmentSelected).elevation(1).matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(MColor.segmentTrack, in: Capsule())
    }
}

// MARK: - 17 Empty state (headline · supporting line · one action)

struct EmptyState: View {
    var headline: String
    var line: String
    var actionTitle: String? = nil
    var actionIcon: String? = nil
    var primary = false
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: Space.lg) {
            VStack(spacing: Space.xs) {
                Text(headline).type(.headingSm).foregroundStyle(MColor.text)
                Text(line).type(.bodyMd).foregroundStyle(MColor.textMute).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                MButton(title: actionTitle, icon: actionIcon, style: primary ? .primary : .secondary, size: .compact, fullWidth: false, action: action)
            }
        }
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 18 Toast (Liquid Glass capsule floating over the content layer)

struct ToastView: View {
    var toast: Toast
    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: symbol).font(.system(size: 16, weight: .regular)).foregroundStyle(tint)
            Text(toast.message).type(.bodyMd).foregroundStyle(MColor.text).lineLimit(2)
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, Space.xl)
    }
    private var symbol: String {
        switch toast.kind { case .success: "checkmark.circle"; case .error: "exclamationmark.circle"; case .info: "info.circle" }
    }
    private var tint: Color {
        switch toast.kind { case .success: MColor.accentText; case .error: MColor.toastError; case .info: MColor.textMute }
    }
}
