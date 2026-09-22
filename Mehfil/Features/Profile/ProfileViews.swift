import SwiftUI

/// E4 · Profile and settings — deliberately short.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.colorScheme) private var scheme
    @State private var appearanceSheet = false
    @State private var businessSheet = false
    @State private var paymentSheet = false
    @State private var notifySheet = false

    var body: some View {
        let v = store.vendor
        let repeatCount = store.clients.filter(\.isRepeat).count
        ScreenScaffold(title: "Profile", subtitle: [v?.businessName, v?.area.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) }].compactMap { $0 }.joined(separator: " · "), isRoot: true, spacing: Space.lg) {
            Button { businessSheet = true } label: {
                HStack(spacing: Space.md) {
                    Text(v?.monogram ?? "M").type(.headingLg).foregroundStyle(MColor.emphasisText)
                        .frame(width: 48, height: 48).background(MColor.emphasisBg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v?.businessName ?? "Your business").type(.headingSm).foregroundStyle(MColor.text)
                        Text([v?.ownerName, v?.area.nilIfEmpty, v?.since.nilIfEmpty].compactMap { $0 }.joined(separator: " · ")).type(.caption).foregroundStyle(MColor.textMute)
                    }
                    Spacer()
                    Chevron()
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()
            }
            .buttonStyle(PressableCardStyle())

            RowGroup {
                row("person.2", "Team", "\(store.crew.count) crew · \(store.crew.filter { $0.role == .coordinator }.count) coordinators") { store.push(.crewList) }
                Hairline(inset: 68)
                row("person", "Clients", store.clients.isEmpty ? "None yet" : "\(store.clients.count) clients · \(repeatCount) repeat") { store.push(.clients) }
                Hairline(inset: 68)
                row("square.stack.3d.up", "Package templates", store.packages.isEmpty ? "None yet" : "\(store.packages.count) templates · from \(Fmt.inr(store.packages.map(\.price).min() ?? 0))") { store.push(.packages) }
                Hairline(inset: 68)
                row("creditcard", "Payment details", [v?.upi.nilIfEmpty.map { "UPI \($0)" }, v?.bankLabel.nilIfEmpty].compactMap { $0 }.joined(separator: " · ").nilIfEmpty ?? "Add your UPI ID") { paymentSheet = true }
                Hairline(inset: 68)
                row("sun.max", "Appearance", store.appearance == .system ? "\(scheme == .dark ? "Dark" : "Light") · follows system" : store.appearance.label) { appearanceSheet = true }
                Hairline(inset: 68)
                row("bell", "Notifications", notifySummary(v)) { notifySheet = true }
                Hairline(inset: 68)
                row(auth.isCloud ? "icloud" : "iphone", "Account", auth.account.map { "\($0.providerLabel)" + ($0.email.map { " · \($0)" } ?? "") } ?? "") { store.push(.account) }
            }
            Text("Mehfil \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                .type(.caption).foregroundStyle(MColor.textMute).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $appearanceSheet) {
            SheetScaffold(title: "Appearance") {
                RowGroup {
                    ForEach(Array(Appearance.allCases.enumerated()), id: \.element.id) { i, a in
                        if i > 0 { Hairline() }
                        Button { store.appearance = a } label: {
                            ListRow(title: a.label, selected: store.appearance == a) { EmptyView() } trailing: { if store.appearance == a { Image(systemName: "checkmark").foregroundStyle(MColor.accentText) } }
                        }.buttonStyle(.plain)
                    }
                }
            } actions: { MButton(title: "Done") { appearanceSheet = false } }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $businessSheet) { BusinessProfileSheet() }
        .sheet(isPresented: $paymentSheet) { PaymentDetailsSheet() }
        .sheet(isPresented: $notifySheet) { NotificationsSheet() }
    }

    private func notifySummary(_ v: VendorProfile?) -> String {
        guard let v else { return "" }
        let on = [v.notifyPayments ? "Payments" : nil, v.notifyConflicts ? "conflicts" : nil, v.notifyChanges ? "change requests" : nil].compactMap { $0 }
        return on.isEmpty ? "All off" : on.joined(separator: ", ")
    }
    private func row(_ symbol: String, _ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { ListRow(title: title, subtitle: subtitle) { IconTile(symbol: symbol) } trailing: { Chevron() } }.buttonStyle(.plain)
    }
}

