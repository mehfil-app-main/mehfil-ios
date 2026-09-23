import SwiftUI

// MARK: - Screen scaffold: ground, large header in content, compact title fades into the nav bar on scroll

struct ScreenScaffold<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    /// Large title in content (collections) vs compact centred nav title (single statement / form) — NOTES title rule.
    var largeTitle = true
    /// Hero screens (B2) draw their own header: no large title, nav title only once scrolled.
    var heroHeader = false
    /// Tab roots hide the navigation bar; a glass title chip floats in once the header scrolls away.
    var isRoot = false
    var spacing: CGFloat = Space.xl
    var bottomPadding: CGFloat = Space.xxl
    var headerTrailing: AnyView? = nil
    @ViewBuilder var content: Content
    @State private var collapsed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                if largeTitle && !heroHeader {
                    ScreenHeader(title: title, subtitle: subtitle, trailing: headerTrailing)
                }
                content
            }
            .padding(.horizontal, Dim.gutter)
            .padding(.top, isRoot ? Space.lg : (largeTitle ? Space.sm : Space.lg))
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(MColor.ground)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 44 } action: { _, new in
            withAnimation(.easeOut(duration: 0.18)) { collapsed = new }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(isRoot ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if !isRoot {
                ToolbarItem(placement: .principal) {
                    Text(title).type(.headingSm).foregroundStyle(MColor.text).opacity((largeTitle || heroHeader) ? (collapsed ? 1 : 0) : 1)
                }
            }
        }
        .overlay(alignment: .top) {
            if isRoot && collapsed {
                Text(title).type(.headingSm).foregroundStyle(MColor.text)
                    .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.top, Space.xs)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

struct ScreenHeader: View {
    var title: String
    var subtitle: String?
    var trailing: AnyView? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .center, spacing: Space.md) {
                Text(title).type(.displayMd).foregroundStyle(MColor.text)
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
            if let subtitle { Text(subtitle).type(.bodyMd).foregroundStyle(MColor.textMute).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionHeading: View {
    var title: String
    var trailing: String? = nil
    var trailingColor: Color = MColor.textMute
    var link: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).type(.caption).foregroundStyle(MColor.textMute)
            Spacer()
            if let trailing { Text(trailing).type(.caption).foregroundStyle(trailingColor) }
            if let link, let action {
                Button(action: action) { Text(link).type(.caption).foregroundStyle(MColor.accentText) }.buttonStyle(.plain)
            }
        }
    }
}

struct StatTile: View {
    var figure: String
    var label: String
    var figureColor: Color = MColor.text
    var action: (() -> Void)? = nil
    var body: some View {
        Button { action?() } label: {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(figure).type(.displayMd).foregroundStyle(figureColor).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(label).type(.caption).foregroundStyle(MColor.textMute).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
        .allowsHitTesting(action != nil)
    }
}

// MARK: - Docked action bar & floating action button (Liquid Glass control layer)

/// Bottom-docked primary action on Liquid Glass. Content scrolls under it; the bar floats above the safe area.
struct DockedBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, Dim.gutter)
            .padding(.top, Space.md)
            .padding(.bottom, Space.sm)
    }
}

extension View {
    func dockedActions<A: View>(@ViewBuilder _ actions: () -> A) -> some View {
        self.safeAreaBar(edge: .bottom) { DockedBar { actions() } }
    }
}

/// Round glass icon action for root-screen headers (search, overflow) — the same control the nav bar would render.
struct GlassIconButton: View {
    var symbol: String
    /// Spoken by VoiceOver. Required: without it the SF Symbol name is announced instead.
    var label: LocalizedStringKey
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(MColor.text).frame(width: Dim.touch, height: Dim.touch)
        }
        .buttonStyle(.glass)
        .clipShape(Circle())
        .accessibilityLabel(label)
    }
}

struct GlassMenuButton<Items: View>: View {
    @ViewBuilder var items: Items
    var body: some View {
        Menu { items } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .medium)).foregroundStyle(MColor.text).frame(width: Dim.touch, height: Dim.touch)
        }
        .buttonStyle(.glass)
        .clipShape(Circle())
    }
}

