import SwiftUI

/// A1 · Home — answer "what do I need to worry about today" in under three seconds.
struct HomeView: View {
    @Environment(AppStore.self) private var store

    private var saturday: Date { Cal.nextSaturday }
    private var saturdayEvents: [Event] { store.events(on: saturday) }
    /// Home ranks urgency above chronology (NOTES Phase 2): a conflicted event leads.
    private var attention: Event? {
        saturdayEvents.first(where: { store.isConflicted($0) }) ?? store.upcomingEvents.first(where: { store.isConflicted($0) }) ?? store.upcomingEvents.first(where: { $0.start >= Cal.startOfDay(Cal.today) })
    }
    private var greeting: String {
        let h = Cal.calendar.component(.hour, from: Cal.today)
        return h < 12 ? "Good morning" : (h < 17 ? "Good afternoon" : "Good evening")
    }

    var body: some View {
        let v = store.vendor
        ScreenScaffold(title: "\(greeting), \(v?.ownerFirstName ?? "there")",
                       subtitle: "\(Fmt.weekdayLong.string(from: Cal.today)) · \(saturdayEvents.count == 0 ? "nothing" : "\(saturdayEvents.count) event\(saturdayEvents.count == 1 ? "" : "s")") this Saturday", isRoot: true,
                       headerTrailing: AnyView(GlassIconButton(symbol: "chart.bar", label: "Season summary") { store.push(.seasonSummary) })) {
            if let (a, b, m) = store.seasonConflict, v?.notifyConflicts ?? true {
                ConflictBanner(text: "\(a.name) and \(b.name) both need \(m.firstName)'s team on \(Fmt.weekdayDayMonth.string(from: a.start)).") {
                    store.push(.assignCrew(a.id), in: .team)
                }
            }

            receivables

            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeading(title: attention.map { "Needs attention · \(Fmt.weekdayShort.string(from: $0.start)), \(Fmt.relativeDays($0.start))" } ?? "Next up",
                               link: "Calendar") { store.push(.calendarMonth) }
                if let e = attention {
                    EventCard(event: e, client: store.client(for: e), paymentState: store.paymentState(for: e), conflicted: store.isConflicted(e)) { store.push(.eventDetail(e.id)) }
                    let others = store.events(on: e.start).filter { $0.id != e.id }
                    if !others.isEmpty {
                        Text("Also \(Fmt.weekdayShort.string(from: e.start)) · " + others.map { "\($0.name) \(Fmt.time.string(from: $0.start))" }.joined(separator: " · "))
                            .type(.caption).foregroundStyle(MColor.textMute).fixedSize(horizontal: false, vertical: true)
                    }
                } else if store.loaded {
                    EmptyState(headline: "No events booked", line: "Create your first event and Mehfil starts watching the dates, the money and the crew.",
                               actionTitle: "Create event", actionIcon: "plus", primary: true) { store.push(.createEvent, in: .events) }
                        .padding(.vertical, Space.xl)
                }
            }

            HStack(spacing: Space.md) {
                StatTile(figure: "\(store.events(inMonth: Cal.month(Cal.today), year: Cal.year(Cal.today)).count)", label: "Events this month") { store.selectedTab = .events }
                StatTile(figure: "\(store.crewOnDuty(Cal.today))", label: "Crew on duty today") { store.selectedTab = .team }
                StatTile(figure: "\(store.openEnquiries.count)", label: "Open enquiries") { store.selectedTab = .events }
            }
        }
    }

    private var receivables: some View {
        Button { store.selectedTab = .money } label: {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(store.totalOutstanding == 0 ? "Nothing outstanding" : "Outstanding across \(store.eventsWithOpenMoney) event\(store.eventsWithOpenMoney == 1 ? "" : "s")").type(.caption).foregroundStyle(MColor.textMute)
                    Text(Fmt.inr(store.totalOutstanding)).type(.displayHero).foregroundStyle(MColor.text)
                    if store.overdueTotal > 0 {
                        HStack(spacing: Space.xs) {
                            Image(systemName: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(MColor.danger)
                            Text("\(Fmt.inr(store.overdueTotal)) overdue · \(store.overdueSurnames)").type(.caption).foregroundStyle(MColor.danger)
                        }
                    } else {
                        Text("Nothing overdue").type(.caption).foregroundStyle(MColor.textMute)
                    }
                }
                Spacer()
                Chevron()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(PressableCardStyle())
    }
}

/// A2 · Calendar month — see the shape of the month.
struct CalendarMonthView: View {
    @Environment(AppStore.self) private var store
    @State private var month: Date = Cal.calendar.date(from: Cal.calendar.dateComponents([.year, .month], from: Cal.today))!
    @State private var selected: Date = Cal.startOfDay(Cal.today)

    private var monthEvents: [Event] { store.events(inMonth: Cal.month(month), year: Cal.year(month)) }
    private var byDay: [Int: [Event]] { Dictionary(grouping: monthEvents, by: { Cal.day($0.start) }) }
    private var conflictDays: Set<Int> { Set(monthEvents.filter { store.isConflicted($0) }.map { Cal.day($0.start) }) }
    private var dayEvents: [Event] { store.events(on: selected) }

    var body: some View {
        ScreenScaffold(title: Fmt.monthYear.string(from: month), subtitle: monthEvents.isEmpty ? "No events this month" : "\(monthEvents.count) event\(monthEvents.count == 1 ? "" : "s") · \(Fmt.inr(monthEvents.reduce(0) { $0 + $1.quoted })) booked", spacing: Space.lg) {
            CalendarGrid(month: month, selected: $selected, eventsByDay: byDay, conflictDays: conflictDays)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                    if v.translation.width < -30 { shift(1) } else if v.translation.width > 30 { shift(-1) }
                })