/// Package templates — the menu the create-event flow picks from.
struct PackagesView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: Package?
    @State private var adding = false

    var body: some View {
        ScreenScaffold(title: "Package templates", subtitle: store.packages.isEmpty ? "None yet" : "\(store.packages.count) templates", spacing: Space.lg, bottomPadding: 100) {
            if store.packages.isEmpty {
                EmptyState(headline: "No packages yet", line: "Templates make quoting a new event a three-tap job.", actionTitle: "New package", actionIcon: "plus", primary: true) { adding = true }.padding(.top, 120)
            } else {
                RowGroup {
                    ForEach(Array(store.packages.enumerated()), id: \.element.id) { i, p in
                        if i > 0 { Hairline() }
                        Button { editing = p } label: {
                            ListRow(title: p.name, subtitle: p.detail) { EmptyView() } trailing: { HStack(spacing: Space.sm) { Money(p.price); Chevron() } }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .dockedActions { MButton(title: "New package", icon: "plus", style: .secondary) { adding = true } }
        .sheet(isPresented: $adding) { PackageSheet(existing: nil) }
        .sheet(item: $editing) { PackageSheet(existing: $0) }
    }
}

/// E1 · Client list — search, rows with event count and lifetime value; repeat clients carry a marker.
struct ClientListView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var editing: Client?

    var body: some View {
        let list = store.clients.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.phone.contains(query) }
            .sorted { store.stats(for: $0).lifetimeValue > store.stats(for: $1).lifetimeValue }
        let lifetime = store.lifetimeValue
        let repeatCount = store.clients.filter(\.isRepeat).count
        ScreenScaffold(title: "Clients", subtitle: store.clients.isEmpty ? "No clients yet" : "\(store.clients.count) clients · \(Fmt.inr(lifetime)) lifetime", spacing: Space.lg) {
            if store.clients.isEmpty {
                EmptyState(headline: "No clients yet", line: "Each client is added with their first event or enquiry.", actionTitle: "Create event", actionIcon: "plus", primary: true) { store.push(.createEvent, in: .events) }
                    .padding(.top, 120)
            } else {
                HStack(spacing: Space.md) {
                    StatTile(figure: "\(repeatCount) of \(store.clients.count)", label: "Repeat clients")
                    StatTile(figure: Fmt.inr(store.clients.isEmpty ? 0 : lifetime / store.clients.count / 100 * 100), label: "Average lifetime value")
                }
                RowGroup {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { Hairline(inset: 68) }
                        let s = store.stats(for: c)
                        Button {
                            if let e = store.upcomingEvents.first(where: { $0.clientId == c.id }) ?? store.events.first(where: { $0.clientId == c.id }) { store.push(.eventDetail(e.id)) } else { editing = c }
                        } label: {
                            ListRow(title: c.name, subtitle: "\(s.eventCount) event\(s.eventCount == 1 ? "" : "s")" + (s.nextEventDate.map { " · next \(Fmt.dayMonth.string(from: $0))" } ?? "")) {
                                Avatar(index: c.avatar, name: c.name)
                            } trailing: {
                                HStack(spacing: Space.sm) {
                                    if c.isRepeat { Image(systemName: "star").font(.system(size: 11)).foregroundStyle(MColor.accentText) }
                                    Money(s.lifetimeValue)
                                    Chevron()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Edit client", systemImage: "pencil") { editing = c } }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search by name or phone")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { store.push(.enquiry(nil)) } label: { Image(systemName: "plus") } } }
        .sheet(item: $editing) { ClientSheet(client: $0) }
    }
}

/// E3 · Enquiry intake — conflict check on the tentative date, convert to event.
struct EnquiryIntakeView: View {
    @Environment(AppStore.self) private var store
    var enquiryId: String?
    @State private var name = ""
    @State private var phone = ""
    @State private var source = ""
    @State private var budget = ""
    @State private var date: Date? = nil
    @State private var guests = 200
    @State private var notes = ""
    @State private var showDate = false
    @State private var showSource = false
    @State private var showBudget = false
    @State private var loaded = false
    @FocusState private var notesFocused: Bool

    private var conflicts: [Event] { date.map { store.events(on: $0) } ?? [] }
    private var existing: Enquiry? { enquiryId.flatMap { store.enquiry($0) } }

    var body: some View {
        ScreenScaffold(title: existing == nil ? "New enquiry" : "Enquiry", largeTitle: false, spacing: Space.lg, bottomPadding: 100) {
            InputField(label: "Name", text: $name, placeholder: "Who is asking")
            PhoneField(text: $phone)
            PickerField(label: "Source", value: source) { showSource = true }
            PickerField(label: "Budget range", value: budget) { showBudget = true }
            PickerField(label: "Tentative date", value: date.map { Fmt.weekdayLongYear.string(from: $0) } ?? "", placeholder: "Pick a date", trailing: "calendar", highlighted: date != nil) { showDate = true }
            if let d = date, !conflicts.isEmpty {
                let c = conflicts[0]
                InlineConflictWarning(sentence: conflicts.count == 1 ? "\(c.name) runs \(Cal.hour(c.start) >= 17 ? "that evening" : "that day") at \(c.venue.name) with \(c.crewAssigned) crew." : "\(conflicts.count) events already run on \(Fmt.dayMonth.string(from: d)).",
                                      events: conflicts, linkTitle: "See \(Fmt.dayMonth.string(from: d)) timeline") { store.push(.dayDetail(d)) }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Guest estimate").type(.bodyMd).foregroundStyle(MColor.text)
                    Text("Rough is fine").type(.caption).foregroundStyle(MColor.textMute)
                }
                Spacer()
                MStepper(value: $guests, range: 10...5000, step: 10)
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Notes").type(.caption).foregroundStyle(MColor.textMute)
                TextEditor(text: $notes).type(.bodyMd).foregroundStyle(MColor.text).scrollContentBackground(.hidden).focused($notesFocused)
                    .frame(minHeight: 72).padding(Space.sm)
                    .background(MColor.surface, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(notesFocused ? MColor.accent : MColor.lineInput, lineWidth: 1))
            }
            if let existing, existing.status == .open {
                MButton(title: "Close enquiry", style: .tertiary, size: .compact) { store.closeEnquiry(existing.id); store.pop() }
            }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Save") { save(); store.pop() }.type(.buttonSm).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) } }
        .dockedActions {
            MButton(title: "Convert to event") {
                let id = save()
                store.draft = EventDraft(clientName: name.trimmingCharacters(in: .whitespaces), phone: phone, type: nil, date: date, venue: "", guests: guests, packageIds: [], quoted: 0, fromEnquiryId: id)
                store.pop(); store.push(.createEvent, in: .events)
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear {
            guard !loaded else { return }; loaded = true
            if let q = existing { name = q.name; phone = q.phone; source = q.source; budget = q.budget; date = q.date; guests = q.guests; notes = q.notes }
            else { source = SampleSeason.enquirySources[0]; budget = SampleSeason.budgetRanges[2] }
        }
        .sheet(isPresented: $showDate) {
            SheetScaffold(title: "Tentative date", subtitle: "Conflicts are checked as soon as you pick.") {
                DatePicker("Date", selection: Binding(get: { date ?? Cal.nextSaturday }, set: { date = Cal.startOfDay($0) }), in: Cal.startOfDay(Cal.today)..., displayedComponents: .date)
                    .datePickerStyle(.graphical).tint(MColor.accent).environment(\.calendar, Cal.calendar)
            } actions: { MButton(title: "Done") { if date == nil { date = Cal.nextSaturday }; showDate = false } }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showSource) { choiceSheet("Source", SampleSeason.enquirySources, $source, $showSource) }
        .sheet(isPresented: $showBudget) { choiceSheet("Budget range", SampleSeason.budgetRanges, $budget, $showBudget) }
    }

    @discardableResult
    private func save() -> String {
        let q = Enquiry(id: existing?.id ?? Cal.newId(), name: name.trimmingCharacters(in: .whitespaces), phone: phone, source: source, budget: budget, date: date, guests: guests, notes: notes,
                        status: existing?.status ?? .open, createdAt: existing?.createdAt ?? Cal.today)
        store.saveEnquiry(q)
        return q.id
    }

    private func choiceSheet(_ title: String, _ options: [String], _ value: Binding<String>, _ shown: Binding<Bool>) -> some View {
        SheetScaffold(title: title) {
            RowGroup {
                ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                    if i > 0 { Hairline() }
                    Button { value.wrappedValue = o; shown.wrappedValue = false } label: {
                        ListRow(title: o, selected: value.wrappedValue == o) { EmptyView() } trailing: { if value.wrappedValue == o { Image(systemName: "checkmark").foregroundStyle(MColor.accentText) } }
                    }.buttonStyle(.plain)
                }
            }
        } actions: { EmptyView() }
        .presentationDetents([.medium])
    }
}

/// E2 · Shared event page — the read-only view the vendor sends the client. Cream ground, the only gradient mesh,
/// no chips or tiles from the vendor side. Always light: it is the client's page (NOTES Phase 6).
struct SharedEventPageView: View {
    @Environment(AppStore.self) private var store
    var eventId: String

    var body: some View {
        if let e = store.event(eventId), let client = store.client(for: e), let v = store.vendor {
            let collected = store.collected(for: e.id)
            let due = store.milestones(for: e.id).filter(\.isOpen)
            let holds = store.inventory.compactMap { item -> (String, Int)? in item.holds.first { $0.eventId == e.id }.map { (item.name, $0.qty) } }
            let packages = store.packages
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("\(v.businessName.uppercased()) · FOR THE \(e.surname.uppercased()) FAMILY").type(.microCap).foregroundStyle(Palette.muted).tracking(0.6)
                        Text(e.name).type(.displayLg).foregroundStyle(Palette.ink)
                        Text("\(Fmt.weekdayLong.string(from: e.start)) · from \(Fmt.time.string(from: e.start))").type(.bodyLg).foregroundStyle(Palette.ink)
                        Text([e.venue.short, e.venue.hall].compactMap { $0 }.joined(separator: " · ")).type(.bodyLg).foregroundStyle(Palette.body)
                    }
                    .padding(.top, Space.lg)

                    section("What we are bringing") {
                        if holds.isEmpty && packages.isEmpty { line("Full décor as quoted", "") }
                        ForEach(packages.prefix(4), id: \.id) { line($0.name, $0.detail) }
                        ForEach(holds, id: \.0) { line("\($0.1) \($0.0.lowercased())", "") }
                        line("Seating for \(e.guests) guests", "")
                    }
                    section("On the day") {
                        line("Setup begins", Fmt.time.string(from: Cal.adding(-8, .hour, to: e.start)))
                        line("Venue ready for your walkthrough", Fmt.time.string(from: Cal.adding(-30, .minute, to: e.start)))
                        line("Guests arrive", Fmt.time.string(from: e.start))
                        line("Pack-down", Fmt.time.string(from: e.end))
                    }

                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Received").type(.bodyLg).foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(Fmt.inr(collected)) of \(Fmt.inr(e.quoted))").type(.bodyLg).foregroundStyle(Palette.ink).monospacedDigit()
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(Palette.ink.opacity(0.12))
                                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(Palette.ink).frame(width: g.size.width * CGFloat(collected) / CGFloat(max(1, e.quoted)))
                            }
                        }.frame(height: 4)
                        Text((due.map { "\(Fmt.inr($0.amount)) \($0.due <= Cal.today ? "due now" : ($0.kind == .balance ? "on the day" : "by \(Fmt.dayMonth.string(from: $0.due))"))" }.joined(separator: " · ").nilIfEmpty ?? "Fully paid — thank you") + (v.upi.isEmpty ? "" : " · UPI \(v.upi)"))
                            .type(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Space.lg).background(Palette.surfaceSoft, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                    HStack(spacing: Space.sm) {
                        ForEach(1...3, id: \.self) { i in
                            Image("mood-\(i)").resizable().aspectRatio(4/3, contentMode: .fill).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        }
                    }

                    HStack(spacing: Space.md) {
                        Text(v.monogram).type(.headingSm).foregroundStyle(Palette.onDark).frame(width: 36, height: 36).background(Palette.ink, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(v.ownerName) · \(v.businessName)").type(.bodyMdStrong).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.8)
                            Text([v.phone.nilIfEmpty, v.area.nilIfEmpty].compactMap { $0 }.joined(separator: " · ")).type(.caption).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .layoutPriority(1)
                        Spacer(minLength: Space.sm)
                        Button {
                            if let u = URL(string: "https://wa.me/\(Fmt.phoneDigits(v.phone))") { UIApplication.shared.open(u) }
                        } label: {
                            HStack(spacing: Space.xs) { Image(systemName: "bubble").font(.system(size: 14)); Text("Chat").type(.buttonSm) }
                                .foregroundStyle(Palette.ink).padding(.horizontal, Space.md).frame(height: 40).overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.ink, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                    .padding(.bottom, Space.xl)
                }
                .padding(.horizontal, Space.xl)
            }
            .background(mesh.ignoresSafeArea())
            .environment(\.colorScheme, .light)
            .toolbarColorScheme(.light, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText(e, client: client, vendor: v, collected: collected, due: due), subject: Text(e.name)) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }

    private func shareText(_ e: Event, client: Client, vendor v: VendorProfile, collected: Int, due: [Milestone]) -> String {
        var s = "\(v.businessName) · for the \(e.surname) family\n\n\(e.name)\n\(Fmt.weekdayLong.string(from: e.start)) · from \(Fmt.time.string(from: e.start))\n\([e.venue.short, e.venue.hall].compactMap { $0 }.joined(separator: " · "))\n"
        s += "\nReceived \(Fmt.inr(collected)) of \(Fmt.inr(e.quoted))"
        if !due.isEmpty { s += "\n" + due.map { "\(Fmt.inr($0.amount)) \($0.due <= Cal.today ? "due now" : "by \(Fmt.dayMonth.string(from: $0.due))")" }.joined(separator: " · ") }
        if !v.upi.isEmpty { s += "\nUPI \(v.upi)" }
        s += "\n\n\(v.ownerName) · \(v.phone)"
        return s
    }

    /// The gradient mesh was the previous skin's signature and has no Airbnb equivalent: an Airbnb listing page
    /// is a white canvas where the photographs do the work. Still light in the dark wall on purpose — this is
    /// the page a client opens from a WhatsApp link.
    private var mesh: some View { Palette.canvas }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title).type(.headingSm).foregroundStyle(Palette.ink)
            content()
        }
    }
    private func line(_ l: String, _ r: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(l).type(.bodyLg).foregroundStyle(Palette.ink)
            Spacer()
            Text(r).type(.bodyLg).foregroundStyle(Palette.muted).monospacedDigit()
        }
    }
}