/// Floating "New event" action (B1). Glass, prominent, interactive.
struct FloatingAction: View {
    var title: String
    var icon = "plus"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                Text(title).type(.buttonMd)
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        }
        .buttonStyle(.glassProminent)
        .tint(MColor.accent)
    }
}

// MARK: - 03 Event card (date block · name · client · venue · chip · crew · colour edge)

struct EventCard: View {
    var event: Event
    var client: Client?
    var paymentState: PaymentState
    var conflicted = false
    var compact = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                RoundedRectangle(cornerRadius: 2).fill(MColor.event(event.hue)).frame(width: Dim.edge)
                if !compact {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Fmt.dayNum.string(from: event.start)).type(.displayMd).foregroundStyle(conflicted ? MColor.danger : MColor.text).monospacedDigit()
                        Text(Fmt.monthShort.string(from: event.start)).type(.caption).foregroundStyle(MColor.textMute)
                    }
                    .frame(width: 44, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(event.name).type(.headingSm).foregroundStyle(MColor.text).lineLimit(1)
                    if compact {
                        Text("\(Fmt.timeRange(event.start, event.end)) · \(event.venue.shortName)").type(.caption).foregroundStyle(MColor.textMute).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    } else {
                        if let client { Text(client.name).type(.bodyMd).foregroundStyle(MColor.textSecondary).lineLimit(1) }
                        Text("\(event.venue.compact) · \(Fmt.time.string(from: event.start))").type(.caption).foregroundStyle(MColor.textMute).lineLimit(1)
                        HStack(spacing: Space.md) {
                            StatusChip(kind: conflicted ? .conflict : ChipKind.from(paymentState))
                            HStack(spacing: Space.xs) {
                                Image(systemName: "person.2").font(.system(size: 12)).foregroundStyle(MColor.textMute)
                                Text("\(event.crewAssigned) crew").type(.caption).foregroundStyle(MColor.textMute)
                            }
                        }
                        .padding(.top, Space.xs)
                    }
                }
                Spacer(minLength: Space.sm)
                if compact { StatusChip(kind: conflicted ? .conflict : ChipKind.from(paymentState)) }
                Chevron()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(fill: conflicted ? MColor.dangerTint : MColor.surface)
        }
        .buttonStyle(PressableCardStyle())
    }
}

struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 04 Payment row (milestone · due · amount · status chip · optional trailing action)

struct PaymentRow: View {
    var milestone: Milestone
    var title: String? = nil          // defaults to milestone name; C1 uses the event name
    var subtitle: String
    var subtitleColor: Color = MColor.textMute
    var trailingAction: (() -> Void)? = nil
    var trailingSymbol = "paperplane"
    var action: (() -> Void)? = nil

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? milestone.name).type(.bodyMdStrong).foregroundStyle(MColor.text).lineLimit(1)
                    Text(subtitle).type(.caption).foregroundStyle(subtitleColor).lineLimit(1)
                }
                Spacer(minLength: Space.sm)
                VStack(alignment: .trailing, spacing: Space.xs) {
                    Money(milestone.amount)
                    StatusChip(kind: ChipKind.from(milestone.effectiveStatus))
                }
                if let trailingAction {
                    IconButton(symbol: trailingSymbol, label: "Send a reminder", action: trailingAction)
                        .padding(.trailing, -Space.sm)
                }
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
            .frame(minHeight: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(action != nil)
    }
}

// MARK: - 05 Calendar grid (7 columns · numerals · event indicators · plus-count)

struct CalendarGrid: View {
    var month: Date
    @Binding var selected: Date
    var eventsByDay: [Int: [Event]]
    var conflictDays: Set<Int>
    var today: Date = Cal.today

