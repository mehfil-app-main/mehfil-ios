import SwiftUI

/// B3 · Create event step 1 (client and date, inline conflict check) and B4 · step 2 (venue and pricing).
struct CreateEventView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var step = 1
    @State private var showDate = false
    @State private var showType = false
    @State private var showAmount = false

    private var draft: Binding<EventDraft> { Binding(get: { store.draft }, set: { store.draft = $0 }) }
    private var conflicts: [Event] { store.draft.date.map { store.events(on: $0) } ?? [] }
    private var packageTotal: Int { store.packages.filter { store.draft.packageIds.contains($0.id) }.reduce(0) { $0 + $1.price } }
    private var step1Valid: Bool { !store.draft.clientName.trimmingCharacters(in: .whitespaces).isEmpty && store.draft.type != nil && store.draft.date != nil }
    private var step2Valid: Bool { !store.draft.venue.trimmingCharacters(in: .whitespaces).isEmpty && store.draft.quoted > 0 }

    var body: some View {
        ScreenScaffold(title: "New event", largeTitle: false, spacing: Space.lg, bottomPadding: step == 2 ? 120 : Space.xxl) {
            progress
            if step == 1 { stepOne } else { stepTwo }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save draft") { store.show(.success, "Draft saved"); dismiss() }.type(.buttonSm)
            }
        }
        .dockedActions {
            VStack(spacing: Space.sm) {
                if step == 2 { runningTotal }
                if step == 1 {
                    MButton(title: "Continue") { withAnimation(.snappy(duration: 0.3)) { step = 2 } }.disabled(!step1Valid)
                } else {
                    MButton(title: "Create event") {
                        if let e = store.createEvent(from: store.draft) { store.pop(); store.push(.eventDetail(e.id)) }
                    }.disabled(!step2Valid)
                }
            }
        }
        .sheet(isPresented: $showDate) { dateSheet }
        .sheet(isPresented: $showType) { typeSheet }
        .sheet(isPresented: $showAmount) { amountSheet }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Step \(step) of 2 · \(step == 1 ? "Client and date" : "Venue and pricing")").type(.caption).foregroundStyle(MColor.textMute)
            HStack(spacing: Space.xs) {
                Capsule().fill(MColor.accent).frame(height: 3)
                Capsule().fill(step == 2 ? MColor.accent : MColor.line).frame(height: 3)
            }
        }
    }

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            InputField(label: "Client name", text: draft.clientName, placeholder: "Surname the family goes by")
            PhoneField(text: draft.phone)
            PickerField(label: "Event type", value: store.draft.type?.label ?? "") { showType = true }
            PickerField(label: "Date", value: store.draft.date.map { Fmt.weekdayLongYear.string(from: $0) } ?? "", placeholder: "Pick a date", trailing: "calendar", highlighted: store.draft.date != nil) { showDate = true }
            // Conflict check fires on date selection, not on submission (spec B3).
            if let d = store.draft.date, !conflicts.isEmpty {
                let chairs = store.inventory.first(where: { $0.name.localizedCaseInsensitiveContains("chair") }).map { "\($0.committed(on: d)) of \($0.total) \($0.unit)" }
                let when = conflicts.allSatisfy { Cal.hour($0.start) >= 17 } ? "that evening" : "that day"
                let words = ["", "One", "Two", "Three", "Four", "Five"]
                let lead = store.crew.first { m in m.isLead && m.bookings.contains { id in conflicts.contains { $0.id == id } } }
                let committed = [lead.map { "\($0.firstName)'s team" }, chairs].compactMap { $0 }.joined(separator: " and ")
                InlineConflictWarning(sentence: (conflicts.count == 1 ? "\(conflicts[0].name) already runs \(when)." : "\(conflicts.count < words.count ? words[conflicts.count] : "\(conflicts.count)") events already run \(when).") + (committed.isEmpty ? "" : " \(committed) are committed."),
                                      events: conflicts, linkTitle: "See \(Fmt.dayMonth.string(from: d)) timeline") { store.push(.dayDetail(d)) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            InputField(label: "Venue", text: draft.venue, placeholder: "Venue, area", trailing: "mappin.and.ellipse")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Guest count").type(.bodyMd).foregroundStyle(MColor.text)
                    Text("Catering by the venue").type(.caption).foregroundStyle(MColor.textMute)
                }
                Spacer()
                MStepper(value: draft.guests, range: 10...5000, step: 10)
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Packages · select all that apply").type(.caption).foregroundStyle(MColor.textMute)
                if store.packages.isEmpty {
                    Text("No package templates yet — add them in Profile.").type(.caption).foregroundStyle(MColor.textMute)
                } else {
                    RowGroup {
                        ForEach(Array(store.packages.enumerated()), id: \.element.id) { i, p in
                            if i > 0 { Hairline() }
                            let on = store.draft.packageIds.contains(p.id)
                            Button {
                                withAnimation(.snappy(duration: 0.2)) { if on { store.draft.packageIds.remove(p.id) } else { store.draft.packageIds.insert(p.id) } }
                            } label: {
                                ListRow(title: p.name, subtitle: "\(Fmt.inr(p.price)) · \(p.detail)", selected: on) { EmptyView() } trailing: {
                                    Image(systemName: on ? "checkmark" : "circle").font(.system(size: 16)).foregroundStyle(on ? MColor.accentText : MColor.line)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Button { showAmount = true } label: { AmountInput(amount: store.draft.quoted, focused: false, label: "Quoted amount") }.buttonStyle(.plain)
        }
    }

    /// Live running total docked above the action bar (spec B4).
    private var runningTotal: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Running total · \(store.draft.packageIds.count) packages").type(.caption).foregroundStyle(MColor.textMute)
                Money(packageTotal, .bodyMdStrong)
            }
            Spacer()
            if store.draft.quoted > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Fmt.inr(store.draft.quoted - packageTotal)) margin").type(.caption).foregroundStyle(store.draft.quoted >= packageTotal ? MColor.textMute : MColor.danger)
                    Text("on \(Fmt.inr(store.draft.quoted)) quoted").type(.caption).foregroundStyle(MColor.textMute)
                }
            }
        }
        .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var dateSheet: some View {
        SheetScaffold(title: "Event date", subtitle: "Conflicts are checked as soon as you pick.") {
            DatePicker("Date", selection: Binding(get: { store.draft.date ?? Cal.nextSaturday }, set: { store.draft.date = Cal.startOfDay($0) }), in: Cal.startOfDay(Cal.today)..., displayedComponents: .date)
                .datePickerStyle(.graphical).tint(MColor.accent).environment(\.calendar, Cal.calendar)
        } actions: {
            MButton(title: "Done") { if store.draft.date == nil { store.draft.date = Cal.nextSaturday }; showDate = false }
        }
        .presentationDetents([.large])
    }

    private var typeSheet: some View {
        SheetScaffold(title: "Event type") {
            RowGroup {
                ForEach(Array(EventType.allCases.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { Hairline() }
                    Button { store.draft.type = t; showType = false } label: {
                        ListRow(title: t.label, selected: store.draft.type == t) { EmptyView() } trailing: { if store.draft.type == t { Image(systemName: "checkmark").foregroundStyle(MColor.accentText) } }
                    }.buttonStyle(.plain)
                }
            }
        } actions: { EmptyView() }
        .presentationDetents([.medium])
    }

    private var amountSheet: some View {
        SheetScaffold(title: "Quoted amount", subtitle: "What the client pays in total") {
            AmountInput(amount: store.draft.quoted, label: nil)
            NumericKeypad(amount: draft.quoted)
        } actions: { MButton(title: "Done") { showAmount = false } }
        .presentationDetents([.large])
    }
}