            SectionHeading(title: Fmt.weekdayLong.string(from: selected),
                           trailing: dayEvents.isEmpty ? "No events" : "\(dayEvents.count) events" + (store.conflicts(on: selected).isEmpty ? "" : " · overlap"),
                           link: dayEvents.isEmpty ? nil : "Timeline") { store.push(.dayDetail(selected)) }
                .padding(.top, Space.sm)

            if dayEvents.isEmpty {
                Text("Nothing booked on this day.").type(.bodyMd).foregroundStyle(MColor.textMute).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, Space.xl)
            } else {
                VStack(spacing: Space.md) {
                    ForEach(dayEvents) { e in
                        EventCard(event: e, client: store.client(for: e), paymentState: store.paymentState(for: e), conflicted: store.isConflicted(e), compact: true) { store.push(.eventDetail(e.id)) }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
        }
        .onAppear { if let first = store.events(on: Cal.nextSaturday).first, Cal.month(first.start) == Cal.month(month) { selected = first.day } }
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy(duration: 0.25)) {
            month = Cal.adding(n, .month, to: month)
            selected = Cal.calendar.date(from: Cal.calendar.dateComponents([.year, .month], from: month))!
        }
    }
}

/// A3 · Calendar day detail — overlapping commitments render side by side; the conflict is visible from the layout.
struct DayDetailView: View {
    @Environment(AppStore.self) private var store
    var day: Date

    var body: some View {
        let evs = store.events(on: day)
        let crew = evs.reduce(0) { $0 + $1.crewAssigned }
        let overlap = store.conflicts(on: day)
        ScreenScaffold(title: Fmt.weekdayLong.string(from: day),
                       subtitle: "\(evs.count) events · \(crew) crew" + (overlap.isEmpty ? "" : " · overlap from \(Fmt.time.string(from: overlap.map(\.start).max() ?? day))")) {
            if evs.isEmpty { EmptyState(headline: "Nothing on this day", line: "Pick another date from the calendar.").padding(.top, 120) }
            else { TimelineStrip(events: evs) { store.push(.eventDetail($0.id)) } }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Assign crew", systemImage: "person.2") { if let e = evs.first { store.push(.assignCrew(e.id), in: .team) } }
                    Button("Check inventory", systemImage: "shippingbox") { store.push(.inventory, in: .team) }
                } label: { Image(systemName: "ellipsis") }
            }
        }
    }
}

/// A4 · Season summary — the screen a vendor shows their spouse.
struct SeasonSummaryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let s = store.season
        let target = store.vendor?.seasonTarget ?? 0
        let pct = target == 0 ? 0 : Int((Double(s.booked) / Double(target) * 100).rounded())
        ScreenScaffold(title: s.label, subtitle: "October to February · \(s.count) events booked", spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Booked this season").type(.caption).foregroundStyle(MColor.textMute)
                Text(Fmt.inr(s.booked)).type(.displayHero).foregroundStyle(MColor.text)
                if target > 0 {
                    ProgressBar(fraction: Double(s.booked) / Double(target)).padding(.top, Space.xs)
                    Text("\(pct)% of the \(Fmt.inr(target)) target · \(Fmt.inr(max(0, target - s.booked))) to go").type(.caption).foregroundStyle(MColor.textMute)
                } else {
                    Text("Set a season target in Profile → Business details.").type(.caption).foregroundStyle(MColor.textMute)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).card()

            VStack(alignment: .leading, spacing: Space.md) {
                Text("Booked value by month").type(.caption).foregroundStyle(MColor.textMute)
                MonthBars(months: s.months)
            }
            .frame(maxWidth: .infinity, alignment: .leading).card()

            HStack(spacing: Space.md) {
                StatTile(figure: "\(s.count)", label: "Events booked")
                StatTile(figure: Fmt.inr(s.count == 0 ? 0 : s.booked / s.count / 100 * 100), label: "Average ticket")
            }

            if let last = store.vendor?.lastSeasonBooked, last > 0 {
                let delta = Int((Double(s.booked - last) / Double(last) * 100).rounded())
                HStack(alignment: .top, spacing: Space.md) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 18, weight: .light)).foregroundStyle(MColor.accentText).frame(width: Dim.icon, height: Dim.icon)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("\(delta >= 0 ? "+" : "")\(delta)%").type(.displayMd).foregroundStyle(MColor.text)
                        Text("against last season").type(.bodyMd).foregroundStyle(MColor.text)
                        Text("\(Fmt.inr(last)) across \(store.vendor?.lastSeasonEvents ?? 0) events by this point last year").type(.caption).foregroundStyle(MColor.textMute)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()
            }
        }
    }
}

/// Single-series bars in accent; lakh notation because full grouping does not fit a 60pt column (NOTES).
struct MonthBars: View {
    var months: [(String, Int)]
    var body: some View {
        let maxV = max(1, months.map(\.1).max() ?? 1)
        HStack(alignment: .bottom, spacing: Space.md) {
            ForEach(months.indices, id: \.self) { i in
                let (name, v) = months[i]
                VStack(spacing: Space.xs) {
                    if v > 0 { Text(Fmt.lakh(v)).type(.caption).foregroundStyle(MColor.text).monospacedDigit() }
                    else { Text("—").type(.caption).foregroundStyle(MColor.textMute) }
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(v > 0 ? MColor.accent : MColor.line)
                        .frame(height: v > 0 ? max(4, Dim.chart * CGFloat(v) / CGFloat(maxV)) : 2)
                    Text(name).type(.caption).foregroundStyle(MColor.textMute)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Dim.chart + 48, alignment: .bottom)
    }
}