    private var days: [Date?] {
        let cal = Cal.calendar
        let comps = cal.dateComponents([.year, .month], from: month)
        let first = cal.date(from: comps)!
        let range = cal.range(of: .day, in: .month, for: first)!
        let leading = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        cells += range.map { cal.date(byAdding: .day, value: $0 - 1, to: first)! }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    var body: some View {
        VStack(spacing: Space.xs) {
            HStack(spacing: 0) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"].indices, id: \.self) { i in
                    Text(["S", "M", "T", "W", "T", "F", "S"][i]).type(.caption).foregroundStyle(MColor.textMute).frame(maxWidth: .infinity)
                }
            }
            let rows = days.chunked(into: 7)
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        if let d = rows[r][c] { cell(d) } else { Color.clear.frame(height: Dim.calendarCell).frame(maxWidth: .infinity) }
                    }
                }
            }
        }
    }

    private func cell(_ d: Date) -> some View {
        let day = Cal.day(d)
        let isSelected = Cal.sameDay(d, selected)
        let isToday = Cal.sameDay(d, today)
        let conflict = conflictDays.contains(day)
        let evs = eventsByDay[day] ?? []
        let past = d < Cal.startOfDay(today)
        return Button { withAnimation(.snappy(duration: 0.2)) { selected = d } } label: {
            VStack(spacing: 3) {
                Text("\(day)").type(.bodyTabular).monospacedDigit()
                    .foregroundStyle(isSelected ? MColor.textOnPrimary : (conflict ? MColor.danger : (past ? MColor.textMute : MColor.text)))
                    .frame(width: Dim.calendarNumeral, height: Dim.calendarNumeral)
                    .background(isSelected ? (conflict ? MColor.danger : MColor.accent) : Color.clear, in: Circle())
                    .overlay(Circle().strokeBorder(isToday && !isSelected ? MColor.accentText : Color.clear, lineWidth: 1))
                HStack(spacing: 2) {
                    ForEach(Array(evs.prefix(3).enumerated()), id: \.offset) { _, e in
                        Circle().fill(MColor.event(e.hue)).frame(width: 6, height: 6)
                    }
                    if evs.count > 3 { Text("+\(evs.count - 3)").type(.microCap).foregroundStyle(MColor.textMute) }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity).frame(height: Dim.calendarCell)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] { stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) } }
}

// MARK: - 06 Timeline strip (hour markers · blocks by start/duration · overlapping blocks side by side)

struct TimelineStrip: View {
    var events: [Event]
    var startHour: Double = 6
    var endHour: Double = 24
    var onTap: (Event) -> Void

    var body: some View {
        let hourH = Dim.timelineHour
        let total = CGFloat(endHour - startHour) * hourH
        HStack(alignment: .top, spacing: Space.sm) {
            // Gutter with hour labels
            VStack(spacing: 0) {
                ForEach(Array(stride(from: startHour, through: endHour, by: 1)), id: \.self) { h in
                    Text(String(format: "%02d:00", Int(h) % 24)).type(.caption).foregroundStyle(MColor.textMute).monospacedDigit()
                        .frame(height: hourH, alignment: .top)
                }
            }
            .frame(width: Dim.timelineGutter, alignment: .leading)
            .offset(y: -9)
            // Track with hour lines and positioned blocks
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(Array(stride(from: startHour, through: endHour, by: 1)), id: \.self) { _ in
                        Rectangle().fill(MColor.line).frame(height: 1).frame(height: hourH, alignment: .top)
                    }
                }
                GeometryReader { g in
                    let lanes = laneAssignments()
                    ForEach(events) { e in
                        let (lane, count) = lanes[e.id] ?? (0, 1)
                        let w = (g.size.width - CGFloat(count - 1) * Space.xs) / CGFloat(count)
                        let top = CGFloat(Cal.hour(e.start) - startHour) * hourH
                        let endH = Cal.hour(e.end) == 0 ? 24 : Cal.hour(e.end)
                        let h = CGFloat(endH - Cal.hour(e.start)) * hourH
                        block(e).frame(width: w, height: max(h, hourH)).offset(x: CGFloat(lane) * (w + Space.xs), y: top)
                    }
                }
            }
            .frame(height: total + 4)
        }
    }

    private func block(_ e: Event) -> some View {
        Button { onTap(e) } label: {
            HStack(alignment: .top, spacing: Space.sm) {
                RoundedRectangle(cornerRadius: 2).fill(MColor.event(e.hue)).frame(width: Dim.edge)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name).type(.bodyMdStrong).foregroundStyle(MColor.text).lineLimit(1)
                    Text("\(Fmt.timeRange(e.start, e.end)) · \(e.venue.short) · \(e.crewAssigned) crew").type(.caption).foregroundStyle(MColor.textMute)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.sm)
            }
            .padding(.horizontal, Space.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MColor.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(MColor.line, lineWidth: 1))
            .elevation(1)
        }
        .buttonStyle(PressableCardStyle())
    }

    /// Overlapping events share the row at half width (spec A3: the conflict is visible from the layout itself).
    private func laneAssignments() -> [String: (Int, Int)] {
        var result: [String: (Int, Int)] = [:]
        let sorted = events.sorted { $0.start < $1.start }
        var groups: [[Event]] = []
        for e in sorted {
            if var last = groups.last, last.contains(where: { $0.end > e.start }) { last.append(e); groups[groups.count - 1] = last }
            else { groups.append([e]) }
        }
        for g in groups {
            // Assign lanes greedily within the group.
            var laneEnds: [Date] = []
            var lanes: [String: Int] = [:]
            for e in g {
                if let i = laneEnds.firstIndex(where: { $0 <= e.start }) { laneEnds[i] = e.end; lanes[e.id] = i }
                else { laneEnds.append(e.end); lanes[e.id] = laneEnds.count - 1 }
            }
            for e in g { result[e.id] = (lanes[e.id] ?? 0, laneEnds.count) }
        }
        return result
    }
}

