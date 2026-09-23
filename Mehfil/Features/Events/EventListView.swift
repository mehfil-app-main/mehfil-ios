import SwiftUI

enum EventSegment: String, CaseIterable, Identifiable {
    case upcoming = "Upcoming", enquiry = "Enquiry", completed = "Completed"
    var id: String { rawValue }
}

/// B1 · Event list — segmented, grouped under month headers, floating create action.
struct EventListView: View {
    @Environment(AppStore.self) private var store
    @State private var segment: EventSegment = .upcoming
    @State private var searching = false
    @State private var query = ""

    private func matches(_ e: Event) -> Bool { query.isEmpty || e.name.localizedCaseInsensitiveContains(query) || e.venue.short.localizedCaseInsensitiveContains(query) || (store.client(for: e)?.name.localizedCaseInsensitiveContains(query) ?? false) }
    private var upcoming: [Event] { store.upcomingEvents.filter(matches) }
    private var completed: [Event] { store.completedEvents.filter(matches) }
    private var groups: [(String, [Event])] {
        let list = segment == .completed ? completed : upcoming
        var order: [String] = []; var dict: [String: [Event]] = [:]
        for e in list {
            let k = Fmt.monthYear.string(from: e.start)
            if dict[k] == nil { order.append(k) }
            dict[k, default: []].append(e)
        }
        return order.map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        ScreenScaffold(title: "Events", subtitle: upcoming.isEmpty ? "Nothing booked yet" : "\(upcoming.count) upcoming · \(Fmt.inr(upcoming.reduce(0) { $0 + $1.quoted })) booked", isRoot: true, spacing: Space.lg, bottomPadding: 96,
                       headerTrailing: AnyView(GlassIconButton(symbol: searching ? "xmark" : "magnifyingglass", label: searching ? "Close search" : "Search events") { withAnimation(.snappy(duration: 0.25)) { searching.toggle(); if !searching { query = "" } } })) {
            if searching {
                InputField(label: "Search", text: $query, placeholder: "Event, client or venue", trailing: "magnifyingglass")
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            SegmentedControl(items: EventSegment.allCases, label: \.rawValue, selection: $segment)

            switch segment {
            case .upcoming, .completed:
                if groups.isEmpty {
                    EmptyState(headline: segment == .upcoming ? "No events yet" : "Nothing completed yet",
                               line: segment == .upcoming ? "Bookings you create will appear here with their date, venue and balance." : "Events move here once you mark them completed.",
                               actionTitle: segment == .upcoming ? "Create event" : nil, actionIcon: "plus", primary: true) { store.push(.createEvent) }
                        .padding(.top, 120)
                } else {
                    ForEach(groups, id: \.0) { name, evs in
                        VStack(spacing: Space.md) {
                            SectionHeading(title: name, trailing: "\(evs.count) event\(evs.count == 1 ? "" : "s") · \(Fmt.inr(evs.reduce(0) { $0 + $1.quoted }))")
                            ForEach(evs) { e in
                                EventCard(event: e, client: store.client(for: e), paymentState: store.paymentState(for: e), conflicted: store.isConflicted(e)) { store.push(.eventDetail(e.id)) }
                            }
                        }
                    }
                }
            case .enquiry:
                enquiries
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if segment != .completed {
                FloatingAction(title: segment == .enquiry ? "New enquiry" : "New event") { store.push(segment == .enquiry ? .enquiry(nil) : .createEvent) }
                    .padding(.trailing, Dim.gutter).padding(.bottom, Space.lg)
            }
        }
    }

    private var enquiries: some View {
        let open = store.openEnquiries
        return VStack(spacing: Space.md) {
            if open.isEmpty {
                EmptyState(headline: "No open enquiries", line: "Log an enquiry the moment someone asks, and check their date against the calendar.",
                           actionTitle: "New enquiry", actionIcon: "plus", primary: true) { store.push(.enquiry(nil)) }
                    .padding(.top, 120)
            } else {
                SectionHeading(title: "Open", trailing: "\(open.count) enquir\(open.count == 1 ? "y" : "ies")")
                RowGroup {
                    ForEach(Array(open.enumerated()), id: \.element.id) { i, q in
                        if i > 0 { Hairline() }
                        Button { store.push(.enquiry(q.id)) } label: {
                            ListRow(title: q.name, subtitle: [q.source, q.date.map { Fmt.weekdayDayMonth.string(from: $0) }].compactMap { $0 }.joined(separator: " · ")) {
                                IconTile(symbol: "envelope")
                            } trailing: {
                                HStack(spacing: Space.sm) { Text(q.budget).type(.caption).foregroundStyle(MColor.textMute).lineLimit(1); Chevron() }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// B2 · Event detail — the hub for one event. Densest screen in the app.
struct EventDetailView: View {
    @Environment(AppStore.self) private var store
    var eventId: String
    @State private var paymentsExpanded = false
    @State private var recordSheet: Milestone?
    @State private var cancelConfirm = false
    @State private var holdsSheet = false
    @State private var changeSheet = false
    @State private var clientSheet = false

    var body: some View {
        if let e = store.event(eventId) {
            let client = store.client(for: e)
            let balance = store.balanceDue(for: e.id)
            let overdue = store.overdueAmount(for: e.id)
            let conflicted = store.isConflicted(e)
            let pending = store.pendingChangeRequest(for: e.id)
            ScreenScaffold(title: e.name, heroHeader: true, spacing: Space.lg) {
                // Hero
                HStack(alignment: .top, spacing: Space.md) {
                    RoundedRectangle(cornerRadius: 2).fill(MColor.event(e.hue)).frame(width: Dim.edge)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(e.name).type(.displayMd).foregroundStyle(MColor.text)
                        Text("\(Fmt.weekdayLong.string(from: e.start)) · \(Fmt.timeRange(e.start, e.end))").type(.bodyMd).foregroundStyle(MColor.textSecondary)
                        Text([e.venue.short, e.venue.hall].compactMap { $0 }.joined(separator: " · ")).type(.caption).foregroundStyle(MColor.textMute)
                        HStack(spacing: Space.sm) {
                            if e.status == .upcoming {
                                HStack(spacing: Space.xs) {
                                    Image(systemName: "clock").font(.system(size: 11))
                                    Text(Fmt.relativeDays(e.start).prefix(1).uppercased() + Fmt.relativeDays(e.start).dropFirst()).type(.caption)
                                }
                                .foregroundStyle(MColor.text).padding(.horizontal, 10).frame(height: 28)
                                .overlay(Capsule().strokeBorder(MColor.line, lineWidth: 1))
                            }
                            if conflicted { StatusChip(kind: .conflict) }
                            if e.status == .cancelled { StatusChip(kind: .cancelled) }
                            if e.status == .completed { StatusChip(kind: .confirmed) }
                        }
                        .padding(.top, Space.xs)
                    }
                }

                if let cr = pending, store.vendor?.notifyChanges ?? true {
                    Button { store.push(.changeRequest(cr.id)) } label: {
                        HStack(spacing: Space.md) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 18, weight: .light)).foregroundStyle(MColor.accentText).frame(width: Dim.icon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Change request from \(client?.name ?? "the client")").type(.bodyMdStrong).foregroundStyle(MColor.text)
                                Text("\(cr.summary) · \(cr.via), \(Fmt.weekdayDayMonthTime.string(from: cr.requestedAt)) · see what it moves").type(.caption).foregroundStyle(MColor.textMute)
                            }
                            Spacer(); Chevron()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).card(fill: MColor.accentTint)
                    }
                    .buttonStyle(PressableCardStyle())
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.md), GridItem(.flexible(), spacing: Space.md)], spacing: Space.md) {
                    StatTile(figure: "\(e.guests)", label: "Guests")
                    StatTile(figure: Fmt.inr(e.quoted), label: "Quoted")
                    StatTile(figure: "\(e.crewAssigned) of \(e.crewNeeded)", label: "Crew assigned")
                    StatTile(figure: Fmt.inr(balance), label: overdue > 0 ? "Balance due · \(Fmt.inr(overdue)) overdue" : "Balance due", figureColor: overdue > 0 ? MColor.danger : MColor.text)
                }

                RowGroup {
                    sectionRow(symbol: "creditcard", title: "Payments", summary: "\(Fmt.inr(store.collected(for: e.id))) of \(Fmt.inr(e.quoted))" + (overdue > 0 ? " · overdue" : ""), expanded: paymentsExpanded) {
                        withAnimation(.snappy(duration: 0.3)) { paymentsExpanded.toggle() }
                    }
                    if paymentsExpanded { paymentsBlock(e) }
                    Hairline()
                    sectionRow(symbol: "person.2", title: "Crew", summary: "\(e.crewAssigned) of \(e.crewNeeded) · \(crewNote(e) ?? "assigned")") { store.push(.assignCrew(e.id)) }
                    Hairline()
                    sectionRow(symbol: "shippingbox", title: "Inventory", summary: store.inventorySummary(for: e)) { holdsSheet = true }
                    Hairline()
                    sectionRow(symbol: "list.bullet.rectangle", title: "Runsheet", summary: store.runsheetSummary(for: e)) { store.push(.runsheet(e.id)) }
                }

                if let client {
                    Button { clientSheet = true } label: {
                        ContactRow(client: client, note: "\(client.phone.isEmpty ? "No phone" : client.phone) · \(client.isRepeat ? "repeat client" : "first event")")
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { store.push(.sharedPage(e.id)) } label: { Image(systemName: "square.and.arrow.up") }
                    Menu {
                        Button("Log change request", systemImage: "arrow.triangle.2.circlepath") { changeSheet = true }
                        Button("Expenses and margin", systemImage: "indianrupeesign") { store.push(.expenses(e.id)) }
                        Button("Set inventory holds", systemImage: "shippingbox") { holdsSheet = true }
                        if e.status == .upcoming { Button("Mark completed", systemImage: "checkmark.circle") { store.markCompleted(e.id) } }
                        Divider()
                        if e.status != .cancelled { Button("Cancel event", systemImage: "xmark.circle", role: .destructive) { cancelConfirm = true } }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
            .sheet(item: $recordSheet) { m in RecordPaymentSheet(milestone: m).presentationDetents([.large]) }
            .sheet(isPresented: $holdsSheet) { EventHoldsSheet(event: e) }
            .sheet(isPresented: $changeSheet) { LogChangeRequestSheet(event: e) { store.push(.changeRequest($0.id)) } }
            .sheet(isPresented: $clientSheet) { if let client { ClientSheet(client: client) } }
            .sheet(isPresented: $cancelConfirm) {
                // Destructive confirmation names the specific thing being destroyed (spec §5).
                SheetScaffold(title: "Cancel the \(e.name) on \(Fmt.dayMonthLong.string(from: e.start))?",
                              subtitle: "\(store.assignedCrew(for: e.id).count) crew bookings and the inventory holds are released. \(client?.name ?? "The client") is not notified automatically.") {
                    EmptyView()
                } actions: {
                    VStack(spacing: Space.sm) {
                        MButton(title: "Cancel the \(e.type.rawValue)", style: .destructive) { store.cancelEvent(e.id); cancelConfirm = false; store.pop() }
                        MButton(title: "Keep it", style: .tertiary, size: .compact) { cancelConfirm = false }
                    }
                }
                .presentationDetents([.medium])
            }
        } else {
            ContentUnavailableView("Event not found", systemImage: "calendar.badge.exclamationmark")
        }
    }

    private func crewNote(_ e: Event) -> String? {
        let others = store.events(on: e.start).filter { $0.id != e.id }
        guard !others.isEmpty else { return nil }
        if let m = store.crew.first(where: { m in m.bookings.contains(e.id) && m.bookings.contains { id in others.contains { $0.id == id } } }) { return "\(m.firstName)'s team conflicted" }
        return nil
    }

    private func sectionRow(symbol: String, title: String, summary: String, expanded: Bool? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ListRow(title: title, subtitle: summary) { IconTile(symbol: symbol) } trailing: {
                Image(systemName: "chevron.right").font(.system(size: 14)).foregroundStyle(MColor.textMute).rotationEffect(.degrees(expanded == true ? 90 : 0))
            }
        }
        .buttonStyle(.plain)
    }

    private func paymentsBlock(_ e: Event) -> some View {
        VStack(spacing: 0) {
            ForEach(store.milestones(for: e.id)) { m in
                Hairline()
                PaymentRow(milestone: m, subtitle: paymentSubtitle(m), subtitleColor: m.effectiveStatus == .overdue ? MColor.danger : MColor.textMute, action: { if m.isOpen { recordSheet = m } })
            }
            HStack(spacing: Space.md) {
                MButton(title: "Record payment", icon: "indianrupeesign", style: .secondary, size: .compact) {
                    if let next = store.milestones(for: e.id).first(where: \.isOpen) { recordSheet = next } else { store.push(.paymentSchedule(e.id)) }
                }
                Button { store.push(.paymentSchedule(e.id)) } label: { Text("Schedule").type(.buttonSm).foregroundStyle(MColor.accentText) }.buttonStyle(.plain)
            }
            .padding(Space.lg)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

func paymentSubtitle(_ m: Milestone) -> String {
    switch m.effectiveStatus {
    case .paid: return "Paid \(Fmt.weekdayDayMonth.string(from: m.paidOn ?? m.due))" + (m.method.map { " · \($0.label)" } ?? "") + (m.reference.map { " · ref \($0)" } ?? "")
    case .overdue: return "Due \(Fmt.weekdayDayMonth.string(from: m.due)) · \(Fmt.daysLate(m.due)) days late"
    case .pending: return "Due \(Fmt.weekdayDayMonth.string(from: m.due)) · \(Fmt.relativeDays(m.due))"
    }
}