// MARK: - Date strip (D1 / D4 selector: seven days from today; conflict days in ruby)

struct DateStrip: View {
    @Binding var selected: Date
    var conflictDays: Set<Date>
    var start: Date = Cal.today
    var body: some View {
        HStack(spacing: Space.sm) {
            ForEach(0..<7, id: \.self) { i in
                let d = Cal.startOfDay(Cal.adding(i, .day, to: start))
                let sel = Cal.sameDay(d, selected)
                let conflict = conflictDays.contains(where: { Cal.sameDay($0, d) })
                Button { withAnimation(.snappy(duration: 0.2)) { selected = d } } label: {
                    VStack(spacing: 2) {
                        Text(Fmt.weekdayShort.string(from: d)).type(.microCap).foregroundStyle(sel ? MColor.textOnPrimary : MColor.textMute)
                        Text(Fmt.dayNum.string(from: d)).type(.bodyTabularStrong).monospacedDigit().foregroundStyle(sel ? MColor.textOnPrimary : (conflict ? MColor.danger : MColor.text))
                    }
                    .frame(maxWidth: .infinity).frame(height: Dim.touch)
                    .background(sel ? (conflict ? MColor.danger : MColor.accent) : MColor.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(sel ? Color.clear : MColor.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 15 Bottom sheet scaffold (grabber is native; title · subtitle · content · action bar)

struct SheetScaffold<Content: View, Actions: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(title).type(.headingMd).foregroundStyle(MColor.text)
                        if let subtitle { Text(subtitle).type(.caption).foregroundStyle(MColor.textMute) }
                    }
                    content
                }
                .padding(.horizontal, Space.xl).padding(.top, Space.xl).padding(.bottom, Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            actions.padding(.horizontal, Space.xl).padding(.bottom, Space.sm)
        }
        .background(MColor.surface)
        .presentationDragIndicator(.visible)
        .presentationBackground(MColor.surface)
    }
}

// MARK: - Client contact row (B2 / E2): avatar · name · phone · call and message actions

struct ContactRow: View {
    var client: Client
    var note: String
    var body: some View {
        HStack(spacing: Space.md) {
            Avatar(index: client.avatar, name: client.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(client.name).type(.bodyMdStrong).foregroundStyle(MColor.text)
                Text(note).type(.caption).foregroundStyle(MColor.textMute)
            }
            Spacer()
            circleAction("phone") { open("tel://\(Fmt.phoneDigits(client.phone))") }
            circleAction("bubble") { open("https://wa.me/\(Fmt.phoneDigits(client.phone))") }
        }
        .card(padding: Space.md)
    }
    private func circleAction(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(MColor.accentText)
                .frame(width: Dim.touch, height: Dim.touch)
                .overlay(Circle().strokeBorder(MColor.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
    private func open(_ s: String) { if let u = URL(string: s) { UIApplication.shared.open(u) } }
}
